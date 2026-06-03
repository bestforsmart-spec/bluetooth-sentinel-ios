import CoreBluetooth
import SwiftUI
import UIKit

struct ContentView: View {
    @EnvironmentObject private var monitor: BluetoothMonitor
    @AppStorage("darkThemeEnabled") private var darkThemeEnabled = false
    @State private var isAnalysisSheetPresented = false
    @State private var isInstrumentSheetPresented = false
    @State private var selectedDevice: DetectedDevice?

    private var theme: SentinelTheme {
        SentinelTheme(colorScheme: activeColorScheme)
    }

    private var activeColorScheme: ColorScheme {
        darkThemeEnabled ? .dark : .light
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    statusPanel
                    devicesPanel
                }
                .padding(16)
            }
            .background(theme.background.ignoresSafeArea())
            .preferredColorScheme(activeColorScheme)
            .navigationTitle("BT Sentinel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(theme.background, for: .navigationBar)
            .sheet(isPresented: $isAnalysisSheetPresented) {
                AnalysisSheetView(events: monitor.signalEvents, theme: theme)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $isInstrumentSheetPresented) {
                InstrumentSheetView(monitor: monitor, theme: theme)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(item: $selectedDevice) { device in
                DeviceDetailSheet(device: latestDevice(for: device), theme: theme, monitor: monitor)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(statusColor.opacity(0.16))
                            Image(systemName: monitor.isScanning ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(statusColor)
                        }
                        .frame(width: 34, height: 34)

                        Text(operationStateText)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(theme.primaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }

                    Text(monitor.bluetoothState.title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(theme.secondaryText)
                }

                Spacer()

                HStack(alignment: .top, spacing: 10) {
                    Button {
                        monitor.vibrationOnlyEnabled.toggle()
                    } label: {
                        Image(systemName: monitor.vibrationOnlyEnabled ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(monitor.vibrationOnlyEnabled ? .orange : theme.primaryText)
                            .frame(width: 34, height: 34)
                            .background(theme.softFill, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(monitor.vibrationOnlyEnabled ? "Выключить беззвучный режим" : "Включить беззвучный режим")

                    Button {
                        darkThemeEnabled.toggle()
                    } label: {
                        Image(systemName: darkThemeEnabled ? "moon.fill" : "sun.max.fill")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(darkThemeEnabled ? .blue : .orange)
                            .frame(width: 34, height: 34)
                            .background(theme.softFill, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(darkThemeEnabled ? "Включить светлую тему" : "Включить тёмную тему")

                    VStack(alignment: .trailing, spacing: 0) {
                        Text("\(monitor.devices.count)")
                            .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(theme.primaryText)
                        Text("в эфире")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(theme.secondaryText)
                    }
                }
            }

            RadarActivityBar(level: airActivityLevel, accent: statusColor, theme: theme)

            HStack(spacing: 8) {
                CompactMetric(title: "Новые", value: "\(monitor.newDeviceCount)", color: .green, theme: theme)
                Button {
                    isAnalysisSheetPresented = true
                } label: {
                    CompactMetric(title: "Известные", value: "\(monitor.knownDeviceCount)", color: .blue, theme: theme)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Показать анализ")
            }
        }
        .padding(14)
        .background(theme.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(theme.cardStroke)
        }
    }

    private var devicesPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Сигнальная таблица")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(theme.primaryText)
                Spacer()
                Text("\(monitor.devices.count)")
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(theme.secondaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(theme.softFill, in: Capsule())
            }

            if monitor.devices.isEmpty {
                EmptyDevicesView(theme: theme)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(monitor.devices) { device in
                        Button {
                            selectedDevice = device
                        } label: {
                            CompactDeviceRow(device: device, theme: theme)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Открыть устройство \(device.name)")
                            .transaction { transaction in
                                transaction.animation = nil
                            }
                    }
                }
            }
        }
    }

    private var statusColor: Color {
        monitor.isScanning ? .green : theme.secondaryText
    }

    private var operationStateText: String {
        if monitor.isInitialBaselineActive { return "Тихий старт" }
        if monitor.isScanning { return "Сканирование активно" }
        return "Скан остановлен"
    }

    private var airActivityLevel: CGFloat {
        guard let strongestRSSI = monitor.devices.map(\.displayRSSI).max() else { return 0 }
        let clamped = min(max(Double(strongestRSSI), -100), -35)
        return CGFloat((clamped + 100) / 65)
    }

    private func latestDevice(for device: DetectedDevice) -> DetectedDevice {
        monitor.devices.first { $0.id == device.id } ?? device
    }
}

struct CompactDeviceRow: View {
    let device: DetectedDevice
    let theme: SentinelTheme

    var body: some View {
        HStack(spacing: 8) {
            SignalDot(color: signalColor)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(device.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if device.approachState == .approaching {
                        Image(systemName: "arrow.down.left.and.arrow.up.right")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.red)
                    }
                }

                HStack(spacing: 6) {
                    Image(systemName: device.deviceKind.symbolName)
                        .font(.caption2)
                    Text(device.deviceKind.title)
                        .lineLimit(1)
                    Text(shortIdentifier)
                        .font(.caption2.monospaced())
                        .lineLimit(1)
                    TrustBadge(state: device.trustState, theme: theme)
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(theme.secondaryText)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 4) {
                Text("\(device.displayRSSI) dBm")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(signalColor)

                HStack(spacing: 4) {
                    DirectionMiniBadge(device: device, theme: theme)
                    Text(device.displayDistanceText)
                        .font(.caption2.monospacedDigit().weight(.bold))
                        .foregroundStyle(distanceColor)
                }
            }

            VStack(alignment: .trailing, spacing: 4) {
                SignalPowerScale(rssi: device.displayRSSI, color: signalColor, theme: theme)
                Text(device.signalTrendText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(trendColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(width: 56, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(theme.cardBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(alignment: .top) {
            if isFresh || device.approachState == .approaching {
                Rectangle()
                    .fill(rowAccent.opacity(device.approachState == .approaching ? 0.85 : 0.55))
                    .frame(height: 2)
                    .clipShape(Capsule())
                    .padding(.horizontal, 12)
            }
        }
        .overlay(alignment: .leading) {
            if device.trustState == .trusted {
                Rectangle()
                    .fill(.green)
                    .frame(width: 3)
                    .clipShape(Capsule())
                    .padding(.vertical, 10)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(device.approachState == .approaching ? Color.red.opacity(0.55) : theme.cardStroke)
        }
    }

    private var shortIdentifier: String {
        String(device.id.prefix(8))
    }

    private var signalColor: Color {
        if device.displayRSSI > -55 { return .green }
        if device.displayRSSI > -75 { return .orange }
        return theme.secondaryText
    }

    private var distanceColor: Color {
        guard let meters = device.displayDistanceMeters else { return theme.secondaryText }
        if meters < 3 { return .green }
        if meters < 10 { return .orange }
        return theme.secondaryText
    }

    private var trendColor: Color {
        switch device.signalTrendText {
        case "сближение":
            return .red
        case "усиливается":
            return .orange
        case "слабеет":
            return .blue
        case "дрожит":
            return .yellow
        default:
            return theme.secondaryText
        }
    }

    private var isFresh: Bool {
        Date().timeIntervalSince(device.firstSeen) < 8
    }

    private var rowAccent: Color {
        if device.approachState == .approaching { return .red }
        if isFresh { return .blue }
        return theme.secondaryText
    }
}

struct RadarActivityBar: View {
    let level: CGFloat
    let accent: Color
    let theme: SentinelTheme

    var body: some View {
        HStack(spacing: 8) {
            Text("Активность")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(theme.secondaryText)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(theme.softFill)
                    Capsule()
                        .fill(accent.opacity(0.82))
                        .frame(width: proxy.size.width * min(max(level, 0), 1))
                }
            }
            .frame(height: 8)

            Text(activityText)
                .font(.caption2.monospacedDigit().weight(.bold))
                .foregroundStyle(theme.secondaryText)
        }
    }

    private var activityText: String {
        if level > 0.72 { return "HI" }
        if level > 0.42 { return "MID" }
        if level > 0 { return "LOW" }
        return "--"
    }
}

struct TrustBadge: View {
    let state: DeviceTrustState
    let theme: SentinelTheme

    var body: some View {
        switch state {
        case .trusted:
            Image(systemName: "checkmark.shield.fill")
                .foregroundStyle(.green)
        case .known:
            Image(systemName: "shield.fill")
                .foregroundStyle(.blue.opacity(0.8))
        case .quiet:
            Image(systemName: "speaker.slash.fill")
                .foregroundStyle(theme.secondaryText)
        case .unknown:
            Image(systemName: "questionmark.circle.fill")
                .foregroundStyle(theme.secondaryText)
        }
    }
}

struct SignalEventRow: View {
    let event: SignalEvent
    let theme: SentinelTheme

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 1) {
                Text(event.deviceName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(event.detail)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)
            }

            Spacer()

            Text(event.timestamp, format: .dateTime.hour().minute().second())
                .font(.caption2.monospacedDigit())
                .foregroundStyle(theme.secondaryText)
        }
    }

    private var color: Color {
        switch event.kind {
        case .neutral:
            return .blue
        case .stronger:
            return .orange
        case .weaker:
            return .teal
        case .approaching:
            return .red
        }
    }
}

struct AnalysisSheetView: View {
    let events: [SignalEvent]
    let theme: SentinelTheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SheetHeader(title: "Анализ сигнала", count: events.count, theme: theme)

                if events.isEmpty {
                    Text("Событий пока нет")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                        .background(theme.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(theme.cardStroke)
                        }
                } else {
                    LazyVStack(spacing: 9) {
                        ForEach(events) { event in
                            SignalEventRow(event: event, theme: theme)
                                .padding(12)
                                .background(theme.cardBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(theme.cardStroke)
                                }
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(theme.background.ignoresSafeArea())
    }
}

struct InstrumentSheetView: View {
    @ObservedObject var monitor: BluetoothMonitor
    let theme: SentinelTheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SheetHeader(title: "Прибор", count: monitor.packetCount, theme: theme)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "gauge.with.dots.needle.67percent")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(theme.healthColor(monitor.instrumentStatus.level))
                            .frame(width: 34, height: 34)
                            .background(theme.softFill, in: Circle())

                        VStack(alignment: .leading, spacing: 3) {
                            Text(monitor.instrumentStatus.title)
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(theme.primaryText)
                            Text(monitor.instrumentStatus.detail)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(theme.secondaryText)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 3) {
                            Text(monitor.threatLevel.title)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(theme.threatColor(monitor.threatLevel))
                            Text("уверенность \(monitor.alertConfidence.title)")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(theme.secondaryText)
                        }
                    }

                }
                .padding(14)
                .background(theme.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(theme.cardStroke)
                }

                VStack(alignment: .leading, spacing: 9) {
                    Text("Самотест")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.primaryText)

                    ForEach(monitor.selfTestChecks) { check in
                        InstrumentCheckRow(check: check, theme: theme)
                    }
                }
                .padding(14)
                .background(theme.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(theme.cardStroke)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label("Стелс-профиль", systemImage: "eye.slash.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.primaryText)
                    Text("BT Sentinel не запускает BLE-рекламу и не держит Wi-Fi соединение. Полная радионевидимость телефона зависит от системных служб iOS и ручного отключения Wi-Fi, AirDrop и Hotspot.")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .background(theme.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(theme.cardStroke)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Toggle(isOn: $monitor.externalSensorEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Внешний сенсор")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(theme.primaryText)
                            Text("подготовлен режим подключения, источник не выбран")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(theme.secondaryText)
                        }
                    }
                    .tint(.green)
                }
                .padding(14)
                .background(theme.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(theme.cardStroke)
                }

                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text("Чёрный ящик")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(theme.primaryText)
                        Spacer()
                        Button {
                            UIPasteboard.general.string = monitor.exportBlackBoxText()
                        } label: {
                            Image(systemName: "doc.on.doc.fill")
                                .font(.caption.weight(.bold))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .accessibilityLabel("Скопировать журнал")
                    }

                    if monitor.blackBoxEvents.isEmpty {
                        Text("Журнал пока пуст")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(theme.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 16)
                    } else {
                        ForEach(monitor.blackBoxEvents.prefix(16)) { entry in
                            BlackBoxEventRow(entry: entry, theme: theme)
                        }
                    }
                }
                .padding(14)
                .background(theme.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(theme.cardStroke)
                }
            }
            .padding(16)
        }
        .background(theme.background.ignoresSafeArea())
    }
}

