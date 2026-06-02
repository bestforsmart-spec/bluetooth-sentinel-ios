import CoreBluetooth
import CoreLocation
import Foundation
import UIKit
import UserNotifications

enum DeviceTrustState: Equatable {
    case unknown
    case quiet
    case trusted
}

struct DetectedDevice: Identifiable, Equatable {
    let id: String
    var name: String
    var deviceKind: DeviceKind
    var rssi: Int
    var smoothedRSSI: Double
    var strongestHeadingDegrees: Double?
    var strongestHeadingRSSI: Double?
    var firstSeen: Date
    var lastSeen: Date
    var advertisement: String
    var trustState: DeviceTrustState
    var alertCount: Int

    var isTrusted: Bool {
        trustState == .trusted
    }

    var shouldAlert: Bool {
        trustState == .unknown
    }

    var estimatedDistanceMeters: Double? {
        BluetoothDistanceEstimator.estimateMeters(fromRSSI: smoothedRSSI)
    }

    var estimatedDistanceText: String {
        guard let meters = estimatedDistanceMeters else { return "~-- м" }

        if meters < 1 {
            return "~<1 м"
        }

        if meters < 10 {
            return String(format: "~%.1f м", meters)
        }

        if meters < 100 {
            return String(format: "~%.0f м", meters)
        }

        return "~100+ м"
    }

    var directionName: String {
        guard let heading = strongestHeadingDegrees else { return "Поверните" }
        return CompassDirection.name(for: heading)
    }

    var directionShortName: String {
        guard let heading = strongestHeadingDegrees else { return "--" }
        return CompassDirection.shortName(for: heading)
    }

    var directionArrowDegrees: Double? {
        strongestHeadingDegrees
    }
}

enum DeviceKind: Equatable {
    case phone
    case computer
    case drone
    case audio
    case watch
    case tracker
    case vehicle
    case keyboardMouse
    case smartHome
    case appleDevice
    case unknown

    var title: String {
        switch self {
        case .phone:
            return "Телефон"
        case .computer:
            return "Компьютер"
        case .drone:
            return "Дрон"
        case .audio:
            return "Аудио"
        case .watch:
            return "Часы/браслет"
        case .tracker:
            return "Трекер/метка"
        case .vehicle:
            return "Авто"
        case .keyboardMouse:
            return "Клавиатура/мышь"
        case .smartHome:
            return "IoT/датчик"
        case .appleDevice:
            return "Apple устройство"
        case .unknown:
            return "Неизвестно"
        }
    }

    var symbolName: String {
        switch self {
        case .phone:
            return "iphone"
        case .computer:
            return "laptopcomputer"
        case .drone:
            return "airplane"
        case .audio:
            return "headphones"
        case .watch:
            return "applewatch"
        case .tracker:
            return "tag.fill"
        case .vehicle:
            return "car.fill"
        case .keyboardMouse:
            return "keyboard"
        case .smartHome:
            return "sensor.tag.radiowaves.forward.fill"
        case .appleDevice:
            return "apple.logo"
        case .unknown:
            return "questionmark.circle.fill"
        }
    }

    var confidenceText: String {
        self == .unknown ? "тип не определён" : "предположительно"
    }
}

final class BluetoothMonitor: NSObject, ObservableObject {
    private static let autoRememberInterval: TimeInterval = 10
    private static let alertsEnabledKey = "alertsEnabled"
    private static let vibrationOnlyEnabledKey = "vibrationOnlyEnabled"

