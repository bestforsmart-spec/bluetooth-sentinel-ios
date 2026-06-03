import CoreBluetooth
import CoreLocation
import Foundation
import UIKit
import UserNotifications

enum DeviceTrustState: Equatable {
    case unknown
    case known
    case quiet
    case trusted
}

struct SignalSample: Equatable {
    let timestamp: Date
    let rssi: Int
    let smoothedRSSI: Double
}

enum SignalEventKind: Equatable {
    case neutral
    case stronger
    case weaker
    case approaching
}

enum DirectionConfidence: Equatable {
    case scanning
    case low
    case medium
    case high
}

struct SignalEvent: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    let deviceName: String
    let detail: String
    let kind: SignalEventKind
}

enum InstrumentHealthLevel: Equatable {
    case nominal
    case warning
    case critical
}

struct InstrumentCheck: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let level: InstrumentHealthLevel
}

struct InstrumentStatus: Equatable {
    let title: String
    let detail: String
    let level: InstrumentHealthLevel
    let checks: [InstrumentCheck]
}

enum ThreatLevel: Int, Equatable {
    case normal
    case watch
    case strengthening
    case confirmedApproach
    case criticalApproach

    var title: String {
        switch self {
        case .normal:
            return "Норма"
        case .watch:
            return "Наблюдение"
        case .strengthening:
            return "Сигнал усиливается"
        case .confirmedApproach:
            return "Подтверждено"
        case .criticalApproach:
            return "Критично"
        }
    }
}

enum AlertConfidence: Equatable {
    case low
    case medium
    case high

    var title: String {
        switch self {
        case .low:
            return "низкая"
        case .medium:
            return "средняя"
        case .high:
            return "высокая"
        }
    }
}

struct InstrumentLogEntry: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    let title: String
    let detail: String
    let level: InstrumentHealthLevel
}

private struct ApproachSignalAnalysis {
    let hasEnoughHistory: Bool
    let rssiGain: Double
    let trendGain: Double
    let jitter: Double
    let risingSteps: Int
    let span: TimeInterval

    var hasStableTrend: Bool {
        hasEnoughHistory
            && span >= BluetoothMonitor.approachTrendMinimumSpan
            && trendGain >= BluetoothMonitor.approachTrendMinimumGain
            && risingSteps >= 3
    }

    var isJitterControlled: Bool {
        jitter <= BluetoothMonitor.approachMaximumJitter || rssiGain >= BluetoothMonitor.approachStrongGainOverride
    }

    var showsApproach: Bool {
        hasStableTrend
            && isJitterControlled
            && rssiGain >= BluetoothMonitor.approachRSSIGainThreshold
    }
}

struct DetectedDevice: Identifiable, Equatable {
    let id: String
    var name: String
    var deviceKind: DeviceKind
    var rssi: Int
    var smoothedRSSI: Double
    var strongestHeadingDegrees: Double?
    var strongestHeadingRSSI: Double?
    var directionSectorRSSIs: [Double?]
    var directionObservationCount: Int
    var firstSeen: Date
    var lastSeen: Date
    var advertisement: String
    var trustState: DeviceTrustState
    var approachState: ApproachState
    var alertCount: Int
    var signalSamples: [SignalSample]

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
        guard let heading = strongestHeadingDegrees,
              directionConfidence != .scanning else { return "Скан" }
        return CompassDirection.name(for: heading)
    }

    var directionShortName: String {
        guard let heading = strongestHeadingDegrees,
              directionConfidence != .scanning else { return "скан" }
        return CompassDirection.shortName(for: heading)
    }

    var directionArrowDegrees: Double? {
        guard directionConfidence != .scanning else { return nil }
        return strongestHeadingDegrees
    }

    var directionConfidence: DirectionConfidence {
        CompassDirection.confidence(from: directionSectorRSSIs, observations: directionObservationCount)
    }

    var directionConfidenceText: String {
        switch directionConfidence {
        case .scanning:
            return "--"
        case .low:
            return "низк"
        case .medium:
            return "сред"
        case .high:
            return "выс"
        }
    }

    var detectionZone: DetectionZone {
        DetectionZone.zone(forMeters: estimatedDistanceMeters)
    }

    var recentRSSIRangeText: String {
        let samples = signalSamples.suffix(12)
        guard let minimum = samples.map(\.rssi).min(),
              let maximum = samples.map(\.rssi).max() else {
            return "--"
        }

        return "\(minimum)...\(maximum)"
    }

    var signalTrendText: String {
        guard signalSamples.count >= 4,
              let first = signalSamples.suffix(8).first,
              let last = signalSamples.last else {
            return "наблюдение"
        }

        let gain = last.smoothedRSSI - first.smoothedRSSI
        let jitter = recentRSSIJitter

        if approachState == .approaching {
            return "сближение"
        }

        if gain >= 7 {
            return "усиливается"
        }

        if gain <= -7 {
            return "слабеет"
        }

        if jitter >= 10 {
            return "дрожит"
        }

        return "стабильно"
    }

    var recentRSSIJitter: Int {
        let samples = signalSamples.suffix(12)
        guard let minimum = samples.map(\.rssi).min(),
              let maximum = samples.map(\.rssi).max() else {
            return 0
        }

        return maximum - minimum
    }

    mutating func appendSignalSample(rssi: Int, smoothedRSSI: Double, now: Date, limit: Int, minimumSpacing: TimeInterval) {
        if let lastSample = signalSamples.last,
           now.timeIntervalSince(lastSample.timestamp) < minimumSpacing {
            signalSamples[signalSamples.count - 1] = SignalSample(timestamp: now, rssi: rssi, smoothedRSSI: smoothedRSSI)
            return
        }

        signalSamples.append(SignalSample(timestamp: now, rssi: rssi, smoothedRSSI: smoothedRSSI))
        if signalSamples.count > limit {
            signalSamples.removeFirst(signalSamples.count - limit)
        }
    }
}

