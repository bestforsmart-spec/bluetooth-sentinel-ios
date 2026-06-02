import SwiftUI

@main
struct BluetoothSentinelApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var monitor = BluetoothMonitor()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(monitor)
                .onChange(of: scenePhase) { _, newPhase in
                    switch newPhase {
                    case .active:
                        monitor.handleAppDidBecomeActive()
                    case .background:
                        monitor.handleAppDidEnterBackground()
                    case .inactive:
                        break
                    @unknown default:
                        break
                    }
                }
        }
    }
}
