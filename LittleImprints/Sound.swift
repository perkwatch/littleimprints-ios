// Sound.swift — the one soft "stamp" sound on lift-off (spec §2.4).
// A bundled 0.2 s synthesized thump; no other sounds exist in the app.

import AVFoundation

public final class StampSound {
    public static let shared = StampSound()
    private var player: AVAudioPlayer?

    private init() {
        if let url = Bundle.main.url(forResource: "stamp", withExtension: "wav") {
            player = try? AVAudioPlayer(contentsOf: url)
            player?.volume = 0.55
            player?.prepareToPlay()
        }
    }

    public func play(enabled: Bool) {
        guard enabled, let player else { return }
        if player.isPlaying { player.currentTime = 0 }
        player.play()
    }
}
