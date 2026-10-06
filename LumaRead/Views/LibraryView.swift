import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var library: LibraryStore
    @State private var reading: Book?
    @State private var selected: Book?

    private var totalMinutes: Int { Int(library.progress.values.reduce(0) { $0 + $1.minutesRead }) }
    private var finished: Int { library.progress.values.filter(\.finished).count }

    var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackground()
                if library.saved.isEmpty {
                    ContentUnavailableView("Your shelf is empty",
                                           systemImage: "books.vertical",
                                           description: Text("Books you save or start reading appear here."))
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            statTile("\(library.saved.count)", "books")
                            statTile("\(totalMinutes)", "minutes read")
                            statTile("\(finished)", "finished")
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                        BookShelf(
                            title: "On your shelf",
                            books: library.saved,
                            fills: true,
                            progress: { library.progress[$0.id]?.fraction },
                            onSelect: { selected = $0 },
                            onRead: { reading = $0 },
                            onRemove: { library.toggleSave($0) }
                        )
                        .frame(maxHeight: .infinity)
                    }
                }
            }
            .navigationTitle("Library")
            .fullScreenCover(item: $reading) { ReaderView(book: $0) }
            .sheet(item: $selected) { BookDetailView(book: $0) }
        }
    }

    private func statTile(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title2.weight(.bold)).foregroundStyle(Theme.brandGradient)
            Text(label).font(.caption2).foregroundStyle(Theme.dim)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .glass(radius: 16)
    }
}
