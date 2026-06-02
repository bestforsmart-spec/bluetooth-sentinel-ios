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
                                monitor.markAsKnown(device)
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
                StatPill(title: "Известные", value: "\(monitor.knownDeviceCount)", color: .blue)
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

            HStack {
                Button {
                    monitor.markAllVisibleAsKnown()
                } label: {
                    Label("Запомнить текущие", systemImage: "checkmark.shield.fill")
                }
                .disabled(monitor.devices.isEmpty)

                Spacer()

                Button(role: .destructive) {
                    monitor.forgetKnownDevices()
                } label: {
                    Label("Сброс базы", systemImage: "xmark.shield.fill")
                }
            }
            .font(.subheadline)
        }
    }
}

struct DeviceRow: View {
    let device: DetectedDevice
    let markAsKnown: () -> Void

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
                    Label(device.isKnown ? "OK" : "NEW", systemImage: device.isKnown ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.caption2.bold())
                        .foregroundStyle(device.isKnown ? .green : .red)
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

                if !device.isKnown {
                    Button("Запомнить") {
                        markAsKnown()
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
