import AVFoundation
import Foundation

final class AlertSoundPlayer: NSObject, AVAudioPlayerDelegate {
    private var players: [AVAudioPlayer] = []

    func playAlert() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            // The generated tone can still play in many foreground cases.
        }

        Task { @MainActor in
            playTone(frequency: 1320, duration: 0.16)
            try? await Task.sleep(nanoseconds: 210_000_000)
            playTone(frequency: 1760, duration: 0.18)
        }
    }

    private func playTone(frequency: Double, duration: Double) {
        guard let data = ToneGenerator.wavData(frequency: frequency, duration: duration) else { return }

        do {
            let player = try AVAudioPlayer(data: data)
            player.delegate = self
            player.prepareToPlay()
            players.append(player)
            player.play()
        } catch {
            return
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        players.removeAll { $0 === player }
    }
}

enum ToneGenerator {
    static func wavData(frequency: Double, duration: Double, sampleRate: Int = 44_100) -> Data? {
        let sampleCount = Int(duration * Double(sampleRate))
        let byteRate = sampleRate * 2
        let dataSize = sampleCount * 2
        var data = Data()

        data.append(contentsOf: "RIFF".utf8)
        data.appendUInt32LE(UInt32(36 + dataSize))
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8)
        data.appendUInt32LE(16)
        data.appendUInt16LE(1)
        data.appendUInt16LE(1)
        data.appendUInt32LE(UInt32(sampleRate))
        data.appendUInt32LE(UInt32(byteRate))
        data.appendUInt16LE(2)
        data.appendUInt16LE(16)
        data.append(contentsOf: "data".utf8)
        data.appendUInt32LE(UInt32(dataSize))

        for sampleIndex in 0..<sampleCount {
            let progress = Double(sampleIndex) / Double(sampleRate)
            let fadeIn = min(1.0, Double(sampleIndex) / Double(sampleRate) / 0.015)
            let fadeOut = min(1.0, Double(sampleCount - sampleIndex) / Double(sampleRate) / 0.025)
            let envelope = min(fadeIn, fadeOut)
            let value = sin(2.0 * .pi * frequency * progress) * envelope * 0.48
            data.appendInt16LE(Int16(value * Double(Int16.max)))
        }

        return data
    }
}

private extension Data {
    mutating func appendUInt16LE(_ value: UInt16) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }

    mutating func appendInt16LE(_ value: Int16) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}
