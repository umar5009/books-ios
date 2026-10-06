import SwiftUI

struct HomeView: View {
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var recommender: RecommendationEngine
    @EnvironmentObject var moodEngine: MoodEngine
    @EnvironmentObject var settings: AppSettings
    @StateObject private var feed = FeedModel()
    @State private var showMood = false
    @State private var selected: Book?
    @State private var reading: Book?

    var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackground(tint: moodEngine.mood?.color ?? Theme.accent)
                GeometryReader { geo in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            header
                            moodCard
                            if !library.continueReading.isEmpty {
                                BookShelf(
                                    title: "Continue reading",
                                    books: library.continueReading,
                                    coverWidth: 96,
                                    progress: { library.progress[$0.id]?.fraction },
                                    onSelect: { reading = $0 }
                                )
                            }
                            if let mood = moodEngine.mood, !feed.moodPicks.isEmpty {
                                BookShelf(
                                    title: "For a \(mood.title.lowercased()) mood",
                                    subtitle: settings.moodLift && mood.isLow ? "Gently lifting, not mirroring" : nil,
                                    books: feed.moodPicks.map(\.book),
                                    coverWidth: 96,
                                    onSelect: open
                                )
                            }
                            if feed.items.isEmpty && feed.isLoading {
                                ProgressView().tint(.white).frame(maxWidth: .infinity).padding(.top, 40)
                            } else if !feed.items.isEmpty {
                                BookShelf(
                                    title: "For You",
                                    subtitle: "Learns from every scroll, tap and minute you read",
                                    books: feed.items.map(\.book),
                                    fills: true,
                                    reason: { book in feed.items.first { $0.id == book.id }?.reason },
                                    isLoadingMore: feed.isLoading,
                                    onSelect: open,
                                    onNearEnd: {
                                        Task { await feed.loadMore(mood: moodEngine.mood, lift: settings.moodLift) }
                                    }
                                )
                                .frame(maxHeight: .infinity)
                            }
                            if let err = feed.error {
                                Text(err).font(.footnote).foregroundStyle(Theme.dim).padding(.horizontal, 20)
                            }
                        }
                        .frame(minHeight: geo.size.height, alignment: .top)
                        .padding(.top, 8)
                        .padding(.bottom, 8)
                    }
                    .scrollBounceBehavior(.basedOnSize, axes: .vertical)
                    .scrollIndicators(.hidden)
                    .refreshable { await feed.reload(mood: moodEngine.mood, lift: settings.moodLift) }
                }
            }
            .task { if feed.items.isEmpty { await feed.reload(mood: moodEngine.mood, lift: settings.moodLift) } }
            .onChange(of: moodEngine.mood) { _, mood in
                guard let mood else { return }
                Task {
                    await feed.loadMoodPicks(mood, lift: settings.moodLift)
                    await feed.reload(mood: mood, lift: settings.moodLift)
                }
            }
            .sheet(isPresented: $showMood) { MoodCheckInView() }
            .sheet(item: $selected) { BookDetailView(book: $0) }
            .fullScreenCover(item: $reading) { ReaderView(book: $0) }
        }
    }

    private func open(_ book: Book) {
        recommender.record(.open, book: book)
        feed.learn(from: book)
        selected = book
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: .now)
        return h < 12 ? "Good morning" : h < 18 ? "Good afternoon" : "Good evening"
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(greeting).font(.subheadline).foregroundStyle(Theme.dim)
                Text("What shall we read?")
                    .font(.system(.largeTitle, design: .serif).weight(.bold))
                    .foregroundStyle(.white)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
    }

    private var moodCard: some View {
        Button { showMood = true } label: {
            HStack(spacing: 16) {
                MoodOrb(color: moodEngine.mood?.color ?? Theme.accent, size: 54)
                    .frame(width: 76, height: 76)
                VStack(alignment: .leading, spacing: 4) {
                    if let mood = moodEngine.mood {
                        Label("Feeling \(mood.title.lowercased())", systemImage: mood.symbol)
                            .font(.headline).foregroundStyle(.white)
                        Text(mood.blurb).font(.footnote).foregroundStyle(Theme.dim).lineLimit(2)
                    } else {
                        Text("How are you feeling?").font(.headline).foregroundStyle(.white)
                        Text("Talk to me for 5 seconds — I'll find the right book for your mood.")
                            .font(.footnote).foregroundStyle(Theme.dim).lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "mic.fill")
                    .foregroundStyle(.black)
                    .padding(10)
                    .background(Theme.brandGradient, in: Circle())
            }
            .padding(14)
            .glass()
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
    }
}
