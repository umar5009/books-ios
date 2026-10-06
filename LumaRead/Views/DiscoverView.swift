import SwiftUI

struct DiscoverView: View {
    @EnvironmentObject var recommender: RecommendationEngine
    @State private var query = ""
    @State private var topic: String?
    @State private var results: [Book] = []
    @State private var page = 1
    @State private var hasMore = false
    @State private var loading = false
    @State private var selected: Book?

    static let topics = ["Adventure", "Romance", "Mystery", "Science Fiction", "Fantasy", "Horror", "Poetry",
                         "Philosophy", "History", "Humor", "Children", "Biography", "Psychology", "Detective"]

    private var shelfTitle: String {
        if let topic { return topic }
        if !query.isEmpty { return "Results" }
        return "Featured"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackground(tint: Theme.accent2)
                VStack(alignment: .leading, spacing: 14) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Self.topics, id: \.self) { t in
                                Button {
                                    topic = topic == t ? nil : t
                                    if let topic { recommender.recordSearch(topic) }
                                    Task { await search(reset: true) }
                                } label: { Chip(text: t, selected: topic == t) }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 20)
                    }

                    if !recommender.profile.recentQueries.isEmpty && query.isEmpty && topic == nil {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeader(title: "Recent searches")
                                .padding(.horizontal, 20)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(recommender.profile.recentQueries.prefix(8), id: \.self) { q in
                                        Button { query = q; Task { await search(reset: true) } } label: {
                                            Chip(text: q, symbol: "clock.arrow.circlepath")
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 20)
                            }
                        }
                    }

                    if loading && results.isEmpty {
                        Spacer()
                        ProgressView().tint(.white).frame(maxWidth: .infinity)
                        Spacer()
                    } else if !loading && results.isEmpty && (!query.isEmpty || topic != nil) {
                        Spacer()
                        ContentUnavailableView.search(text: query)
                        Spacer()
                    } else if !results.isEmpty {
                        BookShelf(
                            title: shelfTitle,
                            books: results,
                            fills: true,
                            isLoadingMore: loading,
                            onSelect: { book in
                                recommender.record(.open, book: book)
                                selected = book
                            },
                            onNearEnd: {
                                if hasMore { Task { await search(reset: false) } }
                            }
                        )
                        .frame(maxHeight: .infinity)
                    } else {
                        Spacer()
                    }
                }
                .padding(.top, 8)
            }
            .navigationTitle("Discover")
            .searchable(text: $query, prompt: "Titles, authors, topics…")
            .onSubmit(of: .search) {
                recommender.recordSearch(query)
                Task { await search(reset: true) }
            }
            .task { if results.isEmpty { await search(reset: true) } }
            .sheet(item: $selected) { BookDetailView(book: $0) }
        }
    }

    private func search(reset: Bool) async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        if reset { page = 1 }
        do {
            let r = try await GutendexService.shared.fetch(search: query, topic: topic?.lowercased(), page: page)
            let books = r.books.filter { $0.textURL != nil }
            results = reset ? books : results + books.filter { b in !results.contains { $0.id == b.id } }
            hasMore = r.hasMore
            page += 1
        } catch {
            hasMore = false
        }
    }
}
