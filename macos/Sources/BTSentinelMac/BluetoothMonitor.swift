import AppKit
import Combine
import CoreBluetooth
import Foundation

final class BluetoothMonitor: NSObject, ObservableObject, CBCentralManagerDelegate {
    private enum Constants {
        static let quietStart: TimeInterval = 60
        static let rssiWindow: TimeInterval = 8
        static let approachWindow: TimeInterval = 12
        static let historyWindow: TimeInterval = 15
        static let staleAfter: TimeInterval = 60
        static let autoKnownAfter: TimeInterval = 5 * 60
        static let minAutoKnownSamples = 20
        static let rssiDeadband = 3
        static let approachGain = 8
    }

    @Published private(set) var devices: [DetectedDevice] = []
    @Published private(set) var stateText = "Подготовка Bluetooth"
    @Published var soundEnabled = true
    @Published var selectedID: String?

    private var central: CBCentralManager?
    private var devicesByID: [String: DetectedDevice] = [:]
    private var knownIDs: Set<String>
    private var discoveryAlerted: Set<String> = []
    private var approachAlerted: Set<String> = []
    private var unnamedLabels: [String: String] = [:]
    private var nextUnnamedNumber = 1
    private var quietStartEndsAt = Date().addingTimeInterval(Constants.quietStart)
    private var renderTimer: Timer?
    private let knownDefaultsKey = "btSentinelMacKnownIDs"

    var isQuietStart: Bool {
        Date() < quietStartEndsAt
    }

    var quietSecondsLeft: Int {
        max(0, Int(ceil(quietStartEndsAt.timeIntervalSinceNow)))
    }

    var newCount: Int {
        devices.filter { !$0.isKnown }.count
    }

    var knownCount: Int {
        devices.filter(\.isKnown).count
    }

    var selectedDevice: DetectedDevice? {
        guard let selectedID else { return nil }
        return devicesByID[selectedID]
    }

    override init() {
        let stored = UserDefaults.standard.stringArray(forKey: knownDefaultsKey) ?? []
        knownIDs = Set(stored)
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
        renderTimer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
    }

    deinit {
        renderTimer?.invalidate()
        central?.stopScan()
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            stateText = "Сканирование активно"
            startScan()
        case .poweredOff:
            stateText = "Bluetooth выключен"
        case .unauthorized:
            stateText = "Нет доступа к Bluetooth"
        case .unsupported:
            stateText = "Bluetooth LE не поддерживается"
        default:
            stateText = "Ожидание Bluetooth"
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let now = Date()
        let id = peripheral.identifier.uuidString
        let rawName = bestName(peripheral: peripheral, advertisementData: advertisementData)
        let rssi = RSSI.intValue
        var device = devicesByID[id] ?? DetectedDevice(
            id: id,
            name: displayName(id: id, rawName: rawName),
            kind: classify(advertisementData),
            rawRSSI: rssi,
            displayRSSI: rssi,
            firstSeen: now,
            lastSeen: now,
            samples: [],
            totalSamples: 0,
            isKnown: isQuietStart || knownIDs.contains(id),
            isApproaching: false,
            isJittery: false,
            orderBoostAt: now
        )

        let wasNew = devicesByID[id] == nil
        device.name = displayName(id: id, rawName: rawName)
        device.kind = classify(advertisementData)
        device.rawRSSI = rssi
        device.lastSeen = now
        device.samples.append(SignalSample(time: now, rssi: rssi))
        device.totalSamples += 1
        trimSamples(&device, now: now)
        analyze(&device, now: now)

        if wasNew, !device.isKnown, !isQuietStart {
            device.orderBoostAt = now
            if !discoveryAlerted.contains(id) {
                discoveryAlerted.insert(id)
                playDiscoveryAlert()
            }
        }

        maybePromoteKnown(&device, now: now)
        devicesByID[id] = device
        publishDevices()
    }

    func trustCurrentDevices() {
        for id in devicesByID.keys {
            knownIDs.insert(id)
            devicesByID[id]?.isKnown = true
        }
        saveKnown()
        publishDevices()
    }

    func resetTrust() {
        knownIDs.removeAll()
        for id in devicesByID.keys {
            devicesByID[id]?.isKnown = isQuietStart
        }
        saveKnown()
        publishDevices()
    }

    private func startScan() {
        central?.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
    }

