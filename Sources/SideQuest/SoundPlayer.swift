import AVFoundation

@MainActor
final class SoundPlayer {
    static var shared = SoundPlayer()

    // Retain the player until playback finishes. A new cue replaces the previous one.
    private var player: AVAudioPlayer?

    func play(sound: Sound) {
        player?.stop()
        player = nil

        // Audio is optional and lives outside the app bundle. Missing or unreadable
        // files must not interrupt saving, completing or abandoning a quest.
        guard let directory = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else { return }
        let url = directory
            .appendingPathComponent("SideQuest/Sounds", isDirectory: true)
            .appendingPathComponent(sound.fileName)

        guard FileManager.default.fileExists(atPath: url.path),
            let player = try? AVAudioPlayer(contentsOf: url)
        else { return }

        self.player = player
        player.prepareToPlay()
        player.play()
    }
}

// MARK: - Optional local cues

extension SoundPlayer {
    enum Sound {
        case complete
        case new
        case abandoned

        var fileName: String {
            switch self {
            case .complete: "quest-completed.mp3"
            case .new: "quest-created.mp3"
            case .abandoned: "quest-abandoned.mp3"
            }
        }
    }
}
