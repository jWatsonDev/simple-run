import AVFoundation

/// Spoken split updates. Ducks music/podcasts while talking, then hands audio back.
@MainActor
final class Announcer: NSObject, AVSpeechSynthesizerDelegate {
    /// Options offered in settings, in miles. 0 = off.
    static let intervals: [Double] = [0, 0.25, 0.5, 1]
    static let defaultInterval = 0.5
    static let intervalKey = "announceEveryMiles"

    static var interval: Double {
        UserDefaults.standard.object(forKey: intervalKey) as? Double ?? defaultInterval
    }

    static func label(for miles: Double) -> String {
        switch miles {
        case 0: "Off"
        case 0.25: "¼ mile"
        case 0.5: "½ mile"
        default: "\(Format.trimmed(miles)) mile"
        }
    }

    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func split(miles: Double, seconds: TimeInterval) {
        let pace = seconds / miles
        speak("\(spokenDistance(miles)). Time, \(spokenDuration(seconds)). Average pace, \(spokenDuration(pace)) per mile.")
    }

    func speak(_ text: String) {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        try? session.setActive(true)
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.05
        synthesizer.speak(utterance)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard !self.synthesizer.isSpeaking else { return }
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    private func spokenDistance(_ miles: Double) -> String {
        switch miles {
        case 0.25: "A quarter mile"
        case 0.5: "Half a mile"
        case 0.75: "Three quarters of a mile"
        case 1: "1 mile"
        default: "\(Format.trimmed(miles)) miles"
        }
    }

    private func spokenDuration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded())
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        var parts: [String] = []
        if h > 0 { parts.append("\(h) \(h == 1 ? "hour" : "hours")") }
        if m > 0 { parts.append("\(m) \(m == 1 ? "minute" : "minutes")") }
        if sec > 0 || parts.isEmpty { parts.append("\(sec) \(sec == 1 ? "second" : "seconds")") }
        return parts.joined(separator: " ")
    }
}