    @objc private func tick() {
        let now = Date()
        for id in Array(devicesByID.keys) {
            guard var device = devicesByID[id] else { continue }
            if now.timeIntervalSince(device.lastSeen) > Constants.staleAfter {
                devicesByID.removeValue(forKey: id)
                discoveryAlerted.remove(id)
                approachAlerted.remove(id)
                continue
            }
            trimSamples(&device, now: now)
            analyze(&device, now: now)
            maybePromoteKnown(&device, now: now)
            devicesByID[id] = device
        }
        publishDevices()
    }

    private func analyze(_ device: inout DetectedDevice, now: Date) {
        let displayWindow = device.samples.filter { now.timeIntervalSince($0.time) <= Constants.rssiWindow }
        let stableRSSI = SignalMath.trimmedMedian(displayWindow.isEmpty ? device.samples : displayWindow)
        device.isJittery = SignalMath.spread(displayWindow) >= 12
        if abs(stableRSSI - device.displayRSSI) >= Constants.rssiDeadband || device.totalSamples < 2 {
            device.displayRSSI = stableRSSI
        }

        let oldWindow = device.samples.filter {
            let age = now.timeIntervalSince($0.time)
            return age >= Constants.approachWindow - 2 && age <= Constants.approachWindow + 3
        }
        let oldRSSI = SignalMath.trimmedMedian(oldWindow)
        let gain = stableRSSI - oldRSSI
        device.isApproaching = device.samples.count >= 8 && oldRSSI > -120 && gain >= Constants.approachGain
        if device.isApproaching, !isQuietStart, !approachAlerted.contains(device.id) {
            approachAlerted.insert(device.id)
            device.orderBoostAt = now
            playApproachAlert()
        }
    }

    private func maybePromoteKnown(_ device: inout DetectedDevice, now: Date) {
        guard !device.isKnown, !device.isApproaching, !approachAlerted.contains(device.id) else { return }
        let stableLongEnough = now.timeIntervalSince(device.firstSeen) >= Constants.autoKnownAfter
        let enoughSamples = device.totalSamples >= Constants.minAutoKnownSamples
        let fresh = now.timeIntervalSince(device.lastSeen) < 12
        if stableLongEnough, enoughSamples, fresh {
            device.isKnown = true
            knownIDs.insert(device.id)
            saveKnown()
        }
    }

    private func trimSamples(_ device: inout DetectedDevice, now: Date) {
        device.samples.removeAll { now.timeIntervalSince($0.time) > Constants.historyWindow }
    }

    private func publishDevices() {
        devices = devicesByID.values.sorted {
            if $0.isApproaching != $1.isApproaching { return $0.isApproaching && !$1.isApproaching }
            if $0.isKnown != $1.isKnown { return !$0.isKnown && $1.isKnown }
            if $0.orderBoostAt != $1.orderBoostAt { return $0.orderBoostAt > $1.orderBoostAt }
            return $0.lastSeen > $1.lastSeen
        }
        if selectedID == nil {
            selectedID = devices.first?.id
        }
    }

    private func bestName(peripheral: CBPeripheral, advertisementData: [String: Any]) -> String {
        if let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String, !localName.isEmpty {
            return localName
        }
        return peripheral.name ?? ""
    }

    private func displayName(id: String, rawName: String) -> String {
        guard isUnnamed(rawName) else { return rawName }
        if let existing = unnamedLabels[id] { return existing }
        let label = "Новый \(nextUnnamedNumber)"
        nextUnnamedNumber += 1
        unnamedLabels[id] = label
        return label
    }

    private func isUnnamed(_ rawName: String) -> Bool {
        let normalized = rawName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty || normalized == "без имени" || normalized == "unknown" || normalized == "unnamed"
    }

    private func classify(_ advertisementData: [String: Any]) -> String {
        if let services = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID], !services.isEmpty {
            return "BLE service"
        }
        if let connectable = advertisementData[CBAdvertisementDataIsConnectable] as? Bool, connectable {
            return "BLE connectable"
        }
        return "BLE beacon"
    }

    private func playDiscoveryAlert() {
        guard soundEnabled else { return }
        NSSound.beep()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            NSSound.beep()
        }
    }

    private func playApproachAlert() {
        guard soundEnabled else { return }
        NSSound.beep()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { NSSound.beep() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) { NSSound.beep() }
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }

    private func saveKnown() {
        UserDefaults.standard.set(Array(knownIDs), forKey: knownDefaultsKey)
    }
}
