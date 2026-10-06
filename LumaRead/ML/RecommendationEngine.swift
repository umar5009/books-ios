import Foundation
import NaturalLanguage

/// Temu/TikTok-style on-device recommender.
///
/// Every scroll, pause, tap, search and minute read is a training signal. The engine keeps:
///  • an **interest embedding** (512-d, Apple's on-device sentence-embedding model) learned online
///    from the books you engage with — "more like what you actually read";
///  • **tag affinities** (exponentially decayed counts per topic);
///  • a **Thompson-sampling bandit** per topic so the feed keeps exploring new interests
///    instead of getting stuck in a bubble;
///  • **MMR re-ranking** so the next screen is relevant *and* varied.
/// Nothing leaves the device.
@MainActor
final class RecommendationEngine: ObservableObject {
    static let shared = RecommendationEngine()

    enum Event {
        case impression, skip, dwell(TimeInterval), open, startRead, readMinutes(Double), finished, like, dislike, saved
        var weight: Double {
            switch self {
            case .impression: return 0
            case .skip: return -0.25
            case .dwell(let s): return min(0.8, s / 4)
            case .open: return 1.0
            case .startRead: return 2.0
            case .readMinutes(let m): return min(4, m * 0.4)
            case .finished: return 4.0
            case .like: return 3.0
            case .dislike: return -3.0
            case .saved: return 2.0
            }
        }
    }

    struct Beta: Codable { var a: Double = 1; var b: Double = 1 }

    struct Profile: Codable {
        var interest: [Double] = []
        var tagAffinity: [String: Double] = [:]
        var bandit: [String: Beta] = [:]
        var opened: Set<Int> = []
        var disliked: Set<Int> = []
        var recentQueries: [String] = []
        var lastOpenedTitle: String?
        var events = 0
    }

