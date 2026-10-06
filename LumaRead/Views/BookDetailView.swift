import SwiftUI

struct BookDetailView: View {
    let book: Book
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var recommender: RecommendationEngine
    @Environment(\.dismiss) private var dismiss
    @State private var reading = false
    @State private var reaction: Bool?

    var body: some View {
        ZStack {
            AuroraBackground()
            ScrollView {
                VStack(spacing: 22) {
                    Capsule().fill(.white.opacity(0.3)).frame(width: 40, height: 5).padding(.top, 10)
                    BookCover(book: book, corner: 18)
                        .frame(width: 190)
                        .rotation3DEffect(.degrees(6), axis: (x: 0, y: 1, z: 0))
                        .padding(.top, 8)

                    VStack(spacing: 6) {
                        Text(book.title)
                            .font(.system(.title, design: .serif).weight(.bold))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white)
                        Text(book.authorLine).font(.subheadline).foregroundStyle(Theme.dim)
                    }

                    HStack(spacing: 18) {
                        stat("\(book.downloadCount.formatted(.number.notation(.compactName)))", "readers")
                        stat(book.languages.first?.uppercased() ?? "EN", "language")
                        stat("Free", "public domain")
                    }
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .glass(radius: 18)

                    FlowLayout(spacing: 8) {
                        ForEach(book.displayTags, id: \.self) { Chip(text: $0) }
                    }

                    if let summary = book.summary {
                        Text(summary)
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.85))
                            .lineSpacing(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button {
                        library.ensureSaved(book)
                        recommender.record(.startRead, book: book)
                        reading = true
                    } label: {
                        Label(library.progress[book.id] != nil ? "Continue reading" : "Start reading", systemImage: "book.fill")
                    }
                    .buttonStyle(GradientButtonStyle())

                    HStack(spacing: 12) {
                        actionButton(library.isSaved(book) ? "Saved" : "Save",
                                     library.isSaved(book) ? "bookmark.fill" : "bookmark") {
                            library.toggleSave(book)
                            if library.isSaved(book) { recommender.record(.saved, book: book) }
                        }
                        actionButton("More like this", reaction == true ? "hand.thumbsup.fill" : "hand.thumbsup") {
                            reaction = true; recommender.record(.like, book: book)
                        }
                        actionButton("Not for me", reaction == false ? "hand.thumbsdown.fill" : "hand.thumbsdown") {
                            reaction = false; recommender.record(.dislike, book: book)
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 30)
            }
        }
        .presentationDragIndicator(.hidden)
        .fullScreenCover(isPresented: $reading) { ReaderView(book: book) }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline).foregroundStyle(.white)
            Text(label).font(.caption2).foregroundStyle(Theme.dim)
        }
        .frame(maxWidth: .infinity)
    }

    private func actionButton(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.title3)
                Text(title).font(.caption2.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .glass(radius: 16)
        }
        .buttonStyle(.plain)
    }
}
