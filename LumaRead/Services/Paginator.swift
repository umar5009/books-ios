import UIKit

/// Lays text out into exact lines with TextKit so the reader knows the precise
/// rectangle of every line and word — required for gaze → line/word mapping.
enum Paginator {
    struct Line: Hashable {
        let text: String
        let offset: Int      // UTF-16 offset in the book, used to keep your place when font size changes
        var isBreak: Bool { text.isEmpty }
    }

    /// Lays out a batch of paragraphs. Returns lines and the offset after the batch.
    static func layout(paragraphs: [String], startOffset: Int, width: CGFloat, font: UIFont) -> (lines: [Line], end: Int) {
        let joined = paragraphs.joined(separator: "\n")
        let ns = joined as NSString
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        style.hyphenationFactor = 0
        let storage = NSTextStorage(string: joined, attributes: [.font: font, .paragraphStyle: style])
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        manager.ensureLayout(for: container)

        var lines: [Line] = []
        let glyphs = NSRange(location: 0, length: manager.numberOfGlyphs)
        manager.enumerateLineFragments(forGlyphRange: glyphs) { _, _, _, glyphRange, _ in
            let r = manager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            let raw = ns.substring(with: r)
            let endsParagraph = raw.hasSuffix("\n")
            let text = raw.trimmingCharacters(in: .newlines).trimmingCharacters(in: .whitespaces)
            lines.append(Line(text: text, offset: startOffset + r.location))
            if endsParagraph { lines.append(Line(text: "", offset: startOffset + r.location + r.length)) }
        }
        lines.append(Line(text: "", offset: startOffset + ns.length)) // break after the batch's last paragraph
        return (lines, startOffset + ns.length + 1)
    }

    /// Splits paragraphs into ~25k-character batches so the first page appears instantly.
    static func batches(_ paragraphs: [String], size: Int = 25_000) -> [[String]] {
        var out: [[String]] = [], cur: [String] = [], count = 0
        for p in paragraphs {
            cur.append(p); count += p.utf16.count
            if count >= size { out.append(cur); cur = []; count = 0 }
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }
}