struct InstrumentCheckRow: View {
    let check: InstrumentCheck
    let theme: SentinelTheme

    var body: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(theme.healthColor(check.level))
                .frame(width: 8, height: 8)
            Text(check.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.primaryText)
                .frame(width: 88, alignment: .leading)
            Text(check.detail)
                .font(.caption2.weight(.medium))
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
            Spacer(minLength: 0)
        }
    }
}

struct BlackBoxEventRow: View {
    let entry: InstrumentLogEntry
    let theme: SentinelTheme

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Circle()
                .fill(theme.healthColor(entry.level))
                .frame(width: 8, height: 8)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)
                Text(entry.detail)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 6)

            Text(entry.timestamp, format: .dateTime.hour().minute().second())
                .font(.caption2.monospacedDigit())
                .foregroundStyle(theme.secondaryText)
        }
    }
}

struct DeviceDetailSheet: View {
    let device: DetectedDevice
    let theme: SentinelTheme
    let monitor: BluetoothMonitor
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    SignalDot(color: signalColor)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(device.name)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(theme.primaryText)
                            .lineLimit(2)
                        Text(device.id)
                            .font(.caption2.monospaced())
                            .foregroundStyle(theme.secondaryText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(theme.secondaryText)
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 8) {
                    DetailMetric(title: "RSSI 3с", value: "\(device.displayRSSI)", unit: "dBm", color: signalColor, theme: theme)
                    DetailMetric(title: "Дистанция", value: device.displayDistanceText, unit: "", color: distanceColor, theme: theme)
                    DetailMetric(title: "Курс", value: device.directionShortName, unit: device.directionConfidenceText, color: directionColor, theme: theme)
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Мощность")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(theme.primaryText)
                        Spacer()
                        Text(device.signalTrendText)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(trendColor)
                    }
                    SignalHistoryStrip(samples: Array(device.signalSamples.suffix(24)), color: signalColor, theme: theme)
                }
                .padding(14)
                .background(theme.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(theme.cardStroke)
                }

                HStack(spacing: 10) {
                    Button {
                        monitor.trustDevice(device)
                        dismiss()
                    } label: {
                        Label("Доверять", systemImage: "checkmark.shield.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button {
                        UIPasteboard.general.string = device.id
                    } label: {
                        Label("ID", systemImage: "doc.on.doc.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(16)
        }
        .background(theme.background.ignoresSafeArea())
    }

    private var signalColor: Color {
        if device.displayRSSI > -55 { return .green }
        if device.displayRSSI > -75 { return .orange }
        return theme.secondaryText
    }

    private var distanceColor: Color {
        guard let meters = device.displayDistanceMeters else { return theme.secondaryText }
        if meters < 3 { return .green }
        if meters < 10 { return .orange }
        return theme.secondaryText
    }

    private var trendColor: Color {
        switch device.signalTrendText {
        case "сближение":
            return .red
        case "усиливается":
            return .orange
        case "слабеет":
            return .blue
        case "дрожит":
            return .yellow
        default:
            return theme.secondaryText
        }
    }

    private var directionColor: Color {
        switch device.directionConfidence {
        case .scanning:
            return theme.secondaryText
        case .low, .medium:
            return .blue
        case .high:
            return .green
        }
    }
}

struct SheetHeader: View {
    let title: String
    let count: Int
    let theme: SentinelTheme

    var body: some View {
        HStack {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(theme.primaryText)
            Spacer()
            Text("\(count)")
                .font(.caption.monospacedDigit().weight(.bold))
                .foregroundStyle(theme.secondaryText)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(theme.softFill, in: Capsule())
        }
    }
}

struct DetailMetric: View {
    let title: String
    let value: String
    let unit: String
    let color: Color
    let theme: SentinelTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(theme.secondaryText)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.subheadline.monospacedDigit().weight(.bold))
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(theme.softFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

struct SignalHistoryStrip: View {
    let samples: [SignalSample]
    let color: Color
    let theme: SentinelTheme

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(samples.enumerated()), id: \.offset) { _, sample in
                Capsule()
                    .fill(color.opacity(0.80))
                    .frame(maxWidth: .infinity)
                    .frame(height: barHeight(for: sample.rssi))
            }
        }
        .frame(height: 54)
        .padding(10)
        .background(theme.softFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func barHeight(for rssi: Int) -> CGFloat {
        let clamped = min(max(Double(rssi), -100), -35)
        let normalized = (clamped + 100) / 65
        return CGFloat(8 + (normalized * 42))
    }
}

struct SignalPowerScale: View {
    let rssi: Int
    let color: Color
    let theme: SentinelTheme

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(theme.softFill)

            Capsule()
                .fill(color.opacity(0.82))
                .frame(width: 46 * signalLevel)
        }
        .frame(width: 46, height: 8)
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        .background(theme.softFill.opacity(0.75), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private var signalLevel: CGFloat {
        let clamped = min(max(Double(rssi), -100), -35)
        return CGFloat((clamped + 100) / 65)
    }
}

struct EmptyDevicesView: View {
    let theme: SentinelTheme

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.title2)
                .foregroundStyle(theme.secondaryText)
            Text("Пока пусто")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.primaryText)
            Text("Оставьте приложение открытым для максимального BLE-сканирования.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(theme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 16)
        .background(theme.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(theme.cardStroke)
        }
    }
}

