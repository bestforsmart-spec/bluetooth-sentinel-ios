import SwiftUI

struct ContentView: View {
    @ObservedObject var monitor: BluetoothMonitor
    @State private var searchText = ""

    private var filteredDevices: [DetectedDevice] {
        guard !searchText.isEmpty else { return monitor.devices }
        return monitor.devices.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.id.localizedCaseInsensitiveContains(searchText)
                || $0.kind.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 14) {
                HeaderView(monitor: monitor)
                DeviceListView(devices: filteredDevices, selectedID: $monitor.selectedID)
            }
            .padding(18)
            .navigationSplitViewColumnWidth(min: 420, ideal: 500)
            .searchable(text: $searchText, placement: .sidebar)
        } detail: {
            if let device = monitor.selectedDevice {
                DeviceDetailView(device: device, monitor: monitor)
                    .padding(22)
            } else {
                VStack(spacing: 10) {
                    Text("скан")
                        .font(.system(size: 34, weight: .bold))
                    Text("Устройства появятся после BLE advertising-пакетов")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    monitor.soundEnabled.toggle()
                } label: {
                    Label(monitor.soundEnabled ? "Звук" : "Тихо", systemImage: monitor.soundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                }

                Button {
                    monitor.trustCurrentDevices()
                } label: {
                    Label("Доверять текущим", systemImage: "checkmark.shield.fill")
                }
            }
        }
    }
}

struct HeaderView: View {
    @ObservedObject var monitor: BluetoothMonitor

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(.green.opacity(0.16))
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.green)
                }
                .frame(width: 58, height: 58)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Bluetooth включен")
                        .font(.system(size: 22, weight: .bold))
                    Text(monitor.stateText)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(monitor.devices.count)")
                        .font(.system(size: 34, weight: .bold))
                    Text("в эфире")
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                MetricChip(title: "Новые", value: "\(monitor.newCount)", tint: .orange)
                MetricChip(title: "Известные", value: "\(monitor.knownCount)", tint: .blue)
                MetricChip(title: monitor.isQuietStart ? "Тихий старт" : "OK", value: monitor.isQuietStart ? "\(monitor.quietSecondsLeft)" : "OK", tint: .green)
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}

struct MetricChip: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 19, weight: .bold))
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct DeviceListView: View {
    let devices: [DetectedDevice]
    @Binding var selectedID: String?

    var body: some View {
        List(devices, selection: $selectedID) { device in
            DeviceRow(device: device)
                .tag(device.id)
                .padding(.vertical, 4)
        }
        .listStyle(.sidebar)
        .overlay {
            if devices.isEmpty {
                Text("скан")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct DeviceRow: View {
    let device: DetectedDevice

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(device.name)
                        .font(.system(size: 15, weight: .bold))
                        .lineLimit(1)
                    if !device.isKnown {
                        Text("новое")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.orange)
                    }
                }
                Text("\(device.kind) · \(device.shortID)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("\(device.displayRSSI) dBm")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(rssiColor(device.displayRSSI))
                Text(device.distanceText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 80, alignment: .trailing)

            VStack(alignment: .trailing, spacing: 4) {
                Text(SignalMath.powerBars(for: device.displayRSSI))
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(rssiColor(device.displayRSSI))
                Text(device.status)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(device.isApproaching ? .red : device.isJittery ? .orange : .secondary)
            }
            .frame(width: 90, alignment: .trailing)
        }
    }

    private func rssiColor(_ rssi: Int) -> Color {
        if rssi >= -58 { return .green }
        if rssi >= -72 { return .orange }
        return .secondary
    }
}

struct DeviceDetailView: View {
    let device: DetectedDevice
    @ObservedObject var monitor: BluetoothMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(device.name)
                        .font(.system(size: 32, weight: .bold))
                    Text(device.id)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusPill(device: device)
            }

            HStack(spacing: 12) {
                DetailMetric(title: "RSSI", value: "\(device.displayRSSI) dBm")
                DetailMetric(title: "Дистанция", value: device.distanceText)
                DetailMetric(title: "Пакеты", value: "\(device.totalSamples)")
                DetailMetric(title: "Статус", value: device.isKnown ? "известное" : "новое")
            }

            SignalChart(samples: device.samples)
                .frame(height: 150)
                .padding(14)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))

            VStack(alignment: .leading, spacing: 10) {
                InfoLine(title: "Тип", value: device.kind)
                InfoLine(title: "Первое обнаружение", value: elapsed(from: device.firstSeen))
                InfoLine(title: "Последний пакет", value: elapsed(from: device.lastSeen))
                InfoLine(title: "Raw RSSI", value: "\(device.rawRSSI) dBm")
                InfoLine(title: "Анализ", value: device.status)
            }
            .padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))

            HStack {
                Button {
                    monitor.trustCurrentDevices()
                } label: {
                    Label("Доверять текущим", systemImage: "checkmark.shield.fill")
                }
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(device.id, forType: .string)
                } label: {
                    Label("Копировать ID", systemImage: "doc.on.doc.fill")
                }
                Spacer()
            }

            Spacer()
        }
    }

    private func elapsed(from date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 60 { return "\(seconds) сек" }
        return "\(seconds / 60):" + String(format: "%02d", seconds % 60)
    }
}

struct StatusPill: View {
    let device: DetectedDevice

    var body: some View {
        Text(device.isApproaching ? "приближается" : device.isKnown ? "известное" : "новое")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(device.isApproaching ? .red : device.isKnown ? .green : .orange)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.regularMaterial, in: Capsule())
    }
}

struct DetailMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .bold))
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct InfoLine: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
        }
    }
}

struct SignalChart: View {
    let samples: [SignalSample]

    var body: some View {
        GeometryReader { proxy in
            Path { path in
                guard samples.count > 1 else { return }
                let values = samples.suffix(32)
                let minRSSI = min(-95, values.map(\.rssi).min() ?? -95)
                let maxRSSI = max(-35, values.map(\.rssi).max() ?? -35)
                let width = proxy.size.width
                let height = proxy.size.height
                for (index, sample) in values.enumerated() {
                    let x = width * CGFloat(index) / CGFloat(max(values.count - 1, 1))
                    let normalized = CGFloat(sample.rssi - minRSSI) / CGFloat(max(maxRSSI - minRSSI, 1))
                    let y = height - normalized * height
                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(.green, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        }
    }
}

struct SettingsView: View {
    @ObservedObject var monitor: BluetoothMonitor

    var body: some View {
        Form {
            Toggle("Звук включён", isOn: $monitor.soundEnabled)
            Button("Сбросить доверие") {
                monitor.resetTrust()
            }
        }
        .padding()
        .frame(width: 360)
    }
}
