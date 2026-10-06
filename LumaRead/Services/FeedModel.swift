import Foundation

/// Infinite "For You" feed. Each time you near the bottom it fetches candidates for the topics the
/// recommender currently believes in (plus exploration), re-ranks the whole unseen pool with the
/// latest interest profile, and appends the next batch — so what you just tapped shapes what comes next.
@MainActor
final class FeedModel: ObservableObject {
    @Published private(set) var items: [RecommendationEngine.Scored] = []
    @Published private(set) var moodPicks: [RecommendationEngine.Scored] = []
    @Published private(set) var isLoading = false
    @Published var error: String?

    private var pool: [Int: Book] = [:]
    private var shown: Set<Int> = []
    private var topicPage: [String: Int] = [:]
    private var popularPage = 1
    private var priorityTopics: [String] = []

    private var engine: RecommendationEngine { .shared }

    func reload(mood: Mood?, lift: Bool) async {
        items = []; shown = []
        await loadMore(mood: mood, lift: lift)
    }

    func loadMore(mood: Mood?, lift: Bool) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        var topics = priorityTopics + engine.nextTopics(count: 3, mood: mood, lift: lift)
        priorityTopics.removeAll()
        var seen = Set<String>()
        topics = Array(topics.filter { seen.insert($0).inserted }.prefix(4))
        await fetch(topics: topics, includePopular: pool.count < 40)

        let batch = engine.rank(Array(pool.values), mood: mood, lift: lift, limit: 12, excluding: shown)
        shown.formUnion(batch.map(\.book.id))
        items.append(contentsOf: batch)
        if batch.isEmpty && pool.count < 500 {
            popularPage += 1
            await fetch(topics: [], includePopular: true)
        }
    }

    func loadMoodPicks(_ mood: Mood, lift: Bool) async {
        let topics = Array((lift && mood.isLow ? mood.liftTopics : mood.matchTopics).prefix(2))
        await fetch(topics: topics, includePopular: false)
        moodPicks = engine.rank(Array(pool.values), mood: mood, lift: lift, limit: 10)
    }

    /// Called when the user opens a book so the very next batch leans into it.
    func learn(from book: Book) {
        if let tag = book.tags.first { priorityTopics.insert(tag, at: 0) }
    }

    private func fetch(topics: [String], includePopular: Bool) async {
        let pages = topics.map { ($0, topicPage[$0, default: 1]) }
        let popular = popularPage
        let results: [(String?, GutendexService.Result?)] = await withTaskGroup(of: (String?, GutendexService.Result?).self) { group in
            for (t, p) in pages {
                group.addTask { (t, try? await GutendexService.shared.fetch(topic: t, page: p)) }
            }
            if includePopular {
                group.addTask { (nil, try? await GutendexService.shared.fetch(page: popular)) }
            }
            var out: [(String?, GutendexService.Result?)] = []
            for await r in group { out.append(r) }
            return out
        }
        var gotAny = false
        for (topic, result) in results {
            guard let result else { continue }
            gotAny = true
            for b in result.books where b.textURL != nil { pool[b.id] = b }
            if let topic { topicPage[topic, default: 1] += result.hasMore ? 1 : 0 }
            else { popularPage += 1 }
        }
        if !gotAny && pool.isEmpty { error = "Can't reach the library right now. Pull to retry." } else { error = nil }
    }
}
