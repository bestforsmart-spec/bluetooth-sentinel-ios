import CoreBluetooth
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var monitor: BluetoothMonitor

    var body: some View {
        NavigationStack {
            List {
                Section {
                    statusPanel
                }

                Section {
                    controlPanel
                }

                Section("Список устройств") {
                    if monitor.devices.isEmpty {
                        ContentUnavailableView(
                            "Пока пусто",
                            systemImage: "dot.radiowaves.left.and.right",
                            description: Text("Включите Bluetooth и оставьте приложение активным.")
                        )
                    } else {
                        ForEach(monitor.devices) { device in
                            DeviceRow(device: device) {
                                monitor.trustDevice(device)
                            }
                        }
                        .transaction { transaction in
                            transaction.animation = nil
                        }
                    }
                }
            }
            .navigationTitle("BT Sentinel")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        monitor.testAlert()
                    } label: {
                        Image(systemName: "speaker.wave.3.fill")
                    }
                    .accessibilityLabel("Тест сигнала")

                    Button {
                        monitor.clearSession()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel("Очистить список")
                }
            }
        }
    }

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: monitor.isScanning ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                    .font(.title2)
                    .foregroundStyle(monitor.isScanning ? .green : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(monitor.bluetoothState.title)
                        .font(.headline)
                    Text(monitor.isScanning ? "Сканирование активно" : "Сканирование остановлено")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            HStack(spacing: 10) {
                StatPill(title: "Новые", value: "\(monitor.unknownDeviceCount)", color: .red)
                StatPill(title: "Доверенные", value: "\(monitor.trustedDeviceCount)", color: .blue)
                StatPill(title: "В эфире", value: "\(monitor.devices.count)", color: .green)
            }
        }
        .padding(.vertical, 4)
    }

    private var controlPanel: some View {
        VStack(spacing: 12) {
            Button {
                monitor.toggleScanning()
            } label: {
                Label(monitor.isScanning ? "Остановить" : "Сканировать", systemImage: monitor.isScanning ? "pause.fill" : "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(monitor.bluetoothState != .poweredOn)

            Toggle(isOn: $monitor.alertsEnabled) {
                Label("Звуковой сигнал", systemImage: "bell.and.waves.left.and.right.fill")
            }

            Toggle(isOn: $monitor.vibrationOnlyEnabled) {
                Label("Беззвучно: вибро", systemImage: "iphone.radiowaves.left.and.right")
            }
            .disabled(!monitor.alertsEnabled)

            HStack {
                Button {
                    monitor.trustAllVisibleDevices()
                } label: {
                    Label("Доверять текущим", systemImage: "checkmark.shield.fill")
                }
                .disabled(monitor.devices.isEmpty)

                Spacer()

                Button(role: .destructive) {
                    monitor.resetTrustedDevices()
                } label: {
                    Label("Сброс доверия", systemImage: "xmark.shield.fill")
                }
            }
            .font(.subheadline)
        }
    }
}

struct DeviceRow: View {
    let device: DetectedDevice
    let trustDevice: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .font(.headline)
                    Text(device.id)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(device.rssi) dBm")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(signalColor)
                    Text(device.estimatedDistanceText)
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(distanceColor)
                    DirectionBadge(device: device)
                    Label(trustStatusText, systemImage: trustStatusImage)
                        .font(.caption2.bold())
                        .foregroundStyle(trustStatusColor)
                }
            }

            Text(device.advertisement)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Label {
                    Text(device.lastSeen, format: .relative(presentation: .named))
                } icon: {
                    Image(systemName: "clock")
                }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if !device.isTrusted {
                    Button("Доверять") {
                        trustDevice()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private var signalColor: Color {
        if device.rssi > -55 { return .green }
        if device.rssi > -75 { return .orange }
        return .secondary
    }

    private var distanceColor: Color {
        guard let meters = device.estimatedDistanceMeters else { return .secondary }
        if meters < 3 { return .green }
        if meters < 10 { return .orange }
        return .secondary
    }

    private var trustStatusText: String {
        switch device.trustState {
        case .unknown:
            return "NEW"
        case .quiet:
            return "QUIET"
        case .trusted:
            return "TRUST"
        }
    }

    private var trustStatusImage: String {
        switch device.trustState {
        case .unknown:
            return "exclamationmark.triangle.fill"
        case .quiet:
            return "speaker.slash.fill"
        case .trusted:
            return "checkmark.shield.fill"
        }
    }

    private var trustStatusColor: Color {
        switch device.trustState {
        case .unknown:
            return .red
        case .quiet:
            return .orange
        case .trusted:
            return .green
        }
    }
}

struct DirectionBadge: View {
    let device: DetectedDevice

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: device.directionArrowDegrees == nil ? "location.north.line" : "location.north.fill")
                .font(.caption2)
                .rotationEffect(.degrees(device.directionArrowDegrees ?? 0))
                .animation(.easeOut(duration: 0.18), value: device.directionArrowDegrees ?? 0)

            Text(device.directionShortName)
                .font(.caption2.bold())
                .monospacedDigit()
        }
        .foregroundStyle(directionColor)
        .accessibilityLabel("Направление \(device.directionName)")
    }

    private var directionColor: Color {
        device.directionArrowDegrees == nil ? .secondary : .blue
    }
}

struct StatPill: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline.monospacedDigit())
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}

#Preview {
    ContentView()
        .environmentObject(BluetoothMonitor())
}
