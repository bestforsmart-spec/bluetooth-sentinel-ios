import Foundation

enum SignalMath {
    static func trimmedMedian(_ samples: [SignalSample], trimRatio: Double = 0.18) -> Int {
        guard !samples.isEmpty else { return -127 }
        let sorted = samples.map(\.rssi).sorted()
        let trim = max(0, Int(floor(Double(sorted.count) * trimRatio)))
        let lower = min(trim, sorted.count - 1)
        let upper = max(lower + 1, sorted.count - trim)
        let core = Array(sorted[lower..<upper])
        return core[core.count / 2]
    }

    static func spread(_ samples: [SignalSample]) -> Int {
        guard samples.count >= 4 else { return 0 }
        let values = samples.map(\.rssi)
        return (values.max() ?? -127) - (values.min() ?? -127)
    }

    static func powerBars(for rssi: Int) -> String {
        let level: Int
        switch rssi {
        case -55...0: level = 10
        case -62 ... -56: level = 8
        case -70 ... -63: level = 6
        case -78 ... -71: level = 4
        case -86 ... -79: level = 2
        default: level = 1
        }
        return String(repeating: "▮", count: level) + String(repeating: "▯", count: 10 - level)
    }

    static func rssiColor(_ rssi: Int) -> String {
        if rssi >= -58 { return "green" }
        if rssi >= -72 { return "orange" }
        return "muted"
    }
}
