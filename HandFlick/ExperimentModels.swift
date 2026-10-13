import Foundation

enum InputMethod: String, Codable, CaseIterable, Identifiable { case handFlick, defaultDirect, defaultGazePinch
    var id: String { rawValue }
    var title: String { switch self { case .handFlick: "HandFlick"; case .defaultDirect: "Default Keyboard — Direct Touch"; case .defaultGazePinch: "Default Keyboard — Gaze + Pinch" } }
    var instruction: String { switch self { case .handFlick: "Use your left hand as the input surface and your right index finger to tap or flick."; case .defaultDirect: "Please operate the default keyboard using direct finger touch only."; case .defaultGazePinch: "Please operate the default keyboard using gaze and pinch only. Do not directly touch the keyboard." } }
}

struct Phrase: Codable, Identifiable, Hashable { let id: String; let setID: String; let text: String }
struct HandRegion: Codable, Hashable, Identifiable { let finger: FingerID; let segment: SegmentID; var id: String { "\(finger.rawValue)-\(segment.rawValue)" } }
enum FingerID: String, Codable, CaseIterable { case index, middle, ring, little }
enum SegmentID: String, Codable, CaseIterable { case proximal, middle, distal }
enum FlickAction: String, Codable, CaseIterable { case center, forward, backward, radial, ulnar }
struct HandFlickPrimitive: Codable, Hashable { let region: HandRegion; let action: FlickAction }

struct FlickKeyMapping: Codable, Hashable, Identifiable {
    let keyID: String; let region: HandRegion; let characterByAction: [String: String]
    var id: String { keyID }
    func output(for action: FlickAction) -> String? { characterByAction[action.rawValue] }
}
struct EnglishHandFlickLayout: Codable {
    var keys: [FlickKeyMapping]
    var space: HandFlickPrimitive
    var backspace: HandFlickPrimitive
    var caseToggle: HandFlickPrimitive
    static let caseToggleOutput = "__handflick_case_toggle__"
    func output(for primitive: HandFlickPrimitive) -> String? {
        if primitive == caseToggle { return Self.caseToggleOutput }
        if primitive == space { return " " }; if primitive == backspace { return "\u{8}" }
        return keys.first(where: { $0.region == primitive.region })?.output(for: primitive.action)
    }
}
struct HandFlickConfig: Codable {
    /// All distances are normalized by index-to-little-knuckle palm width.
    var contactThreshold: Float = 0.20; var releaseThreshold: Float = 0.27
    // A tap traverses part of the contact volume and includes ARKit jitter.  Require a clearly
    // larger palm-relative movement before treating it as a directional flick.
    var flickDistanceThreshold: Float = 0.16; var minimumContactDuration: TimeInterval = 0.025
    // A research trial should register deliberate, short taps; use one tracked frame for each
    // edge and control accidental repeats with the re-arm requirement and cooldown instead.
    var cooldownDuration: TimeInterval = 0.08; var stableContactFrames = 1; var stableReleaseFrames = 1
    var maximumContactDuration: TimeInterval = 0.90; var maximumFrameSkew: TimeInterval = 0.12
}
struct ExperimentConfig: Codable {
    var numberOfBlocks = 3; var phrasesPerBlock = 8; var enableDebugView = false
    var handFlickConfig = HandFlickConfig(); var breakAfterEachBlock = true; var breakAfterEachCondition = true
    var layout = EnglishHandFlickLayout.default
}
extension EnglishHandFlickLayout {
    static let `default` = EnglishHandFlickLayout(
        keys: [
            // iPhone Japanese 12-key English mode: center, left, up, right, down.
            // On this left-palm surface: left = wrist (backward), up = index side (radial),
            // right = finger-tip direction (forward), down = little-finger side (ulnar).
            .init(keyID: "ABC", region: .init(finger: .index, segment: .middle), characterByAction: ["center": "a", "backward": "b", "radial": "c"]),
            .init(keyID: "DEF", region: .init(finger: .index, segment: .distal), characterByAction: ["center": "d", "backward": "e", "radial": "f"]),
            .init(keyID: "GHI", region: .init(finger: .middle, segment: .proximal), characterByAction: ["center": "g", "backward": "h", "radial": "i"]),
            .init(keyID: "JKL", region: .init(finger: .middle, segment: .middle), characterByAction: ["center": "j", "backward": "k", "radial": "l"]),
            .init(keyID: "MNO", region: .init(finger: .middle, segment: .distal), characterByAction: ["center": "m", "backward": "n", "radial": "o"]),
            .init(keyID: "PQRS", region: .init(finger: .ring, segment: .proximal), characterByAction: ["center": "p", "backward": "q", "radial": "r", "forward": "s"]),
            .init(keyID: "TUV", region: .init(finger: .ring, segment: .middle), characterByAction: ["center": "t", "backward": "u", "radial": "v"]),
            .init(keyID: "WXYZ", region: .init(finger: .ring, segment: .distal), characterByAction: ["center": "w", "backward": "x", "radial": "y", "forward": "z"])],
        space: .init(region: .init(finger: .little, segment: .middle), action: .center),
        backspace: .init(region: .init(finger: .little, segment: .distal), action: .center),
        caseToggle: .init(region: .init(finger: .little, segment: .proximal), action: .center))
}