struct CompactMetric: View {
    let title: String
    let value: String
    let color: Color
    let theme: SentinelTheme

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline.monospacedDigit().weight(.bold))
                .foregroundStyle(theme.primaryText)
            Text(title)
                .font(.caption2.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .foregroundStyle(theme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(theme.metricOpacity), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct SignalDot: View {
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.16))
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)
        }
        .frame(width: 28, height: 28)
    }
}

struct DirectionMiniBadge: View {
    let device: DetectedDevice
    let theme: SentinelTheme

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: device.directionArrowDegrees == nil ? "location.north.line" : "location.north.fill")
                .font(.caption2)
                .rotationEffect(.degrees(device.directionArrowDegrees ?? 0))
            Text(device.directionShortName)
                .font(.caption2.weight(.bold))
            if device.directionConfidence != .scanning {
                Text(device.directionConfidenceText)
                    .font(.caption2.weight(.medium))
            }
        }
        .foregroundStyle(directionColor)
        .accessibilityLabel("Направление \(device.directionName), уверенность \(accessibilityConfidence)")
    }

    private var directionColor: Color {
        switch device.directionConfidence {
        case .scanning:
            return theme.secondaryText
        case .low:
            return .blue.opacity(0.72)
        case .medium:
            return .blue
        case .high:
            return .green
        }
    }

    private var accessibilityConfidence: String {
        switch device.directionConfidence {
        case .scanning:
            return "сканирование"
        case .low:
            return "низкая"
        case .medium:
            return "средняя"
        case .high:
            return "высокая"
        }
    }
}