enum ApproachState: Equatable {
    case watching
    case approaching

    var title: String {
        switch self {
        case .watching:
            return "Наблюдение"
        case .approaching:
            return "ПРИБЛИЖАЕТСЯ"
        }
    }

    var symbolName: String {
        switch self {
        case .watching:
            return "eye.fill"
        case .approaching:
            return "arrow.down.forward.and.arrow.up.backward.circle.fill"
        }
    }
}

enum DetectionZone: Equatable {
    case immediate
    case close
    case far
    case edge
    case unknown

    static func zone(forMeters meters: Double?) -> DetectionZone {
        guard let meters else { return .unknown }
        if meters < 5 { return .immediate }
        if meters < 15 { return .close }
        if meters < 60 { return .far }
        return .edge
    }

    var title: String {
        switch self {
        case .immediate:
            return "КРИТИЧЕСКИ БЛИЗКО"
        case .close:
            return "БЛИЗКО"
        case .far:
            return "ДАЛЬНЯЯ ЗОНА"
        case .edge:
            return "ПРЕДЕЛ ПРИЁМА"
        case .unknown:
            return "ДАЛЬНОСТЬ НЕЯСНА"
        }
    }

    var symbolName: String {
        switch self {
        case .immediate:
            return "exclamationmark.octagon.fill"
        case .close:
            return "exclamationmark.triangle.fill"
        case .far:
            return "antenna.radiowaves.left.and.right"
        case .edge:
            return "dot.radiowaves.left.and.right"
        case .unknown:
            return "questionmark.circle.fill"
        }
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
    private static let fieldScanRefreshInterval: TimeInterval = 25
    private static let maximumSensitivityScanRefreshInterval: TimeInterval = 10
    private static let staleDeviceInterval: TimeInterval = 60
    private static let staleCleanupInterval: TimeInterval = 5
    private static let approachMinimumObservationAge: TimeInterval = 12
    fileprivate static let approachRSSIGainThreshold = 12.0
    private static let approachDistanceDropRatio = 0.50
    private static let approachMinimumDistanceDrop = 6.0
    private static let approachRequiredEvidenceCount = 3
    private static let approachEvidenceMinimumSpacing: TimeInterval = 1.5
    private static let approachEvidenceResetInterval: TimeInterval = 10
    private static let approachTrendSampleCount = 6
    fileprivate static let approachTrendMinimumSpan: TimeInterval = 6
    fileprivate static let approachTrendMinimumGain = 4.0
    fileprivate static let approachMaximumJitter = 12.0
    fileprivate static let approachStrongGainOverride = 18.0
    private static let signalSampleLimit = 30
    private static let signalSampleMinimumSpacing: TimeInterval = 1
    private static let signalEventLimit = 50
    private static let blackBoxEventLimit = 200
    private static let signalEventRSSIThreshold = 8
    private static let signalEventMinimumSpacing: TimeInterval = 8
    private static let directionSectorCount = 8
    private static let initialBaselineDuration: TimeInterval = 60
    private static let packetFreshInterval: TimeInterval = 8
    private static let alertsEnabledKey = "alertsEnabled"
    private static let fieldModeEnabledKey = "fieldModeEnabled"
    private static let maximumSensitivityEnabledKey = "maximumSensitivityEnabled"
    private static let vibrationOnlyEnabledKey = "vibrationOnlyEnabled"
    private static let externalSensorEnabledKey = "externalSensorEnabled"
    private static let knownDevicesKey = "knownObservedBluetoothDeviceIDs"
    private static let initialBaselineCompletedKey = "initialBaselineCompleted"

    @Published private(set) var authorization: CBManagerAuthorization = CBCentralManager.authorization
    @Published private(set) var bluetoothState: CBManagerState = .unknown
    @Published private(set) var devices: [DetectedDevice] = []
    @Published private(set) var signalEvents: [SignalEvent] = []
    @Published private(set) var blackBoxEvents: [InstrumentLogEntry] = []
    @Published private(set) var isScanning = false
    @Published private(set) var lastAlertAt: Date?
    @Published private(set) var lastPacketAt: Date?
    @Published private(set) var packetCount = 0
    @Published private(set) var headingDegrees: Double?
    @Published var alertsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(alertsEnabled, forKey: Self.alertsEnabledKey)
        }
    }
    @Published var fieldModeEnabled: Bool {
        didSet {
            UserDefaults.standard.set(fieldModeEnabled, forKey: Self.fieldModeEnabledKey)
            if fieldModeEnabled {
                quietDeviceIDs.removeAll()
                approachAlertedDeviceIDs.removeAll()
                approachReferenceDistanceByID.removeAll()
                approachReferenceRSSIByID.removeAll()
                approachEvidenceCountByID.removeAll()
                approachLastEvidenceAtByID.removeAll()
                signalEventReferenceRSSIByID.removeAll()
                signalEventLastAtByID.removeAll()
                persistDeviceLists()
                refreshTrustStates()
                startScanning()
            }
        }
    }
    @Published var maximumSensitivityEnabled: Bool {
        didSet {
            UserDefaults.standard.set(maximumSensitivityEnabled, forKey: Self.maximumSensitivityEnabledKey)
            applyMaximumSensitivityPowerMode()
            startScanRefreshTimer()
            if scanningRequested, bluetoothState == .poweredOn {
                refreshFieldScanIfNeeded()
            }
        }
    }
    @Published var vibrationOnlyEnabled: Bool {
        didSet {
            UserDefaults.standard.set(vibrationOnlyEnabled, forKey: Self.vibrationOnlyEnabledKey)
        }
    }
    @Published var externalSensorEnabled: Bool {
        didSet {
            UserDefaults.standard.set(externalSensorEnabled, forKey: Self.externalSensorEnabledKey)
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
    private var knownDeviceIDs: Set<String>
    private var trustedDeviceIDs: Set<String>
    private var devicesByID: [String: DetectedDevice] = [:]
    private var deviceOrder: [String] = []
    private var approachAlertedDeviceIDs: Set<String> = []
    private var approachReferenceDistanceByID: [String: Double] = [:]
    private var approachReferenceRSSIByID: [String: Double] = [:]
    private var approachEvidenceCountByID: [String: Int] = [:]
    private var approachLastEvidenceAtByID: [String: Date] = [:]
    private var signalEventReferenceRSSIByID: [String: Int] = [:]
    private var signalEventLastAtByID: [String: Date] = [:]
    private var autoRememberTimer: Timer?
    private var scanRefreshTimer: Timer?
    private var staleCleanupTimer: Timer?
    private var initialBaselineTimer: Timer?
    private var initialBaselineStartedAt: Date?
    private var initialBaselineCompleted: Bool
    private var scanningRequested = true

    override init() {
        let storedTrustedIDs = UserDefaults.standard.stringArray(forKey: trustedDevicesKey)
            ?? UserDefaults.standard.stringArray(forKey: legacyKnownDevicesKey)
            ?? []
        let storedQuietIDs = UserDefaults.standard.stringArray(forKey: quietDevicesKey) ?? []
        let storedKnownIDs = UserDefaults.standard.stringArray(forKey: Self.knownDevicesKey) ?? []
        self.trustedDeviceIDs = Set(storedTrustedIDs)
        self.knownDeviceIDs = Set(storedKnownIDs).union(storedTrustedIDs)
        self.quietDeviceIDs = Set(storedQuietIDs).subtracting(storedTrustedIDs)
        self.alertsEnabled = true
        self.fieldModeEnabled = true
        self.maximumSensitivityEnabled = true
        self.vibrationOnlyEnabled = UserDefaults.standard.object(forKey: Self.vibrationOnlyEnabledKey) as? Bool ?? false
        self.externalSensorEnabled = UserDefaults.standard.object(forKey: Self.externalSensorEnabledKey) as? Bool ?? false
        self.initialBaselineCompleted = UserDefaults.standard.object(forKey: Self.initialBaselineCompletedKey) as? Bool ?? false
        super.init()
        UserDefaults.standard.set(true, forKey: Self.alertsEnabledKey)
        UserDefaults.standard.set(true, forKey: Self.fieldModeEnabledKey)
        UserDefaults.standard.set(true, forKey: Self.maximumSensitivityEnabledKey)
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
        startScanRefreshTimer()
        startStaleCleanupTimer()
        applyMaximumSensitivityPowerMode()
    }

    deinit {
        autoRememberTimer?.invalidate()
        scanRefreshTimer?.invalidate()
        staleCleanupTimer?.invalidate()
        initialBaselineTimer?.invalidate()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    var trustedDeviceCount: Int {
        trustedDeviceIDs.count
    }

    var knownDeviceCount: Int {
        knownDeviceIDs.count
    }

    var approachingDeviceCount: Int {
        devices.filter { $0.approachState == .approaching }.count
    }

    var unknownDeviceCount: Int {
        devices.filter { $0.trustState == .unknown }.count
    }

    var quietDeviceCount: Int {
        devices.filter { $0.trustState == .quiet }.count
    }

    var isInitialBaselineActive: Bool {
        !initialBaselineCompleted
    }

    var strongestDevice: DetectedDevice? {
        devices.max { $0.rssi < $1.rssi }
    }

    var threatLevel: ThreatLevel {
        if devices.contains(where: { device in
            device.approachState == .approaching
                && (device.rssi >= -55 || (device.estimatedDistanceMeters ?? 120) <= 3)
        }) {
            return .criticalApproach
        }

        if approachingDeviceCount > 0 {
            return .confirmedApproach
        }

        if devices.contains(where: { $0.signalTrendText == "усиливается" }) {
            return .strengthening
        }

        return devices.isEmpty ? .normal : .watch
    }

    var alertConfidence: AlertConfidence {
        guard let device = devices.first(where: { $0.approachState == .approaching })
            ?? devices.first(where: { $0.signalTrendText == "усиливается" })
            ?? strongestDevice
        else {
            return .low
        }

        return confidence(for: device)
    }

    var instrumentStatus: InstrumentStatus {
        let checks = selfTestChecks
        let level: InstrumentHealthLevel
        let title: String
        let detail: String

        if checks.contains(where: { $0.level == .critical }) {
            level = .critical
            title = "Требует внимания"
            detail = "Один из базовых каналов не готов"
        } else if checks.contains(where: { $0.level == .warning }) {
            level = .warning
            title = "Ограниченная уверенность"
            detail = "Данные есть, но условия сканирования не идеальны"
        } else {
            level = .nominal
            title = "Готов"
            detail = "Скан активен, данные свежие"
        }

        return InstrumentStatus(title: title, detail: detail, level: level, checks: checks)
    }

    var selfTestChecks: [InstrumentCheck] {
        let now = Date()
        let packetAge = lastPacketAt.map { now.timeIntervalSince($0) }
        let dataIsFresh = packetAge.map { $0 <= Self.packetFreshInterval } ?? false
        let appIsActive = UIApplication.shared.applicationState == .active
        let isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

        return [
            InstrumentCheck(
                id: "bluetooth",
                title: "Bluetooth",
                detail: bluetoothState == .poweredOn ? "включен" : bluetoothState.title,
                level: bluetoothState == .poweredOn ? .nominal : .critical
            ),
            InstrumentCheck(
                id: "scan",
                title: "Скан",
                detail: isScanning ? "активен" : "остановлен",
                level: isScanning ? .nominal : .critical
            ),
            InstrumentCheck(
                id: "packets",
                title: "Данные",
                detail: dataIsFresh ? "свежие · \(packetCount)" : "мало свежих пакетов",
                level: dataIsFresh ? .nominal : (devices.isEmpty ? .warning : .critical)
            ),
            InstrumentCheck(
                id: "baseline",
                title: "Тихий старт",
                detail: initialBaselineCompleted ? "завершен" : "калибровка",
                level: initialBaselineCompleted ? .nominal : .warning
            ),
            InstrumentCheck(
                id: "compass",
                title: "Компас",
                detail: headingDegrees == nil ? "направление не готово" : "курс доступен",
                level: headingDegrees == nil ? .warning : .nominal
            ),
            InstrumentCheck(
                id: "background",
                title: "Фон",
                detail: appIsActive ? "экран активен" : "iOS ограничивает фон",
                level: appIsActive ? .nominal : .warning
            ),
            InstrumentCheck(
                id: "power",
                title: "Питание",
                detail: isLowPowerMode ? "энергосбережение включено" : "обычный режим",
                level: isLowPowerMode ? .warning : .nominal
            ),
            InstrumentCheck(
                id: "ble_stealth",
                title: "BLE-след",
                detail: "приложение только слушает",
                level: .nominal
            ),
            InstrumentCheck(
                id: "wifi_stealth",
                title: "Wi-Fi след",
                detail: "контролируется iOS вручную",
                level: .warning
            ),
            InstrumentCheck(
                id: "system_stealth",
                title: "Системный след",
                detail: "AirDrop/Hotspot вне контроля",
                level: .warning
            ),
            InstrumentCheck(
                id: "external",
                title: "Внешний сенсор",
                detail: externalSensorEnabled ? "ожидание источника" : "не подключен",
                level: externalSensorEnabled ? .warning : .nominal
            )
        ]
    }

    func confidence(for device: DetectedDevice) -> AlertConfidence {
        let sampleCount = device.signalSamples.count
        let jitter = device.recentRSSIJitter
        let directionConfidence = device.directionConfidence

        if device.approachState == .approaching,
           sampleCount >= 12,
           jitter <= 9,
           (directionConfidence == .medium || directionConfidence == .high) {
            return .high
        }

        if sampleCount >= 8, jitter <= 13 {
            return .medium
        }

        return .low
    }

    func startScanning() {
        scanningRequested = true
        guard bluetoothState == .poweredOn else { return }
        beginInitialBaselineIfNeeded()
        centralManager?.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        isScanning = true
        applyMaximumSensitivityPowerMode()
        appendBlackBoxEvent(title: "Скан запущен", detail: "дубликаты BLE включены", level: .nominal)
        appendBlackBoxEvent(title: "BLE-стелс", detail: "режим central scan, реклама приложением не запускается", level: .nominal)
    }

    func stopScanning() {
        scanningRequested = false
        centralManager?.stopScan()
        isScanning = false
        applyMaximumSensitivityPowerMode()
        appendBlackBoxEvent(title: "Скан остановлен", detail: "ручная остановка", level: .warning)
    }

    func toggleScanning() {
        isScanning ? stopScanning() : startScanning()
    }

    func trustAllVisibleDevices() {
        for id in devicesByID.keys {
            knownDeviceIDs.insert(id)
            trustedDeviceIDs.insert(id)
            quietDeviceIDs.remove(id)
        }
        persistDeviceLists()
        refreshTrustStates()
        appendBlackBoxEvent(title: "Доверие обновлено", detail: "текущие устройства добавлены в доверенные", level: .nominal)
    }

    func trustDevice(_ device: DetectedDevice) {
        knownDeviceIDs.insert(device.id)
        trustedDeviceIDs.insert(device.id)
        quietDeviceIDs.remove(device.id)
        persistDeviceLists()
        refreshTrustStates()
        appendBlackBoxEvent(title: "Устройство доверено", detail: "\(device.name) · \(String(device.id.prefix(8)))", level: .nominal)
    }

    func resetTrustedDevices() {
        trustedDeviceIDs.removeAll()
        quietDeviceIDs.removeAll()
        approachAlertedDeviceIDs.removeAll()
        approachReferenceDistanceByID.removeAll()
        approachReferenceRSSIByID.removeAll()
        approachEvidenceCountByID.removeAll()
        approachLastEvidenceAtByID.removeAll()
        signalEventReferenceRSSIByID.removeAll()
        signalEventLastAtByID.removeAll()
        persistDeviceLists()
        refreshTrustStates()
        appendBlackBoxEvent(title: "Доверие сброшено", detail: "текущие базовые точки очищены", level: .warning)
    }

    func clearSession() {
        devicesByID.removeAll()
        deviceOrder.removeAll()
        devices.removeAll()
        approachAlertedDeviceIDs.removeAll()
        approachReferenceDistanceByID.removeAll()
        approachReferenceRSSIByID.removeAll()
        approachEvidenceCountByID.removeAll()
        approachLastEvidenceAtByID.removeAll()
        signalEventReferenceRSSIByID.removeAll()
        signalEventLastAtByID.removeAll()
        signalEvents.removeAll()
        blackBoxEvents.removeAll()
        lastPacketAt = nil
        packetCount = 0
    }

    func testAlert() {
        playConfiguredForegroundAlert()
        appendBlackBoxEvent(title: "Тест сигнала", detail: vibrationOnlyEnabled ? "вибрация" : "звуковой сигнал", level: .nominal)
    }

    func restartFieldBaseline() {
        initialBaselineCompleted = false
        initialBaselineStartedAt = nil
        UserDefaults.standard.set(false, forKey: Self.initialBaselineCompletedKey)
        initialBaselineTimer?.invalidate()
        approachAlertedDeviceIDs.removeAll()
        approachReferenceDistanceByID.removeAll()
        approachReferenceRSSIByID.removeAll()
        approachEvidenceCountByID.removeAll()
        approachLastEvidenceAtByID.removeAll()
        signalEventReferenceRSSIByID.removeAll()
        signalEventLastAtByID.removeAll()
        for device in devicesByID.values {
            seedApproachReferenceIfNeeded(for: device)
        }
        appendBlackBoxEvent(title: "Пост развернут", detail: "тихий старт перезапущен на 60 секунд", level: .warning)
        startScanning()
    }

    func exportBlackBoxText() -> String {
        blackBoxEvents
            .map { entry in
                let timestamp = entry.timestamp.formatted(date: .numeric, time: .standard)
                return "[\(timestamp)] \(entry.title): \(entry.detail)"
            }
            .joined(separator: "\n")
    }

    func handleAppDidBecomeActive() {
        if scanningRequested, bluetoothState == .poweredOn {
            startScanning()
        }
        applyMaximumSensitivityPowerMode()
    }

    func handleAppDidEnterBackground() {
        if scanningRequested, bluetoothState == .poweredOn {
            startScanning()
        }
        applyMaximumSensitivityPowerMode()
    }

    private func persistDeviceLists() {
        UserDefaults.standard.set(Array(trustedDeviceIDs).sorted(), forKey: trustedDevicesKey)
        UserDefaults.standard.set(Array(trustedDeviceIDs).sorted(), forKey: legacyKnownDevicesKey)
        UserDefaults.standard.set(Array(knownDeviceIDs).sorted(), forKey: Self.knownDevicesKey)
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

        if !fieldModeEnabled, quietDeviceIDs.contains(id) {
            return .quiet
        }

        if knownDeviceIDs.contains(id) {
            return .known
        }

        return .unknown
    }

    private func publishDeviceList() {
        devices = deviceOrder.compactMap { devicesByID[$0] }
    }

    private func rememberKnownDevice(_ id: String) {
        guard knownDeviceIDs.insert(id).inserted else { return }
        persistDeviceLists()
    }

    private func beginInitialBaselineIfNeeded(now: Date = Date()) {
        guard !initialBaselineCompleted, initialBaselineStartedAt == nil else { return }

        initialBaselineStartedAt = now
        initialBaselineTimer?.invalidate()
        initialBaselineTimer = Timer.scheduledTimer(withTimeInterval: Self.initialBaselineDuration, repeats: false) { [weak self] _ in
            self?.completeInitialBaseline()
        }
    }

    private func completeInitialBaseline() {
        guard !initialBaselineCompleted else { return }

        initialBaselineCompleted = true
        UserDefaults.standard.set(true, forKey: Self.initialBaselineCompletedKey)
        initialBaselineTimer?.invalidate()
        initialBaselineTimer = nil
        appendBlackBoxEvent(title: "Тихий старт завершен", detail: "тревоги по сближению активны", level: .nominal)
    }

    private func handleApproachAlert(_ device: DetectedDevice, now: Date = Date()) {
        guard alertsEnabled, fieldModeEnabled, initialBaselineCompleted, !approachAlertedDeviceIDs.contains(device.id) else {
            return
        }

        approachAlertedDeviceIDs.insert(device.id)
        lastAlertAt = now

        if UIApplication.shared.applicationState == .active {
            playConfiguredForegroundAlert()
        } else {
            notificationCenter.postDeviceAlert(device, vibrationOnly: vibrationOnlyEnabled)
            if vibrationOnlyEnabled {
                soundPlayer.playApproachVibration()
            }
        }
    }

    private func playConfiguredForegroundAlert() {
        if vibrationOnlyEnabled {
            soundPlayer.playApproachVibration()
        } else {
            soundPlayer.playApproachAlert()
        }
    }

    private func startAutoRememberTimer() {
        autoRememberTimer?.invalidate()
        autoRememberTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.rememberLongVisibleUnknownDevices()
        }
    }

    private func startScanRefreshTimer() {
        scanRefreshTimer?.invalidate()
        scanRefreshTimer = Timer.scheduledTimer(withTimeInterval: scanRefreshInterval, repeats: true) { [weak self] _ in
            self?.refreshFieldScanIfNeeded()
        }
    }

    private func startStaleCleanupTimer() {
        staleCleanupTimer?.invalidate()
        staleCleanupTimer = Timer.scheduledTimer(withTimeInterval: Self.staleCleanupInterval, repeats: true) { [weak self] _ in
            self?.removeStaleDevices()
        }
    }

    private func refreshFieldScanIfNeeded() {
        guard (fieldModeEnabled || maximumSensitivityEnabled), scanningRequested, bluetoothState == .poweredOn else { return }
        centralManager?.stopScan()
        centralManager?.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        isScanning = true
        applyMaximumSensitivityPowerMode()
    }

    private var scanRefreshInterval: TimeInterval {
        maximumSensitivityEnabled ? Self.maximumSensitivityScanRefreshInterval : Self.fieldScanRefreshInterval
    }

    private func applyMaximumSensitivityPowerMode() {
        UIApplication.shared.isIdleTimerDisabled = maximumSensitivityEnabled && scanningRequested && bluetoothState == .poweredOn
    }

    private func seedApproachReferenceIfNeeded(for device: DetectedDevice) {
        if approachReferenceRSSIByID[device.id] == nil {
            approachReferenceRSSIByID[device.id] = device.smoothedRSSI
        }

        if approachReferenceDistanceByID[device.id] == nil,
           let distance = device.estimatedDistanceMeters {
            approachReferenceDistanceByID[device.id] = distance
        }
    }

    private func recordApproachEvidence(for deviceID: String, now: Date) -> Bool {
        if let lastEvidenceAt = approachLastEvidenceAtByID[deviceID],
           now.timeIntervalSince(lastEvidenceAt) < Self.approachEvidenceMinimumSpacing {
            return false
        }

        let evidenceCount = (approachEvidenceCountByID[deviceID] ?? 0) + 1
        approachEvidenceCountByID[deviceID] = evidenceCount
        approachLastEvidenceAtByID[deviceID] = now
        return evidenceCount >= Self.approachRequiredEvidenceCount
    }

    private func decayApproachEvidence(for deviceID: String, now: Date) {
        guard let lastEvidenceAt = approachLastEvidenceAtByID[deviceID],
              now.timeIntervalSince(lastEvidenceAt) >= Self.approachEvidenceResetInterval else {
            return
        }

        approachEvidenceCountByID[deviceID] = 0
        approachLastEvidenceAtByID.removeValue(forKey: deviceID)
    }

    private func appendSignalEvent(deviceName: String, detail: String, kind: SignalEventKind, now: Date = Date()) {
        signalEvents.insert(
            SignalEvent(timestamp: now, deviceName: deviceName, detail: detail, kind: kind),
            at: 0
        )

        if signalEvents.count > Self.signalEventLimit {
            signalEvents.removeLast(signalEvents.count - Self.signalEventLimit)
        }
    }

    private func appendBlackBoxEvent(title: String, detail: String, level: InstrumentHealthLevel, now: Date = Date()) {
        if let latest = blackBoxEvents.first,
           latest.title == title,
           latest.detail == detail,
           now.timeIntervalSince(latest.timestamp) < 10 {
            return
        }

        blackBoxEvents.insert(
            InstrumentLogEntry(timestamp: now, title: title, detail: detail, level: level),
            at: 0
        )

        if blackBoxEvents.count > Self.blackBoxEventLimit {
            blackBoxEvents.removeLast(blackBoxEvents.count - Self.blackBoxEventLimit)
        }
    }

    private func recordSignalEventIfNeeded(for device: DetectedDevice, previousRSSI: Int, now: Date) {
        let referenceRSSI = signalEventReferenceRSSIByID[device.id] ?? previousRSSI
        let delta = device.rssi - referenceRSSI

        guard abs(delta) >= Self.signalEventRSSIThreshold else { return }

        if let lastEventAt = signalEventLastAtByID[device.id],
           now.timeIntervalSince(lastEventAt) < Self.signalEventMinimumSpacing {
            return
        }

        let kind: SignalEventKind = delta > 0 ? .stronger : .weaker
        let sign = delta > 0 ? "+" : ""
        appendSignalEvent(
            deviceName: device.name,
            detail: "\(sign)\(delta) dB · \(device.signalTrendText)",
            kind: kind,
            now: now
        )
        appendBlackBoxEvent(
            title: delta > 0 ? "Сигнал усилился" : "Сигнал ослаб",
            detail: "\(device.name) · \(sign)\(delta) dB · \(device.rssi) dBm",
            level: delta > 0 ? .warning : .nominal,
            now: now
        )
        signalEventReferenceRSSIByID[device.id] = device.rssi
        signalEventLastAtByID[device.id] = now
    }

    private func analyzeApproachSignal(for device: DetectedDevice, referenceRSSI: Double) -> ApproachSignalAnalysis {
        let samples = Array(device.signalSamples.suffix(Self.approachTrendSampleCount))
        guard samples.count >= Self.approachTrendSampleCount,
              let first = samples.first,
              let last = samples.last else {
            return ApproachSignalAnalysis(
                hasEnoughHistory: false,
                rssiGain: device.smoothedRSSI - referenceRSSI,
                trendGain: 0,
                jitter: Double(device.recentRSSIJitter),
                risingSteps: 0,
                span: 0
            )
        }

        let recentMedian = median(samples.suffix(3).map(\.smoothedRSSI))
        let earlierMedian = median(samples.prefix(3).map(\.smoothedRSSI))
        let rawRSSIs = samples.map(\.rssi)
        let jitter = Double((rawRSSIs.max() ?? device.rssi) - (rawRSSIs.min() ?? device.rssi))
        let risingSteps = zip(samples.dropLast(), samples.dropFirst()).filter { previous, next in
            next.smoothedRSSI >= previous.smoothedRSSI - 1.0
        }.count

        return ApproachSignalAnalysis(
            hasEnoughHistory: true,
            rssiGain: recentMedian - referenceRSSI,
            trendGain: recentMedian - earlierMedian,
            jitter: jitter,
            risingSteps: risingSteps,
            span: last.timestamp.timeIntervalSince(first.timestamp)
        )
    }

    private func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }

        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }

        return sorted[middle]
    }

    private func updateApproachState(for device: inout DetectedDevice, now: Date) -> Bool {
        guard fieldModeEnabled,
              initialBaselineCompleted,
              device.trustState == .unknown || device.trustState == .known else {
            return false
        }

        seedApproachReferenceIfNeeded(for: device)

        guard !approachAlertedDeviceIDs.contains(device.id),
              now.timeIntervalSince(device.firstSeen) >= Self.approachMinimumObservationAge else {
            return false
        }

        let referenceRSSI = approachReferenceRSSIByID[device.id] ?? device.smoothedRSSI
        let signalAnalysis = analyzeApproachSignal(for: device, referenceRSSI: referenceRSSI)
        var distanceShowsApproach = false

        if let referenceDistance = approachReferenceDistanceByID[device.id],
           let currentDistance = device.estimatedDistanceMeters {
            distanceShowsApproach = currentDistance <= referenceDistance * Self.approachDistanceDropRatio
                && referenceDistance - currentDistance >= Self.approachMinimumDistanceDrop
                && signalAnalysis.hasStableTrend
                && signalAnalysis.isJitterControlled
        }

        let signalShowsApproach = signalAnalysis.showsApproach
        if (signalShowsApproach || distanceShowsApproach),
           recordApproachEvidence(for: device.id, now: now) {
            device.approachState = .approaching
            return true
        }

        decayApproachEvidence(for: device.id, now: now)

        if device.smoothedRSSI < referenceRSSI - 3 {
            approachReferenceRSSIByID[device.id] = device.smoothedRSSI
            approachEvidenceCountByID[device.id] = 0
            approachLastEvidenceAtByID.removeValue(forKey: device.id)
        }

        if let currentDistance = device.estimatedDistanceMeters,
           let referenceDistance = approachReferenceDistanceByID[device.id],
           currentDistance > referenceDistance * 1.25 {
            approachReferenceDistanceByID[device.id] = currentDistance
        }

        return false
    }

    private func rememberLongVisibleUnknownDevices(now: Date = Date()) {
        guard !fieldModeEnabled else { return }

        var changed = false

        for id in deviceOrder {
            guard var device = devicesByID[id],
                  device.trustState == .unknown,
                  now.timeIntervalSince(device.firstSeen) >= Self.autoRememberInterval
            else {
                continue
            }

            knownDeviceIDs.insert(id)
            device.trustState = .known
            devicesByID[id] = device
            changed = true
        }

        guard changed else { return }

        persistDeviceLists()
        publishDeviceList()
    }

    private func removeStaleDevices(now: Date = Date()) {
        let staleIDs = devicesByID.compactMap { id, device in
            now.timeIntervalSince(device.lastSeen) >= Self.staleDeviceInterval ? id : nil
        }
        guard !staleIDs.isEmpty else { return }

        for id in staleIDs {
            if let device = devicesByID[id] {
                appendBlackBoxEvent(
                    title: "Устройство пропало",
                    detail: "\(device.name) · последнее \(device.rssi) dBm",
                    level: .nominal,
                    now: now
                )
            }
            devicesByID.removeValue(forKey: id)
            approachAlertedDeviceIDs.remove(id)
            approachReferenceDistanceByID.removeValue(forKey: id)
            approachReferenceRSSIByID.removeValue(forKey: id)
            approachEvidenceCountByID.removeValue(forKey: id)
            approachLastEvidenceAtByID.removeValue(forKey: id)
            signalEventReferenceRSSIByID.removeValue(forKey: id)
            signalEventLastAtByID.removeValue(forKey: id)
        }

        let staleIDSet = Set(staleIDs)
        deviceOrder.removeAll { staleIDSet.contains($0) }
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

        if device.directionSectorRSSIs.count != Self.directionSectorCount {
            device.directionSectorRSSIs = Array(repeating: nil, count: Self.directionSectorCount)
        }

        let sector = CompassDirection.sectorIndex(for: headingDegrees)
        if let sectorRSSI = device.directionSectorRSSIs[sector] {
            device.directionSectorRSSIs[sector] = max(sectorRSSI, currentRSSI)
        } else {
            device.directionSectorRSSIs[sector] = currentRSSI
        }
        device.directionObservationCount += 1

        guard let estimate = CompassDirection.estimate(from: device.directionSectorRSSIs, observations: device.directionObservationCount) else {
            device.strongestHeadingRSSI = nil
            device.strongestHeadingDegrees = nil
            return
        }

        if let strongestHeading = device.strongestHeadingDegrees {
            device.strongestHeadingDegrees = CompassDirection.blendDegrees(
                from: strongestHeading,
                to: estimate.headingDegrees,
                weight: 0.18
            )
        } else {
            device.strongestHeadingDegrees = estimate.headingDegrees
        }
        device.strongestHeadingRSSI = estimate.bestRSSI
    }
}