    @Published private(set) var authorization: CBManagerAuthorization = CBCentralManager.authorization
    @Published private(set) var bluetoothState: CBManagerState = .unknown
    @Published private(set) var devices: [DetectedDevice] = []
    @Published private(set) var isScanning = false
    @Published private(set) var lastAlertAt: Date?
    @Published private(set) var headingDegrees: Double?
    @Published var alertsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(alertsEnabled, forKey: Self.alertsEnabledKey)
        }
    }
    @Published var vibrationOnlyEnabled: Bool {
        didSet {
            UserDefaults.standard.set(vibrationOnlyEnabled, forKey: Self.vibrationOnlyEnabledKey)
        }
    }

    private let legacyKnownDevicesKey = "knownBluetoothDeviceIDs"
    private let quietDevicesKey = "quietBluetoothDeviceIDs"
    private let trustedDevicesKey = "trustedBluetoothDeviceIDs"
    private let notificationCenter = BluetoothAlertNotificationCenter()
    private let soundPlayer = AlertSoundPlayer()
    private let locationManager = CLLocationManager()
    private var centralManager: CBCentralManager?
    private var quietDeviceIDs: Set<String>
    private var trustedDeviceIDs: Set<String>
    private var devicesByID: [String: DetectedDevice] = [:]
    private var deviceOrder: [String] = []
    private var alertedDeviceIDs: Set<String> = []
    private var autoRememberTimer: Timer?
    private var scanningRequested = true

    override init() {
        let storedTrustedIDs = UserDefaults.standard.stringArray(forKey: trustedDevicesKey)
            ?? UserDefaults.standard.stringArray(forKey: legacyKnownDevicesKey)
            ?? []
        let storedQuietIDs = UserDefaults.standard.stringArray(forKey: quietDevicesKey) ?? []
        self.trustedDeviceIDs = Set(storedTrustedIDs)
        self.quietDeviceIDs = Set(storedQuietIDs).subtracting(storedTrustedIDs)
        self.alertsEnabled = UserDefaults.standard.object(forKey: Self.alertsEnabledKey) as? Bool ?? true
        self.vibrationOnlyEnabled = UserDefaults.standard.object(forKey: Self.vibrationOnlyEnabledKey) as? Bool ?? false
        super.init()
        self.locationManager.delegate = self
        self.locationManager.headingFilter = 5
        self.centralManager = CBCentralManager(
            delegate: self,
            queue: .main,
            options: [
                CBCentralManagerOptionRestoreIdentifierKey: "com.bestforsmart.bluetoothsentinel.central"
            ]
        )
        notificationCenter.requestAuthorization()
        startHeadingUpdatesIfPossible()
        startAutoRememberTimer()
    }

    deinit {
        autoRememberTimer?.invalidate()
    }

    var trustedDeviceCount: Int {
        trustedDeviceIDs.count
    }

    var unknownDeviceCount: Int {
        devices.filter { $0.trustState == .unknown }.count
    }

    var quietDeviceCount: Int {
        devices.filter { $0.trustState == .quiet }.count
    }

    func startScanning() {
        scanningRequested = true
        guard bluetoothState == .poweredOn else { return }
        centralManager?.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        isScanning = true
    }

    func stopScanning() {
        scanningRequested = false
        centralManager?.stopScan()
        isScanning = false
    }

    func toggleScanning() {
        isScanning ? stopScanning() : startScanning()
    }

    func trustAllVisibleDevices() {
        for id in devicesByID.keys {
            trustedDeviceIDs.insert(id)
            quietDeviceIDs.remove(id)
        }
        persistDeviceLists()
        refreshTrustStates()
    }

    func trustDevice(_ device: DetectedDevice) {
        trustedDeviceIDs.insert(device.id)
        quietDeviceIDs.remove(device.id)
        persistDeviceLists()
        refreshTrustStates()
    }

    func resetTrustedDevices() {
        trustedDeviceIDs.removeAll()
        quietDeviceIDs.removeAll()
        alertedDeviceIDs.removeAll()
        persistDeviceLists()
        refreshTrustStates()
    }

    func clearSession() {
        devicesByID.removeAll()
        deviceOrder.removeAll()
        devices.removeAll()
        alertedDeviceIDs.removeAll()
    }

    func testAlert() {
        playConfiguredForegroundAlert()
    }

    func handleAppDidBecomeActive() {
        if scanningRequested, bluetoothState == .poweredOn {
            startScanning()
        }
    }

    func handleAppDidEnterBackground() {
        if scanningRequested, bluetoothState == .poweredOn {
            startScanning()
        }
    }

    private func persistDeviceLists() {
        UserDefaults.standard.set(Array(trustedDeviceIDs).sorted(), forKey: trustedDevicesKey)
        UserDefaults.standard.set(Array(trustedDeviceIDs).sorted(), forKey: legacyKnownDevicesKey)
        UserDefaults.standard.set(Array(quietDeviceIDs).sorted(), forKey: quietDevicesKey)
    }

    private func refreshTrustStates() {
        for id in devicesByID.keys {
            devicesByID[id]?.trustState = trustState(for: id)
        }
        publishDeviceList()
    }

    private func trustState(for id: String) -> DeviceTrustState {
        if trustedDeviceIDs.contains(id) {
            return .trusted
        }

        if quietDeviceIDs.contains(id) {
            return .quiet
        }

        return .unknown
    }

    private func publishDeviceList() {
        devices = deviceOrder.compactMap { devicesByID[$0] }
    }

    private func handleNewUnknownDevice(_ device: DetectedDevice) {
        guard alertsEnabled, !alertedDeviceIDs.contains(device.id) else { return }
        alertedDeviceIDs.insert(device.id)
        lastAlertAt = Date()

        if UIApplication.shared.applicationState == .active {
            playConfiguredForegroundAlert()
        } else {
            notificationCenter.postDeviceAlert(device, vibrationOnly: vibrationOnlyEnabled)
            if vibrationOnlyEnabled {
                soundPlayer.playVibration()
            }
        }
    }

    private func playConfiguredForegroundAlert() {
        if vibrationOnlyEnabled {
            soundPlayer.playVibration()
        } else {
            soundPlayer.playAlert()
        }
    }

    private func startAutoRememberTimer() {
        autoRememberTimer?.invalidate()
        autoRememberTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.rememberLongVisibleUnknownDevices()
        }
    }

    private func rememberLongVisibleUnknownDevices(now: Date = Date()) {
        var changed = false

        for id in deviceOrder {
            guard var device = devicesByID[id],
                  device.trustState == .unknown,
                  now.timeIntervalSince(device.firstSeen) >= Self.autoRememberInterval
            else {
                continue
            }

            quietDeviceIDs.insert(id)
            device.trustState = .quiet
            devicesByID[id] = device
            changed = true
        }

        guard changed else { return }

        persistDeviceLists()
        publishDeviceList()
    }

    private func startHeadingUpdatesIfPossible() {
        guard CLLocationManager.headingAvailable() else { return }

        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            locationManager.startUpdatingHeading()
        case .denied, .restricted:
            break
        @unknown default:
            break
        }
    }

    private func updateDirectionEstimate(for device: inout DetectedDevice) {
        guard let headingDegrees else { return }

        let currentRSSI = device.smoothedRSSI
        guard let strongestRSSI = device.strongestHeadingRSSI,
              let strongestHeading = device.strongestHeadingDegrees else {
            device.strongestHeadingRSSI = currentRSSI
            device.strongestHeadingDegrees = headingDegrees
            return
        }

        if currentRSSI > strongestRSSI + 1.2 {
            device.strongestHeadingRSSI = currentRSSI
            device.strongestHeadingDegrees = headingDegrees
        } else if abs(currentRSSI - strongestRSSI) <= 1.8 {
            device.strongestHeadingDegrees = CompassDirection.blendDegrees(
                from: strongestHeading,
                to: headingDegrees,
                weight: 0.14
            )
            device.strongestHeadingRSSI = max(strongestRSSI, currentRSSI)
        }
    }
}

