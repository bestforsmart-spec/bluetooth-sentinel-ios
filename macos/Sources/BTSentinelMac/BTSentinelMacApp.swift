import SwiftUI

@main
struct BTSentinelMacApp: App {
    @StateObject private var monitor = BluetoothMonitor()

    var body: some Scene {
        WindowGroup {
            ContentView(monitor: monitor)
                .frame(minWidth: 980, minHeight: 640)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("BT Sentinel") {
                Button(monitor.soundEnabled ? "Беззвучный режим" : "Включить звук") {
                    monitor.soundEnabled.toggle()
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])

                Button("Доверять текущим") {
                    monitor.trustCurrentDevices()
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])

                Button("Сбросить доверие") {
                    monitor.resetTrust()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView(monitor: monitor)
        }
    }
}