extension BluetoothMonitor: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        authorization = CBCentralManager.authorization
        bluetoothState = central.state
        appendBlackBoxEvent(
            title: "Bluetooth",
            detail: central.state.title,
            level: central.state == .poweredOn ? .nominal : .critical
        )

        if central.state == .poweredOn, scanningRequested {
            startScanning()
        } else {
            isScanning = false
            applyMaximumSensitivityPowerMode()
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
        lastPacketAt = now
        packetCount += 1
        let name = peripheral.name
            ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
            ?? "Без имени"
        let summary = AdvertisementFormatter.summary(from: advertisementData)
        let deviceKind = DeviceKindClassifier.classify(name: name, advertisementData: advertisementData)
        beginInitialBaselineIfNeeded(now: now)
        let wasUnknown = trustState(for: id) == .unknown
        var currentTrustState = trustState(for: id)
        if wasUnknown {
            rememberKnownDevice(id)
            currentTrustState = .known
        }

        if var existing = devicesByID[id] {
            let latestRSSI = RSSI.intValue
            let previousRSSI = existing.rssi
            existing.name = name
            existing.deviceKind = deviceKind
            existing.rssi = latestRSSI
            existing.smoothedRSSI = (existing.smoothedRSSI * 0.72) + (Double(latestRSSI) * 0.28)
            existing.appendSignalSample(
                rssi: latestRSSI,
                smoothedRSSI: existing.smoothedRSSI,
                now: now,
                limit: Self.signalSampleLimit,
                minimumSpacing: Self.signalSampleMinimumSpacing
            )
            updateDirectionEstimate(for: &existing)
            existing.lastSeen = now
            existing.advertisement = summary
            existing.trustState = currentTrustState
            if !fieldModeEnabled,
               existing.trustState == .unknown,
               now.timeIntervalSince(existing.firstSeen) >= Self.autoRememberInterval {
                knownDeviceIDs.insert(id)
                existing.trustState = .known
                persistDeviceLists()
            }
            recordSignalEventIfNeeded(for: existing, previousRSSI: previousRSSI, now: now)
            let isApproaching = updateApproachState(for: &existing, now: now)
            devicesByID[id] = existing
            if isApproaching {
                deviceOrder.removeAll { $0 == id }
                deviceOrder.insert(id, at: 0)
                appendSignalEvent(deviceName: existing.name, detail: "подтверждённое сближение", kind: .approaching, now: now)
                appendBlackBoxEvent(
                    title: "Сближение подтверждено",
                    detail: "\(existing.name) · \(existing.rssi) dBm · доверие \(confidence(for: existing).title)",
                    level: (existing.rssi >= -55 || (existing.estimatedDistanceMeters ?? 120) <= 3) ? .critical : .warning,
                    now: now
                )
                handleApproachAlert(existing, now: now)
            }
        } else {
            let latestRSSI = RSSI.intValue
            let newDevice = DetectedDevice(
                id: id,
                name: name,
                deviceKind: deviceKind,
                rssi: latestRSSI,
                smoothedRSSI: Double(latestRSSI),
                strongestHeadingDegrees: nil,
                strongestHeadingRSSI: nil,
                directionSectorRSSIs: Array(repeating: nil, count: Self.directionSectorCount),
                directionObservationCount: 0,
                firstSeen: now,
                lastSeen: now,
                advertisement: summary,
                trustState: currentTrustState,
                approachState: .watching,
                alertCount: 0,
                signalSamples: [
                    SignalSample(timestamp: now, rssi: latestRSSI, smoothedRSSI: Double(latestRSSI))
                ]
            )
            devicesByID[id] = newDevice
            deviceOrder.removeAll { $0 == id }
            deviceOrder.insert(id, at: 0)
            seedApproachReferenceIfNeeded(for: newDevice)
            signalEventReferenceRSSIByID[id] = latestRSSI
            signalEventLastAtByID[id] = now
            appendSignalEvent(deviceName: newDevice.name, detail: "появилось · \(latestRSSI) dBm", kind: .neutral, now: now)
            appendBlackBoxEvent(
                title: "Новое устройство",
                detail: "\(newDevice.name) · \(latestRSSI) dBm · \(String(id.prefix(8)))",
                level: .nominal,
                now: now
            )
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
        content.title = "Устройство приближается"
        content.body = "\(device.name): сигнал усилился, \(device.estimatedDistanceText), \(device.directionName)"
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

struct CompassDirectionEstimate {
    let headingDegrees: Double
    let bestRSSI: Double
    let confidence: DirectionConfidence
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

    private static let minimumObservations = 6
    private static let minimumScannedSectors = 3
    private static let minimumSignalGap = 4.0
    private static let mediumSignalGap = 6.5
    private static let highSignalGap = 9.0

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

    static func sectorIndex(for degrees: Double) -> Int {
        index(for: degrees)
    }

    static func estimate(from sectorRSSIs: [Double?], observations: Int) -> CompassDirectionEstimate? {
        let indexedRSSIs = sectorRSSIs.enumerated().compactMap { index, rssi -> (index: Int, rssi: Double)? in
            guard let rssi else { return nil }
            return (index, rssi)
        }
        guard observations >= minimumObservations,
              indexedRSSIs.count >= minimumScannedSectors,
              let best = indexedRSSIs.max(by: { $0.rssi < $1.rssi }) else {
            return nil
        }

        let secondBestRSSI = indexedRSSIs
            .filter { $0.index != best.index }
            .map(\.rssi)
            .max() ?? -120
        let gap = best.rssi - secondBestRSSI
        guard gap >= minimumSignalGap else { return nil }

        let confidence: DirectionConfidence
        if observations >= 14, indexedRSSIs.count >= 4, gap >= highSignalGap {
            confidence = .high
        } else if observations >= 10, gap >= mediumSignalGap {
            confidence = .medium
        } else {
            confidence = .low
        }

        return CompassDirectionEstimate(
            headingDegrees: Double(best.index) * 45,
            bestRSSI: best.rssi,
            confidence: confidence
        )
    }

    static func confidence(from sectorRSSIs: [Double?], observations: Int) -> DirectionConfidence {
        estimate(from: sectorRSSIs, observations: observations)?.confidence ?? .scanning
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