extension BluetoothMonitor: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        authorization = CBCentralManager.authorization
        bluetoothState = central.state

        if central.state == .poweredOn, scanningRequested {
            startScanning()
        } else {
            isScanning = false
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let id = peripheral.identifier.uuidString
        let now = Date()
        let name = peripheral.name
            ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
            ?? "Без имени"
        let summary = AdvertisementFormatter.summary(from: advertisementData)
        let deviceKind = DeviceKindClassifier.classify(name: name, advertisementData: advertisementData)
        let currentTrustState = trustState(for: id)

        if var existing = devicesByID[id] {
            let latestRSSI = RSSI.intValue
            existing.name = name
            existing.deviceKind = deviceKind
            existing.rssi = latestRSSI
            existing.smoothedRSSI = (existing.smoothedRSSI * 0.72) + (Double(latestRSSI) * 0.28)
            updateDirectionEstimate(for: &existing)
            existing.lastSeen = now
            existing.advertisement = summary
            existing.trustState = currentTrustState
            if existing.trustState == .unknown,
               now.timeIntervalSince(existing.firstSeen) >= Self.autoRememberInterval {
                quietDeviceIDs.insert(id)
                existing.trustState = .quiet
                persistDeviceLists()
            }
            devicesByID[id] = existing
        } else {
            let newDevice = DetectedDevice(
                id: id,
                name: name,
                deviceKind: deviceKind,
                rssi: RSSI.intValue,
                smoothedRSSI: Double(RSSI.intValue),
                strongestHeadingDegrees: headingDegrees,
                strongestHeadingRSSI: headingDegrees == nil ? nil : Double(RSSI.intValue),
                firstSeen: now,
                lastSeen: now,
                advertisement: summary,
                trustState: currentTrustState,
                alertCount: currentTrustState == .unknown ? 1 : 0
            )
            devicesByID[id] = newDevice
            deviceOrder.append(id)
            if currentTrustState == .unknown {
                handleNewUnknownDevice(newDevice)
            }
        }

        publishDeviceList()
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        bluetoothState = central.state
    }
}

