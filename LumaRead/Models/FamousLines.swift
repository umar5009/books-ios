import Foundation

/// Well-known lines for public-domain books, keyed by Project Gutenberg id.
enum FamousLines {
    static func text(for id: Int) -> String? { lines[id] }

    private static let lines: [Int: String] = [
        11: "Curiouser and curiouser!",
        16: "To die will be an awfully big adventure.",
        43: "If he be Mr. Hyde, I shall be Mr. Seek.",
        46: "God bless us, every one!",
        76: "All right, then, I'll go to hell.",
        84: "Beware; for I am fearless, and therefore powerful.",
        98: "It was the best of times, it was the worst of times.",
        174: "The only way to get rid of a temptation is to yield to it.",
        345: "Listen to them, the children of the night. What music they make!",
        520: "One morning, when Gregor Samsa woke from troubled dreams, he found himself transformed in his bed into a horrible vermin.",
        768: "Whatever our souls are made of, his and mine are the same.",
        1184: "All human wisdom is contained in these two words: wait and hope.",
        1260: "I am no bird; and no net ensnares me.",
        1342: "It is a truth universally acknowledged, that a single man in possession of a good fortune, must be in want of a wife.",
        1513: "O Romeo, Romeo! wherefore art thou Romeo?",
        1514: "The course of true love never did run smooth.",
        1524: "To be, or not to be, that is the question.",
        1533: "Out, damned spot! out, I say!",
        1399: "All happy families are alike; each unhappy family is unhappy in its own way.",
        1661: "You see, but you do not observe.",
        2701: "Call me Ishmael.",
    ]
}
