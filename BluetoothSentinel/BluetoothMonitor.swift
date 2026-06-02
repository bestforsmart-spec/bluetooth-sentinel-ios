import CoreBluetooth
import Foundation

struct DetectedDevice: Identifiable, Equatable {
    let id: String
    var name: String
    var rssi: Int
    var smoothedRSSI: Double
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
}

final class BluetoothMonitor: NSObject, ObservableObject {
    @Published private(set) var authorization: CBManagerAuthorization = CBCentralManager.authorization
    @Published private(set) var bluetoothState: CBManagerState = .unknown
    @Published private(set) var devices: [DetectedDevice] = []
    @Published private(set) var isScanning = false
    @Published private(set) var lastAlertAt: Date?
    @Published var alertsEnabled = true

    private let knownDevicesKey = "knownBluetoothDeviceIDs"
    private let soundPlayer = AlertSoundPlayer()
    private var centralManager: CBCentralManager?
    private var knownDeviceIDs: Set<String>
    private var devicesByID: [String: DetectedDevice] = [:]
    private var deviceOrder: [String] = []
    private var alertedDeviceIDs: Set<String> = []

    override init() {
        let storedIDs = UserDefaults.standard.stringArray(forKey: knownDevicesKey) ?? []
        self.knownDeviceIDs = Set(storedIDs)
        super.init()
        self.centralManager = CBCentralManager(
            delegate: self,
            queue: .main,
            options: [
                CBCentralManagerOptionRestoreIdentifierKey: "com.bestforsmart.bluetoothsentinel.central"
            ]
        )
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
            existing.lastSeen = now
            existing.advertisement = summary
            existing.isKnown = isKnown
            devicesByID[id] = existing
        } else {
            let newDevice = DetectedDevice(
                id: id,
                name: name,
                rssi: RSSI.intValue,
                smoothedRSSI: Double(RSSI.intValue),
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

enum BluetoothDistanceEstimator {
    private static let referenceRSSIAtOneMeter = -59.0
    private static let indoorPathLossExponent = 2.2

    static func estimateMeters(fromRSSI rssi: Double) -> Double? {
        guard rssi < 0, rssi > -120 else { return nil }

        let exponent = (referenceRSSIAtOneMeter - rssi) / (10.0 * indoorPathLossExponent)
        return min(max(pow(10.0, exponent), 0.2), 120.0)
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