extension BluetoothMonitor: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        startHeadingUpdatesIfPossible()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard newHeading.headingAccuracy >= 0 else { return }

        let heading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        headingDegrees = CompassDirection.normalize(heading)
    }

    func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
        true
    }
}

final class BluetoothAlertNotificationCenter {
    private let center = UNUserNotificationCenter.current()

    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func postDeviceAlert(_ device: DetectedDevice, vibrationOnly: Bool) {
        let content = UNMutableNotificationContent()
        content.title = "Новое Bluetooth-устройство"
        content.body = "\(device.name) рядом: \(device.deviceKind.title), \(device.estimatedDistanceText), \(device.directionName)"
        content.categoryIdentifier = "bluetooth-device-alert"
        if !vibrationOnly {
            content.sound = .default
        }

        let request = UNNotificationRequest(
            identifier: "bluetooth-device-\(device.id)-\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: nil
        )
        center.add(request)
    }
}

enum BluetoothDistanceEstimator {
    private static let referenceRSSIAtOneMeter = -59.0
    private static let indoorPathLossExponent = 2.2

    static func estimateMeters(fromRSSI rssi: Double) -> Double? {
        guard rssi < 0, rssi > -120 else { return nil }

        let exponent = (referenceRSSIAtOneMeter - rssi) / (10.0 * indoorPathLossExponent)
        return min(max(pow(10.0, exponent), 0.2), 120.0)
    }
}

enum CompassDirection {
    private static let names = [
        "Север",
        "Северо-восток",
        "Восток",
        "Юго-восток",
        "Юг",
        "Юго-запад",
        "Запад",
        "Северо-запад"
    ]

    private static let shortNames = [
        "С",
        "СВ",
        "В",
        "ЮВ",
        "Ю",
        "ЮЗ",
        "З",
        "СЗ"
    ]

    static func name(for degrees: Double) -> String {
        names[index(for: degrees)]
    }

    static func shortName(for degrees: Double) -> String {
        shortNames[index(for: degrees)]
    }

    static func normalize(_ degrees: Double) -> Double {
        let value = degrees.truncatingRemainder(dividingBy: 360)
        return value >= 0 ? value : value + 360
    }

    static func blendDegrees(from start: Double, to end: Double, weight: Double) -> Double {
        let startRadians = start * .pi / 180
        let endRadians = end * .pi / 180
        let x = ((1 - weight) * cos(startRadians)) + (weight * cos(endRadians))
        let y = ((1 - weight) * sin(startRadians)) + (weight * sin(endRadians))
        return normalize(atan2(y, x) * 180 / .pi)
    }

    private static func index(for degrees: Double) -> Int {
        Int((normalize(degrees) + 22.5) / 45.0) % names.count
    }
}

