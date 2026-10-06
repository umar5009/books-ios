import Foundation

struct Book: Identifiable, Codable, Hashable {
    let id: Int
    let title: String
    let authors: [String]
    let subjects: [String]
    let bookshelves: [String]
    let languages: [String]
    let coverURL: URL?
    let textURL: URL?
    let downloadCount: Int
    let summary: String?
    var authorBirthYear: Int? = nil
    var authorDeathYear: Int? = nil

    var authorLine: String {
        guard let first = authors.first else { return "Unknown author" }
        // Gutenberg stores "Austen, Jane" — flip to "Jane Austen".
        let parts = first.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let name = parts.count >= 2 ? "\(parts[1]) \(parts[0])" : first
        return authors.count > 1 ? "\(name) & others" : name
    }

    /// Normalised, de-duplicated topic tags used by the recommender.
    var tags: [String] {
        var out: [String] = []
        let raw = subjects.flatMap { $0.components(separatedBy: " -- ") } + bookshelves
        for r in raw {
            var t = r.lowercased()
            for prefix in ["browsing: ", "category: "] where t.hasPrefix(prefix) { t.removeFirst(prefix.count) }
            t = t.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            if t.count > 2, t.count < 40, !out.contains(t) { out.append(t) }
        }
        return out
    }

    /// Text the sentence-embedding model reads to understand the book.
    var featureText: String {
        let s = summary.map { String($0.prefix(400)) } ?? ""
        return "\(title). \(tags.prefix(8).joined(separator: ", ")). \(s)"
    }

    var displayTags: [String] { Array(tags.prefix(3)).map { $0.capitalized } }

    /// A year from the title when the catalogue includes one, otherwise the author's lifespan.
    var yearLine: String? {
        if let year = yearInTitle { return String(year) }
        switch (authorBirthYear, authorDeathYear) {
        case let (birth?, death?): return "\(birth)–\(death)"
        case let (birth?, nil): return "born \(birth)"
        case let (nil, death?): return "died \(death)"
        default: return nil
        }
    }

    /// A line to reveal when the shelf opens this book. Famous lines stay marked as quotes.
    var showcase: BookLine {
        if let quote = FamousLines.text(for: id) {
            return BookLine(text: quote, isQuote: true)
        }
        if let detail = previewDetail {
            return BookLine(text: detail, isQuote: false)
        }
        return BookLine(text: "Open it and begin.", isQuote: false)
    }

    /// A short blurb the shelf can show without opening the book.
    var previewDetail: String? {
        if let summary = summary?.trimmingCharacters(in: .whitespacesAndNewlines), summary.count > 24 {
            return summary
        }
        let topics = displayTags
        return topics.isEmpty ? nil : topics.joined(separator: " · ")
    }

    private var yearInTitle: Int? {
        guard let match = title.range(of: #"(?<!\d)(1[5-9]\d{2}|20[0-2]\d)(?!\d)"#, options: .regularExpression) else { return nil }
        return Int(title[match])
    }
}

struct BookLine {
    var text: String
    var isQuote: Bool
}

struct ReadingProgress: Codable, Hashable {
    var charOffset: Int = 0
    var fraction: Double = 0
    var minutesRead: Double = 0
    var lastOpened: Date = .now
    var finished = false
}