struct SentinelTheme {
    let colorScheme: ColorScheme

    var background: Color {
        colorScheme == .dark ? Color(red: 0.05, green: 0.06, blue: 0.08) : Color(red: 0.95, green: 0.96, blue: 0.98)
    }

    var cardBackground: Color {
        colorScheme == .dark ? Color(red: 0.10, green: 0.11, blue: 0.14) : .white
    }

    var softFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05)
    }

    var cardStroke: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.07)
    }

    var primaryText: Color {
        colorScheme == .dark ? .white : Color(red: 0.08, green: 0.10, blue: 0.13)
    }

    var secondaryText: Color {
        colorScheme == .dark ? Color.white.opacity(0.62) : Color.black.opacity(0.58)
    }

    var metricOpacity: Double {
        colorScheme == .dark ? 0.20 : 0.12
    }

    func healthColor(_ level: InstrumentHealthLevel) -> Color {
        switch level {
        case .nominal:
            return .green
        case .warning:
            return .orange
        case .critical:
            return .red
        }
    }

    func threatColor(_ level: ThreatLevel) -> Color {
        switch level {
        case .normal:
            return .green
        case .watch:
            return .blue
        case .strengthening:
            return .orange
        case .confirmedApproach, .criticalApproach:
            return .red
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(BluetoothMonitor())
}
