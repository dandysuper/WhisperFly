import Foundation
import SwiftUI

/// Live input level history for the waveform in the floating pill.
///
/// Kept apart from `AppController` on purpose: the controller used to publish
/// `audioLevel` twenty times a second, which re-rendered the menu bar window and
/// every other observer on each meter tick. Only the waveform watches this, and
/// updates are throttled to the display rate the bars actually need.
@MainActor
final class AudioMeter: ObservableObject {

    static let barCount = 24

    /// Normalised levels (0…1), oldest first.
    @Published private(set) var levels: [CGFloat] = Array(repeating: 0, count: AudioMeter.barCount)

    private var lastUpdate = Date.distantPast
    private var smoothed: CGFloat = 0
    private let minimumInterval: TimeInterval = 1.0 / 24.0

    /// Feeds one level in dBFS. Called from any rate; coalesced here.
    func push(dBFS: Float) {
        let now = Date()
        guard now.timeIntervalSince(lastUpdate) >= minimumInterval else { return }
        lastUpdate = now

        // -55 dBFS and below reads as silence; speech peaks around -20…-10.
        let clamped = max(-55, min(0, dBFS))
        let linear = CGFloat((clamped + 55) / 55)
        // Ease toward the new value so bars move smoothly instead of flickering.
        smoothed = smoothed * 0.35 + linear * 0.65
        var next = levels
        next.removeFirst()
        next.append(min(1, pow(smoothed, 1.4) * 1.25))
        levels = next
    }

    func reset() {
        smoothed = 0
        levels = Array(repeating: 0, count: Self.barCount)
    }
}
