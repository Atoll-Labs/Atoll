import Defaults

enum MusicControlButton: String, CaseIterable, Identifiable, Codable, Defaults.Serializable {
    case shuffle
    case trackBackward
    case playPause
    case trackForward
    case repeatMode
    case mediaOutput
    case lyrics
    case seekBackward
    case seekForward
    case none

    static let slotCount = 5

    static let defaultLayout: [MusicControlButton] = [
        .shuffle,
        .trackBackward,
        .playPause,
        .trackForward,
        .repeatMode
    ]

    static let minimalLayout: [MusicControlButton] = [
        .none,
        .trackBackward,
        .playPause,
        .trackForward,
        .none
    ]

    static let pickerOptions: [MusicControlButton] = [
        .trackBackward,
        .playPause,
        .trackForward,
        .seekBackward,
        .seekForward,
        .shuffle,
        .repeatMode,
        .lyrics,
        .mediaOutput
    ]

    var id: String { rawValue }

    var label: String {
        switch self {
        case .shuffle:
            return "Shuffle"
        case .trackBackward:
            return "Previous Track"
        case .playPause:
            return "Play / Pause"
        case .trackForward:
            return "Next Track"
        case .repeatMode:
            return "Repeat"
        case .mediaOutput:
            return "Media Output"
        case .lyrics:
            return "Lyrics"
        case .seekBackward:
            return "Rewind 10s"
        case .seekForward:
            return "Forward 10s"
        case .none:
            return "Empty Slot"
        }
    }

    var iconName: String {
        switch self {
        case .shuffle:
            return "shuffle"
        case .trackBackward:
            return "backward.fill"
        case .playPause:
            return "playpause"
        case .trackForward:
            return "forward.fill"
        case .repeatMode:
            return "repeat"
        case .mediaOutput:
            return "speaker.wave.2"
        case .lyrics:
            return "quote.bubble"
        case .seekBackward:
            return "gobackward.10"
        case .seekForward:
            return "goforward.10"
        case .none:
            return ""
        }
    }

    var prefersLargeScale: Bool {
        self == .playPause
    }
}

extension Array where Element == MusicControlButton {
    func normalized(allowingMediaOutput: Bool) -> [MusicControlButton] {
        var sanitized = map { button -> MusicControlButton in
            if button == .mediaOutput && !allowingMediaOutput {
                return .none
            }
            return button
        }

        if sanitized.count < MusicControlButton.slotCount {
            sanitized.append(contentsOf: Array(repeating: .none, count: MusicControlButton.slotCount - sanitized.count))
        }

        if sanitized.count > MusicControlButton.slotCount {
            sanitized = Array(sanitized.prefix(MusicControlButton.slotCount))
        }

        return sanitized
    }
}

extension MusicControlButton {
    init(auxiliaryControl: MusicAuxiliaryControl) {
        switch auxiliaryControl {
        case .shuffle:
            self = .shuffle
        case .repeatMode:
            self = .repeatMode
        case .mediaOutput:
            self = .mediaOutput
        case .lyrics:
            self = .lyrics
        }
    }
}
