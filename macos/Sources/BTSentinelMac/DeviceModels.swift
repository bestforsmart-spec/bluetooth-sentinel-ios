import Foundation

struct SignalSample: Identifiable {
    let id = UUID()
    let time: Date
    let rssi: Int
}

struct DetectedDevice: Identifiable {
    let id: String
    var name: String
    var kind: String
    var rawRSSI: Int
    var displayRSSI: Int
    var firstSeen: Date
    var lastSeen: Date
    var samples: [SignalSample]
    var totalSamples: Int
    var isKnown: Bool
    var isApproaching: Bool
    var isJittery: Bool
    var orderBoostAt: Date

    var status: String {
        if isApproaching { return "ближе" }
        if isJittery { return "дрожит" }
        return "скан"
    }

    var distanceText: String {
        let meters = pow(10.0, (-59.0 - Double(displayRSSI)) / 24.0)
        if meters < 1 { return "~<1 м" }
        if meters < 10 { return String(format: "~%.1f м", meters) }
        return String(format: "~%.0f м", meters)
    }

    var shortID: String {
        String(id.suffix(8))
    }
}