enum AdvertisementFormatter {
    static func summary(from advertisementData: [String: Any]) -> String {
        var parts: [String] = []

        if let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID], !serviceUUIDs.isEmpty {
            parts.append("Services: " + serviceUUIDs.map(\.uuidString).joined(separator: ", "))
        }

        if let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data {
            parts.append("Manufacturer: \(manufacturerData.count) bytes")
        }

        if let connectable = advertisementData[CBAdvertisementDataIsConnectable] as? Bool {
            parts.append(connectable ? "Connectable" : "Not connectable")
        }

        return parts.isEmpty ? "Нет подробностей" : parts.joined(separator: " · ")
    }
}

enum DeviceKindClassifier {
    static func classify(name: String, advertisementData: [String: Any]) -> DeviceKind {
        let normalizedName = name.lowercased()
        let serviceUUIDs = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? [])
            .map { $0.uuidString.uppercased() }
        let manufacturerID = manufacturerCompanyID(from: advertisementData)

        if matches(normalizedName, [
            "dji", "mavic", "phantom", "inspire", "avata", "matrice", "spark",
            "drone", "quad", "quadcopter", "fpv", "autel", "skydio", "parrot", "anafi"
        ]) {
            return .drone
        }

        if matches(normalizedName, [
            "iphone", "android", "galaxy", "pixel", "phone", "redmi", "xiaomi",
            "huawei", "honor", "oneplus", "oppo", "vivo", "realme", "moto"
        ]) {
            return .phone
        }

        if matches(normalizedName, [
            "macbook", "imac", "mac mini", "mac studio", "windows", "laptop",
            "desktop", "surface", "thinkpad", "lenovo", "dell", "hp-", "asus", "acer", "pc"
        ]) {
            return .computer
        }

        if matches(normalizedName, [
            "airpods", "beats", "buds", "headphone", "headset", "earbuds",
            "speaker", "sound", "jbl", "bose", "sony wh", "sony wf", "marshall", "anker"
        ]) {
            return .audio
        }

        if matches(normalizedName, [
            "watch", "apple watch", "fitbit", "garmin", "mi band", "smart band",
            "amazfit", "whoop", "polar", "coros"
        ]) {
            return .watch
        }

        if matches(normalizedName, [
            "airtag", "tile", "smarttag", "tag", "tracker", "beacon", "ibeacon"
        ]) || serviceUUIDs.contains("FEAA") {
            return .tracker
        }

        if matches(normalizedName, [
            "tesla", "bmw", "mercedes", "audi", "toyota", "honda", "ford",
            "hyundai", "kia", "car", "vehicle", "obd"
        ]) {
            return .vehicle
        }

        if matches(normalizedName, ["keyboard", "mouse", "trackpad"]) || serviceUUIDs.contains("1812") {
            return .keyboardMouse
        }

        if matches(normalizedName, [
            "sensor", "thermo", "temperature", "humidity", "lock", "camera",
            "door", "bulb", "lamp", "light", "plug", "switch", "printer", "router", "tv"
        ]) || serviceUUIDs.contains("1809") {
            return .smartHome
        }

        if manufacturerID == 0x004C {
            if normalizedName.contains("ipad") {
                return .phone
            }
            return .appleDevice
        }

        return .unknown
    }

    private static func matches(_ value: String, _ keywords: [String]) -> Bool {
        keywords.contains { value.contains($0) }
    }

    private static func manufacturerCompanyID(from advertisementData: [String: Any]) -> UInt16? {
        guard let data = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
              data.count >= 2 else {
            return nil
        }

        return UInt16(data[0]) | (UInt16(data[1]) << 8)
    }
}

extension CBManagerState {
    var title: String {
        switch self {
        case .unknown:
            return "Проверка"
        case .resetting:
            return "Сброс"
        case .unsupported:
            return "Не поддерживается"
        case .unauthorized:
            return "Нет доступа"
        case .poweredOff:
            return "Bluetooth выключен"
        case .poweredOn:
            return "Bluetooth включен"
        @unknown default:
            return "Неизвестно"
        }
    }
}
