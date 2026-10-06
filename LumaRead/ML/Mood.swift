import SwiftUI

enum Mood: String, CaseIterable, Codable, Identifiable {
    case joyful, calm, curious, adventurous, romantic, melancholy, stressed, tired
    var id: String { rawValue }

    var title: String { rawValue.capitalized }

    var symbol: String {
        switch self {
        case .joyful: return "sun.max.fill"
        case .calm: return "leaf.fill"
        case .curious: return "lightbulb.fill"
        case .adventurous: return "mountain.2.fill"
        case .romantic: return "heart.fill"
        case .melancholy: return "cloud.rain.fill"
        case .stressed: return "bolt.heart.fill"
        case .tired: return "moon.zzz.fill"
        }
    }

    var color: Color {
        switch self {
        case .joyful: return Color(red: 1.0, green: 0.78, blue: 0.30)
        case .calm: return Color(red: 0.40, green: 0.85, blue: 0.65)
        case .curious: return Color(red: 0.35, green: 0.75, blue: 1.0)
        case .adventurous: return Color(red: 1.0, green: 0.50, blue: 0.30)
        case .romantic: return Color(red: 1.0, green: 0.45, blue: 0.65)
        case .melancholy: return Color(red: 0.55, green: 0.60, blue: 0.95)
        case .stressed: return Color(red: 0.95, green: 0.40, blue: 0.40)
        case .tired: return Color(red: 0.62, green: 0.50, blue: 0.95)
        }
    }

    /// Gutendex topics that match this mood ("mirror") ...
    var matchTopics: [String] {
        switch self {
        case .joyful: return ["humor", "comedy", "adventure"]
        case .calm: return ["nature", "poetry", "essays"]
        case .curious: return ["science", "history", "philosophy"]
        case .adventurous: return ["adventure", "sea stories", "science fiction"]
        case .romantic: return ["love stories", "romance", "domestic fiction"]
        case .melancholy: return ["poetry", "tragedy", "psychological fiction"]
        case .stressed: return ["humor", "short stories", "nature"]
        case .tired: return ["fairy tales", "short stories", "poetry"]
        }
    }

    /// ... and topics that gently lift a low mood.
    var liftTopics: [String] {
        switch self {
        case .melancholy: return ["humor", "friendship", "fairy tales"]
        case .stressed: return ["nature", "humor", "poetry"]
        case .tired: return ["short stories", "humor", "fairy tales"]
        default: return matchTopics
        }
    }

    var isLow: Bool { [.melancholy, .stressed, .tired].contains(self) }

    var blurb: String {
        switch self {
        case .joyful: return "You sound bright! Here are witty, high-energy reads."
        case .calm: return "A settled mood — slow, beautiful prose to match."
        case .curious: return "Your mind is hungry. Big ideas and true stories ahead."
        case .adventurous: return "Restless energy — let's go somewhere far away."
        case .romantic: return "Heart-first stories for a tender mood."
        case .melancholy: return "A softer day. Gentle, warm stories to keep you company."
        case .stressed: return "Let's slow your breathing — light, comforting picks."
        case .tired: return "Low battery? Short, cosy reads that don't ask much."
        }
    }

    /// Keyword lexicon (stems) used by the rule-based layer of the classifier.
    var lexicon: [String] {
        switch self {
        case .joyful: return ["happy", "great", "awesome", "amazing", "excit", "fun", "glad", "good day", "love it", "fantastic", "celebrat", "laugh"]
        case .calm: return ["calm", "relax", "peace", "chill", "quiet", "fine", "okay", "content", "slow", "sunday", "coffee", "tea"]
        case .curious: return ["curious", "learn", "wonder", "why", "how", "interest", "know", "discover", "science", "history", "idea"]
        case .adventurous: return ["adventure", "travel", "explore", "bored", "restless", "trip", "wild", "action", "escape", "thrill"]
        case .romantic: return ["love", "crush", "date", "romant", "heart", "miss you", "partner", "wedding", "kiss"]
        case .melancholy: return ["sad", "lonely", "alone", "cry", "down", "miss", "lost", "grief", "hurt", "empty", "blue", "upset"]
        case .stressed: return ["stress", "anxious", "worr", "deadline", "exam", "busy", "overwhelm", "pressure", "angry", "frustrat", "nervous"]
        case .tired: return ["tired", "sleep", "exhaust", "drained", "long day", "can't focus", "sleepy", "worn out", "lazy"]
        }
    }
}
