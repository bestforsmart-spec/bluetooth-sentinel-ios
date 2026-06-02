import CoreBluetooth
import CoreLocation
import Foundation

struct DetectedDevice: Identifiable, Equatable {
    let id: String
    var name: String
    var rssi: Int
    var smoothedRSSI: Double
    var strongestHeadingDegrees: Double?
    var strongestHeadingRSSI: Double?
    var firstSeen: Date
    var lastSeen: Date
    var advertisement: String
    var isKnown: Bool
    var alertCount: Int

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

final class BluetoothMonitor: NSObject, ObservableObject {
    private static let autoRememberInterval: TimeInterval = 30

    @Published private(set) var authorization: CBManagerAuthorization = CBCentralManager.authorization
    @Published private(set) var bluetoothState: CBManagerState = .unknown
    @Published private(set) var devices: [DetectedDevice] = []
    @Published private(set) var isScanning = false
    @Published private(set) var lastAlertAt: Date?
    @Published private(set) var headingDegrees: Double?
    @Published var alertsEnabled = true

    private let knownDevicesKey = "knownBluetoothDeviceIDs"
    private let soundPlayer = AlertSoundPlayer()
    private let locationManager = CLLocationManager()
    private var centralManager: CBCentralManager?
    private var knownDeviceIDs: Set<String>
    private var devicesByID: [String: DetectedDevice] = [:]
    private var deviceOrder: [String] = []
    private var alertedDeviceIDs: Set<String> = []
    private var autoRememberTimer: Timer?

    override init() {
        let storedIDs = UserDefaults.standard.stringArray(forKey: knownDevicesKey) ?? []
        self.knownDeviceIDs = Set(storedIDs)
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
        startHeadingUpdatesIfPossible()
        startAutoRememberTimer()
    }

    deinit {
        autoRememberTimer?.invalidate()
    }

    var knownDeviceCount: Int {
        knownDeviceIDs.count
    }

    var unknownDeviceCount: Int {
        devices.filter { !$0.isKnown }.count
    }

    func startScanning() {
        guard bluetoothState == .poweredOn else { return }
        centralManager?.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        isScanning = true
    }

    func stopScanning() {
        centralManager?.stopScan()
        isScanning = false
    }

    func toggleScanning() {
        isScanning ? stopScanning() : startScanning()
    }

    func markAllVisibleAsKnown() {
        for id in devicesByID.keys {
            knownDeviceIDs.insert(id)
        }
        persistKnownDevices()
        refreshKnownFlags()
    }

    func markAsKnown(_ device: DetectedDevice) {
        knownDeviceIDs.insert(device.id)
        persistKnownDevices()
        refreshKnownFlags()
    }

    func forgetKnownDevices() {
        knownDeviceIDs.removeAll()
        alertedDeviceIDs.removeAll()
        persistKnownDevices()
        refreshKnownFlags()
    }

    func clearSession() {
        devicesByID.removeAll()
        deviceOrder.removeAll()
        devices.removeAll()
        alertedDeviceIDs.removeAll()
    }

    func testAlert() {
        soundPlayer.playAlert()
    }

    private func persistKnownDevices() {
        UserDefaults.standard.set(Array(knownDeviceIDs).sorted(), forKey: knownDevicesKey)
    }

    private func refreshKnownFlags() {
        for id in devicesByID.keys {
            devicesByID[id]?.isKnown = knownDeviceIDs.contains(id)
        }
        publishDeviceList()
    }

    private func publishDeviceList() {
        devices = deviceOrder.compactMap { devicesByID[$0] }
    }

    private func handleNewUnknownDevice(_ id: String) {
        guard alertsEnabled, !alertedDeviceIDs.contains(id) else { return }
        alertedDeviceIDs.insert(id)
        lastAlertAt = Date()
        soundPlayer.playAlert()
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
                  !device.isKnown,
                  now.timeIntervalSince(device.firstSeen) >= Self.autoRememberInterval
            else {
                continue
            }

            knownDeviceIDs.insert(id)
            device.isKnown = true
            devicesByID[id] = device
            changed = true
        }

        guard changed else { return }

        persistKnownDevices()
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

        if central.state == .poweredOn {
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
        let isKnown = knownDeviceIDs.contains(id)

        if var existing = devicesByID[id] {
            let latestRSSI = RSSI.intValue
            existing.name = name
            existing.rssi = latestRSSI
            existing.smoothedRSSI = (existing.smoothedRSSI * 0.72) + (Double(latestRSSI) * 0.28)
            updateDirectionEstimate(for: &existing)
            existing.lastSeen = now
            existing.advertisement = summary
            existing.isKnown = isKnown || now.timeIntervalSince(existing.firstSeen) >= Self.autoRememberInterval
            if existing.isKnown {
                knownDeviceIDs.insert(id)
                persistKnownDevices()
            }
            devicesByID[id] = existing
        } else {
            let newDevice = DetectedDevice(
                id: id,
                name: name,
                rssi: RSSI.intValue,
                smoothedRSSI: Double(RSSI.intValue),
                strongestHeadingDegrees: headingDegrees,
                strongestHeadingRSSI: headingDegrees == nil ? nil : Double(RSSI.intValue),
                firstSeen: now,
                lastSeen: now,
                advertisement: summary,
                isKnown: isKnown,
                alertCount: isKnown ? 0 : 1
            )
            devicesByID[id] = newDevice
            deviceOrder.append(id)
            if !isKnown {
                handleNewUnknownDevice(id)
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
