import CoreBluetooth
import SwiftUI

struct ContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var monitor: BluetoothMonitor
    @State private var isAnalysisVisible = false

    private var theme: SentinelTheme {
        SentinelTheme(colorScheme: colorScheme)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    statusPanel
                    controlPanel
                    if isAnalysisVisible {
                        analysisPanel
                    }
                    devicesPanel
                }
                .padding(16)
            }
            .background(theme.background.ignoresSafeArea())
            .navigationTitle("BT Sentinel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(theme.background, for: .navigationBar)
        }
    }

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(statusColor.opacity(0.16))
                    Image(systemName: monitor.isScanning ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(statusColor)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 3) {
                    Text(monitor.bluetoothState.title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(theme.primaryText)
                    Text(monitor.isScanning ? "Сканирование активно" : "Сканирование остановлено")
                        .font(.caption)
                        .foregroundStyle(theme.secondaryText)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(monitor.devices.count)")
                        .font(.title3.monospacedDigit().weight(.bold))
                        .foregroundStyle(theme.primaryText)
                    Text("в эфире")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(theme.secondaryText)
                }
            }

            HStack(spacing: 8) {
                CompactMetric(title: "Сближение", value: "\(monitor.approachingDeviceCount)", color: .red, theme: theme)
                Button {
                    withAnimation(.snappy(duration: 0.22)) {
                        isAnalysisVisible.toggle()
                    }
                } label: {
                    CompactMetric(title: "Известные", value: "\(monitor.knownDeviceCount)", color: .blue, theme: theme)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isAnalysisVisible ? "Скрыть анализ" : "Показать анализ")
                CompactMetric(title: "Тихий старт", value: monitor.isInitialBaselineActive ? "ON" : "OK", color: .green, theme: theme)
            }
        }
        .padding(14)
        .background(theme.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(theme.cardStroke)
        }
    }

    private var controlPanel: some View {
        VStack(spacing: 12) {
            Toggle(isOn: $monitor.vibrationOnlyEnabled) {
                Label("Беззвучный режим", systemImage: monitor.vibrationOnlyEnabled ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.primaryText)
            }
            .tint(.orange)

            HStack(spacing: 10) {
                Button {
                    monitor.trustAllVisibleDevices()
                } label: {
                    Label("Доверять", systemImage: "checkmark.shield.fill")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .fixedSize()
                .disabled(monitor.devices.isEmpty)

                Button(role: .destructive) {
                    monitor.resetTrustedDevices()
                } label: {
                    Label("Сброс доверия", systemImage: "xmark.shield.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
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
                Text("Устройства")
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
                        CompactDeviceRow(device: device, theme: theme)
                            .transaction { transaction in
                                transaction.animation = nil
                            }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var analysisPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Анализ")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(theme.primaryText)
                Spacer()
                Text("\(monitor.signalEvents.count)")
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(theme.secondaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(theme.softFill, in: Capsule())
            }

            if monitor.signalEvents.isEmpty {
                Text("История появится после новых устройств или заметного изменения сигнала.")
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(2)
            } else {
                VStack(spacing: 7) {
                    ForEach(monitor.signalEvents.prefix(5)) { event in
                        SignalEventRow(event: event, theme: theme)
                    }
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

    private var statusColor: Color {
        monitor.isScanning ? .green : .secondary
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
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(theme.secondaryText)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 4) {
                Text("\(device.rssi) dBm")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(signalColor)

                HStack(spacing: 4) {
                    DirectionMiniBadge(device: device, theme: theme)
                    Text(device.estimatedDistanceText)
                        .font(.caption2.monospacedDigit().weight(.bold))
                        .foregroundStyle(distanceColor)
                }
            }

            VStack(alignment: .trailing, spacing: 4) {
                SignalPowerScale(rssi: device.rssi, color: signalColor, theme: theme)
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
                .stroke(device.approachState == .approaching ? Color.red.opacity(0.45) : theme.cardStroke)
        }
    }

    private var shortIdentifier: String {
        String(device.id.prefix(8))
    }

    private var signalColor: Color {
        if device.rssi > -55 { return .green }
        if device.rssi > -75 { return .orange }
        return theme.secondaryText
    }

    private var distanceColor: Color {
        guard let meters = device.estimatedDistanceMeters else { return theme.secondaryText }
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
}

#Preview {
    ContentView()
        .environmentObject(BluetoothMonitor())
}