    /// Not @Published: impressions fire constantly; we notify only on meaningful changes.
    private(set) var profile = Profile()
    private let embedder = NLEmbedding.sentenceEmbedding(for: .english)
    private var vectorCache: [Int: [Double]] = [:]
    private let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("interest-profile.json")
    }()

    init() {
        if let d = try? Data(contentsOf: url), let p = try? JSONDecoder().decode(Profile.self, from: d) { profile = p }
    }

    var isColdStart: Bool { profile.events < 3 && profile.tagAffinity.isEmpty }

    // MARK: - Learning

    /// Cold start: seed from onboarding interests.
    func seed(interests: [String]) {
        for i in interests {
            profile.tagAffinity[i.lowercased(), default: 0] += 2
            if let v = embed(i) { blend(v, weight: 1.5) }
        }
        save()
    }

    func record(_ event: Event, book: Book) {
        let w = event.weight
        profile.events += 1

        // Bandit: impressions add a little "failure" mass, engagement adds "success" mass.
        for tag in book.tags.prefix(6) {
            var beta = profile.bandit[tag] ?? Beta()
            switch event {
            case .impression: beta.b += 0.15
            case .skip, .dislike: beta.b += 0.5
            default: if w > 0 { beta.a += min(2, w * 0.5) }
            }
            profile.bandit[tag] = beta
        }
        guard w != 0 else { return }

        // Tag affinity with decay so tastes can change.
        for key in profile.tagAffinity.keys { profile.tagAffinity[key]! *= 0.995 }
        for tag in book.tags.prefix(6) { profile.tagAffinity[tag, default: 0] += w }

        // Online interest embedding update.
        if let v = vector(for: book) { blend(v, weight: w) }

        switch event {
        case .open, .startRead: profile.opened.insert(book.id); profile.lastOpenedTitle = book.title
        case .dislike: profile.disliked.insert(book.id)
        case .skip, .dwell: return  // persisted with the next meaningful event; avoids re-rendering while scrolling
        default: break
        }
        save()
        objectWillChange.send()
    }

    func recordSearch(_ query: String) {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard q.count > 1 else { return }
        profile.recentQueries.removeAll { $0 == q }
        profile.recentQueries.insert(q, at: 0)
        profile.recentQueries = Array(profile.recentQueries.prefix(12))
        profile.tagAffinity[q, default: 0] += 1.5
        if let v = embed(q) { blend(v, weight: 1.2) }
        profile.events += 1
        save()
        objectWillChange.send()
    }

    func reset() {
        profile = Profile(); vectorCache = [:]; save()
        objectWillChange.send()
    }

    // MARK: - Candidate generation

    /// Topics to fetch next. Mixes exploitation (top affinities), exploration (Thompson samples)
    /// and recent searches — this is what makes the feed drift towards your new interests.
    func nextTopics(count: Int = 3, mood: Mood?, lift: Bool) -> [String] {
        var topics: [String] = []
        if let mood { topics.append(contentsOf: (lift && mood.isLow ? mood.liftTopics : mood.matchTopics).prefix(1)) }
        topics.append(contentsOf: profile.recentQueries.prefix(1))
        let top = profile.tagAffinity.sorted { $0.value > $1.value }.prefix(6).map(\.key)
        topics.append(contentsOf: top.shuffled().prefix(2))
        let sampled = profile.bandit
            .map { ($0.key, Self.sampleBeta($0.value)) }
            .sorted { $0.1 > $1.1 }
            .prefix(4).map(\.0)
        topics.append(contentsOf: sampled.shuffled().prefix(1))
        if topics.isEmpty { topics = ["adventure", "romance", "science fiction", "mystery"].shuffled() }
        var seen = Set<String>()
        return topics.filter { seen.insert($0).inserted }.prefix(count).map { $0 }
    }

    // MARK: - Ranking

    struct Scored: Identifiable { let book: Book; let score: Double; let reason: String; var id: Int { book.id } }

    func rank(_ books: [Book], mood: Mood?, lift: Bool, limit: Int, excluding: Set<Int> = []) -> [Scored] {
        let user = profile.interest.isEmpty ? nil : profile.interest
        let maxAff = max(1, profile.tagAffinity.values.max() ?? 1)
        let moodTopics = mood.map { Set(lift && $0.isLow ? $0.liftTopics : $0.matchTopics) } ?? []

        var scored: [(Scored, [Double]?)] = books
            .filter { !excluding.contains($0.id) && !profile.disliked.contains($0.id) }
            .map { (book: Book) -> (Scored, [Double]?) in
                let v = vector(for: book)
                let sim = (user != nil && v != nil) ? cosine(user!, v!) : 0
                let tags = book.tags
                let aff = tags.prefix(6).map { (profile.tagAffinity[$0] ?? 0) / maxAff }.max() ?? 0
                let moodHit = tags.contains { t in moodTopics.contains { t.contains($0) } } ? 1.0 : 0
                let pop = log10(Double(max(10, book.downloadCount))) / 5
                let explore = tags.prefix(4).map { Self.sampleBeta(profile.bandit[$0] ?? Beta()) }.max() ?? 0.5
                let seenPenalty = profile.opened.contains(book.id) ? 0.35 : 0
                let s = 0.40 * sim + 0.22 * aff + 0.15 * moodHit + 0.10 * pop + 0.13 * explore - seenPenalty

                let reason: String
                if moodHit > 0, let mood { reason = "For your \(mood.title.lowercased()) mood" }
                else if sim > 0.55, let t = profile.lastOpenedTitle { reason = "Because you opened \(t.prefix(22))" }
                else if aff > 0.5, let t = tags.first { reason = "You like \(t)" }
                else if explore > 0.8 { reason = "Something new for you" }
                else { reason = book.downloadCount > 20_000 ? "Trending classic" : "Hidden gem" }
                return (Scored(book: book, score: s, reason: reason), v)
            }

        // Maximal Marginal Relevance for diversity.
        var picked: [(Scored, [Double]?)] = []
        while picked.count < limit, !scored.isEmpty {
            var bestIdx = 0, bestVal = -Double.infinity
            for (i, cand) in scored.enumerated() {
                let redundancy = picked.compactMap { p -> Double? in
                    guard let a = p.1, let b = cand.1 else { return nil }
                    return cosine(a, b)
                }.max() ?? 0
                let val = 0.75 * cand.0.score - 0.25 * redundancy
                if val > bestVal { bestVal = val; bestIdx = i }
            }
            picked.append(scored.remove(at: bestIdx))
        }
        return picked.map(\.0)
    }

    // MARK: - Helpers

    func vector(for book: Book) -> [Double]? {
        if let v = vectorCache[book.id] { return v }
        let v = embed(book.featureText)
        vectorCache[book.id] = v
        return v
    }

    private func embed(_ text: String) -> [Double]? { embedder?.vector(for: text) }

    private func blend(_ v: [Double], weight w: Double) {
        if profile.interest.count != v.count { profile.interest = Array(repeating: 0, count: v.count) }
        for i in v.indices { profile.interest[i] = profile.interest[i] * 0.97 + w * v[i] }
    }

    private func cosine(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count else { return 0 }
        var dot = 0.0, na = 0.0, nb = 0.0
        for i in a.indices { dot += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i] }
        return na > 0 && nb > 0 ? dot / (sqrt(na) * sqrt(nb)) : 0
    }

    /// Beta sample via two Gamma draws (Marsaglia–Tsang).
    static func sampleBeta(_ p: Beta) -> Double {
        let x = gamma(p.a), y = gamma(p.b)
        return x / (x + y)
    }

    private static func gamma(_ shape: Double) -> Double {
        if shape < 1 { return gamma(shape + 1) * pow(Double.random(in: 0.0001..<1), 1 / shape) }
        let d = shape - 1.0 / 3.0, c = 1 / sqrt(9 * d)
        while true {
            var x = 0.0, v = 0.0
            repeat {
                // Box–Muller normal
                let u1 = Double.random(in: 0.0001..<1), u2 = Double.random(in: 0..<1)
                x = sqrt(-2 * log(u1)) * cos(2 * .pi * u2)
                v = 1 + c * x
            } while v <= 0
            v = v * v * v
            let u = Double.random(in: 0.0001..<1)
            if log(u) < 0.5 * x * x + d - d * v + d * log(v) { return d * v }
        }
    }

    private func save() {
        if let d = try? JSONEncoder().encode(profile) { try? d.write(to: url, options: .atomic) }
    }
}
