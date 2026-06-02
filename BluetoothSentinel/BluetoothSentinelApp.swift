import SwiftUI

@main
struct BluetoothSentinelApp: App {
    @StateObject private var monitor = BluetoothMonitor()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(monitor)
        }
    }
}
