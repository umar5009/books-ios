import SwiftUI

struct BookCover: View {
    let book: Book
    var corner: CGFloat = 14
    var showsShadow: Bool = true

    var body: some View {
        ZStack {
            Theme.coverGradient(seed: book.id)
            VStack(alignment: .leading, spacing: 6) {
                Spacer()
                Text(book.title)
                    .font(.system(.headline, design: .serif).weight(.bold))
                    .lineLimit(4)
                    .minimumScaleFactor(0.7)
                Text(book.authorLine).font(.caption2.weight(.medium)).opacity(0.8).lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)

            if let url = book.coverURL {
                AsyncImage(url: url, transaction: Transaction(animation: .easeIn)) { phase in
                    if case .success(let img) = phase {
                        img.resizable().scaledToFill()
                    }
                }
            }
        }
        .aspectRatio(2 / 3, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
        .shadow(color: .black.opacity(showsShadow ? 0.4 : 0), radius: showsShadow ? 10 : 0, y: showsShadow ? 6 : 0)
    }
}

/// A feed card that reports impressions, dwell time and quick skips to the recommender.
struct BookCard: View {
    let book: Book
    var reason: String? = nil
    var showsMeta: Bool = true
    var showsShadow: Bool = true
    @EnvironmentObject var recommender: RecommendationEngine
    @State private var appearedAt: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: showsMeta ? 8 : 0) {
            BookCover(book: book, showsShadow: showsShadow)
            if showsMeta {
                Text(book.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text(book.authorLine).font(.caption).foregroundStyle(Theme.dim).lineLimit(1)
                if let reason {
                    Text(reason)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.accent2)
                        .lineLimit(1)
                }
            }
        }
        .onAppear {
            appearedAt = .now
            recommender.record(.impression, book: book)
        }
        .onDisappear {
            guard let t = appearedAt else { return }
            let dwell = Date().timeIntervalSince(t)
            if dwell > 2.0 { recommender.record(.dwell(dwell), book: book) }
            else if dwell < 0.5 { recommender.record(.skip, book: book) }
        }
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.title3.weight(.bold)).foregroundStyle(.white)
            if let subtitle { Text(subtitle).font(.footnote).foregroundStyle(Theme.dim) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MoodOrb: View {
    var color: Color = Theme.accent
    var level: CGFloat = 0
    var size: CGFloat = 120

    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(AngularGradient(colors: [color, Theme.accent2, color.opacity(0.6), color], center: .center,
                                              angle: .degrees(t * 40 + Double(i) * 120)))
                        .frame(width: size * (0.8 + 0.1 * CGFloat(i)) * (1 + level * 0.35),
                               height: size * (0.8 + 0.1 * CGFloat(i)) * (1 + level * 0.35))
                        .blur(radius: 12 + CGFloat(i) * 6)
                        .opacity(0.65 - Double(i) * 0.15)
                        .offset(x: CGFloat(sin(t * 1.3 + Double(i))) * 6, y: CGFloat(cos(t * 1.1 + Double(i))) * 6)
                }
                Circle()
                    .fill(.white.opacity(0.9))
                    .frame(width: size * 0.18, height: size * 0.18)
                    .blur(radius: 6)
            }
            .frame(width: size * 1.4, height: size * 1.4)
            .animation(.easeOut(duration: 0.12), value: level)
        }
    }
}

/// A library shelf. Books slide sideways; the one in front lifts off the wood.
struct BookShelf: View {
    var title: String
    var subtitle: String? = nil
    let books: [Book]
    var coverWidth: CGFloat = 112
    /// The front book grows to fill the shelf and opens onto a page.
    var fills = false
    var reason: ((Book) -> String?)? = nil
    var progress: ((Book) -> Double?)? = nil
    var isLoadingMore = false
    var onSelect: (Book) -> Void
    var onRead: ((Book) -> Void)? = nil
    var onRemove: ((Book) -> Void)? = nil
    var onNearEnd: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var focused: Int?
    @State private var settled: Int?

    private var coverHeight: CGFloat { coverWidth * 1.5 }
    private var liftDistance: CGFloat { reduceMotion ? 0 : 48 }
    private var liftRoom: CGFloat { liftDistance + 36 }
    private let plankHeight: CGFloat = 22
    private var focusedBook: Book? {
        if let focused, let book = books.first(where: { $0.id == focused }) { return book }
        return books.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: title, subtitle: subtitle)
                .padding(.horizontal, 20)

            GeometryReader { geo in
                let metrics = shelfMetrics(width: geo.size.width, height: geo.size.height)
                ZStack(alignment: .bottom) {
                    shelfBack
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .bottom, spacing: fills ? 22 : 18) {
                            ForEach(books) { book in
                                shelfBook(book, metrics: metrics)
                                    .id(book.id)
                                    .onAppear {
                                        if book.id == books.last?.id { onNearEnd?() }
                                    }
                            }
                        }
                        .scrollTargetLayout()
                        .frame(height: max(0, geo.size.height - plankHeight), alignment: .bottom)
                    }
                    .contentMargins(.horizontal, metrics.inset, for: .scrollContent)
                    .scrollTargetBehavior(.viewAligned)
                    .scrollPosition(id: $focused, anchor: .center)
                    .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                    .scrollClipDisabled(fills)
                    .padding(.bottom, plankHeight)

                    ShelfPlank()
                        .frame(height: plankHeight)
                        .allowsHitTesting(false)

                    if fills, let book = books.first(where: { $0.id == settled }) {
                        OpenBook(book: book, size: CGSize(width: metrics.spread, height: max(metrics.side.height, metrics.hero.height - 8)))
                            .id(book.id)
                            .padding(.bottom, plankHeight + 2)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                            .allowsHitTesting(false)
                            .transition(.scale(scale: 0.55, anchor: .bottom).combined(with: .opacity))
                    }

                    if isLoadingMore {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                            .padding(.trailing, 18)
                            .padding(.bottom, plankHeight + 24)
                            .allowsHitTesting(false)
                    }
                }
            }
            .frame(maxHeight: fills ? .infinity : nil)
            .frame(height: fills ? nil : coverHeight + liftRoom + plankHeight)

            nameplate
                .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: fills ? .infinity : nil, alignment: .top)
        .animation(.spring(response: 0.5, dampingFraction: 0.82), value: settled)
        .onAppear(perform: alignFocus)
        .onChange(of: books.map(\.id)) { _, _ in alignFocus() }
        .task(id: focused) {
            guard fills, let id = focused else { return }
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            settled = id
        }
    }

    private struct ShelfMetrics {
        var side: CGSize
        var hero: CGSize
        var spread: CGFloat
        var inset: CGFloat
    }

    private func shelfMetrics(width: CGFloat, height: CGFloat) -> ShelfMetrics {
        let side = CGSize(width: coverWidth, height: coverWidth * 1.5)
        let room = max(0, height - plankHeight)
        let heroH = fills ? max(side.height, room - 4) : side.height
        let heroW = fills ? min(width * 0.56, heroH * 0.62) : coverWidth
        let spread = fills ? min(width * 0.86, max(heroW * 1.45, width * 0.72)) : heroW
        let inset = max(18, (width - coverWidth) / 2)
        return ShelfMetrics(side: side, hero: CGSize(width: heroW, height: heroH), spread: spread, inset: inset)
    }

    private func alignFocus() {
        if let focused, books.contains(where: { $0.id == focused }) { return }
        let first = books.first?.id
        if focused != first { focused = first }
    }

    private var shelfBack: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.04), Color.black.opacity(0.38)],
                        startPoint: .top, endPoint: .bottom)
                )
                .padding(.horizontal, 28)
                .padding(.bottom, plankHeight)
                .frame(height: coverHeight * 0.78)
                .frame(maxHeight: .infinity, alignment: .bottom)

            HStack {
                ShelfUpright()
                Spacer()
                ShelfUpright()
            }
            .padding(.horizontal, 14)
            .padding(.bottom, plankHeight - 2)
            .frame(height: coverHeight * 0.92)
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .allowsHitTesting(false)
    }

    private func shelfBook(_ book: Book, metrics: ShelfMetrics) -> some View {
        let active = focused == book.id
        let hidden = fills && book.id == settled
        let resting = metrics.side

        return Button { onSelect(book) } label: {
            ZStack(alignment: .bottom) {
                Ellipse()
                    .fill(Color.black.opacity(0.4))
                    .frame(width: resting.width * 0.62, height: 8)
                    .blur(radius: 2)
                    .offset(y: 4)

                closedBook(book, size: resting, highlighted: active && !fills)
                    .offset(y: active && !fills && !reduceMotion ? -liftDistance : 0)
                    .opacity(hidden ? 0 : 1)
            }
            .frame(width: resting.width, height: resting.height, alignment: .bottom)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(book.title), \(book.authorLine)")
        .accessibilityAddTraits(active ? .isSelected : [])
        .shelfRemoveMenu(onRemove.map { action in { action(book) } })
    }

    private func closedBook(_ book: Book, size: CGSize, highlighted: Bool) -> some View {
        BookCard(book: book, showsMeta: false, showsShadow: false)
            .frame(width: size.width, height: size.height)
            .background(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.22, green: 0.13, blue: 0.09),
                                Color(red: 0.48, green: 0.32, blue: 0.20)
                            ],
                            startPoint: .leading, endPoint: .trailing)
                    )
                    .frame(width: 9, height: size.height * 0.94)
                    .offset(x: -4)
            }
            .overlay(alignment: .bottom) {
                if let progress, let value = progress(book), value > 0 {
                    Capsule()
                        .fill(Color.white.opacity(0.22))
                        .frame(height: 3)
                        .overlay(alignment: .leading) {
                            Capsule().fill(Theme.accent2)
                                .scaleEffect(x: max(0.04, value), anchor: .leading)
                        }
                        .clipShape(Capsule())
                        .padding(.horizontal, 8)
                        .padding(.bottom, 8)
                }
            }
            .overlay {
                if reduceMotion && highlighted {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Theme.accent2, lineWidth: 2)
                }
            }
            .scaleEffect(highlighted && !reduceMotion ? 1.08 : 1, anchor: .bottom)
            .shadow(color: .black.opacity(highlighted ? 0.4 : 0.22), radius: highlighted ? 14 : 5, y: highlighted ? 12 : 4)
    }

    private var nameplate: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(focusedBook?.title ?? " ")
                    .font(.system(.title3, design: .serif).weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                if let book = focusedBook {
                    Text(metaLine(for: book))
                        .font(.subheadline)
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                    if book.showcase.isQuote, let detail = book.previewDetail {
                        Text(detail)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.82))
                            .lineLimit(2)
                    } else if !book.displayTags.isEmpty {
                        Text(book.displayTags.joined(separator: " · "))
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.82))
                            .lineLimit(1)
                    }
                    if let line = reason?(book) {
                        Text(line)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.accent2)
                            .lineLimit(1)
                    }
                    if let value = progress?(book) {
                        ProgressView(value: value)
                            .tint(Theme.accent2)
                            .frame(maxWidth: 160)
                        Text("\(Int(value * 100))% read")
                            .font(.caption2)
                            .foregroundStyle(Theme.dim)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let onRead, let book = focusedBook {
                Button { onRead(book) } label: {
                    Image(systemName: "play.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.black)
                        .padding(12)
                        .background(Theme.brandGradient, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Read \(book.title)")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glass(radius: 18)
        .animation(.easeInOut(duration: 0.2), value: focused)
    }

    private func metaLine(for book: Book) -> String {
        var parts = [book.authorLine]
        if let year = book.yearLine { parts.append(year) }
        if let language = book.languages.first?.uppercased() { parts.append(language) }
        return parts.joined(separator: " · ")
    }
}

/// The book in front. It grows, the cover swings open, and a page turns onto a line from the book.
private struct OpenBook: View {
    let book: Book
    var size: CGSize

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var opened = false
    @State private var turned = false
    @State private var hideSheet = false

    private var line: BookLine { book.showcase }
    private let paper = Color(red: 0.97, green: 0.93, blue: 0.84)
    private let ink = Color(red: 0.24, green: 0.15, blue: 0.10)

    var body: some View {
        let pageW = size.width * 0.58
        let pageH = size.height
        ZStack {
            HStack(spacing: 0) {
                insideCover
                    .frame(width: size.width - pageW, height: pageH)
                quotePage
                    .frame(width: pageW, height: pageH)
            }
            .opacity(opened ? 1 : 0)
            .shadow(color: .black.opacity(opened ? 0.35 : 0), radius: 16, y: 12)

            pageSheet
                .frame(width: pageW, height: pageH)
                .rotation3DEffect(
                    .degrees(turned ? -168 : 0),
                    axis: (x: 0, y: 1, z: 0),
                    anchor: .leading,
                    perspective: 0.4)
                .offset(x: size.width * 0.18)
                .opacity(opened && !hideSheet ? 1 : 0)
                .allowsHitTesting(false)

            BookCover(book: book, showsShadow: false)
                .frame(width: pageW, height: pageH)
                .background(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color(red: 0.28, green: 0.16, blue: 0.11))
                        .frame(width: 8)
                        .offset(x: -3)
                }
                .rotation3DEffect(
                    .degrees(opened ? -150 : 0),
                    axis: (x: 0, y: 1, z: 0),
                    anchor: .leading,
                    perspective: 0.48)
                .offset(x: opened ? -size.width * 0.08 : 0)
                .opacity(opened ? 0 : 1)
                .shadow(color: .black.opacity(0.35), radius: 12, y: 10)
        }
        .frame(width: size.width, height: size.height)
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.7), trigger: opened)
        .task(id: book.id) { await play() }
    }

    private var quotePage: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(
                LinearGradient(colors: [paper, Color(red: 0.93, green: 0.86, blue: 0.73)],
                               startPoint: .top, endPoint: .bottom)
            )
            .overlay {
                VStack(alignment: .leading, spacing: 8) {
                    Text(line.isQuote ? "“" : "")
                        .font(.system(size: 34, weight: .bold, design: .serif))
                        .foregroundStyle(ink.opacity(0.35))
                        .frame(height: line.isQuote ? 28 : 0)
                    Text(line.text)
                        .font(.system(.callout, design: .serif).italic())
                        .foregroundStyle(ink)
                        .lineLimit(6)
                        .minimumScaleFactor(0.72)
                    Spacer(minLength: 0)
                    Text(line.isQuote ? "— \(book.title)" : book.authorLine)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(ink.opacity(0.55))
                        .lineLimit(1)
                }
                .padding(14)
                .opacity(turned || reduceMotion ? 1 : 0)
            }
            .overlay(alignment: .leading) {
                Rectangle().fill(Color.black.opacity(0.08)).frame(width: 8)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var insideCover: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.42, green: 0.14, blue: 0.16),
                        Color(red: 0.24, green: 0.08, blue: 0.10)
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .overlay {
                VStack(spacing: 8) {
                    Text(book.title)
                        .font(.system(.caption, design: .serif).weight(.semibold))
                        .multilineTextAlignment(.center)
                        .lineLimit(4)
                    Text(book.authorLine)
                        .font(.caption2)
                        .opacity(0.75)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(Color(red: 0.93, green: 0.84, blue: 0.62))
                .padding(12)
            }
            .overlay(alignment: .trailing) {
                Rectangle().fill(Color.black.opacity(0.28)).frame(width: 12)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var pageSheet: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(paper)
            .overlay(alignment: .leading) {
                Rectangle().fill(Color.black.opacity(0.12)).frame(width: 8)
            }
            .shadow(color: .black.opacity(0.2), radius: 6, x: 4, y: 2)
    }

    private func play() async {
        opened = false
        turned = false
        hideSheet = false
        guard !reduceMotion else {
            opened = true
            turned = true
            hideSheet = true
            return
        }
        try? await Task.sleep(for: .milliseconds(180))
        guard !Task.isCancelled else { return }
        withAnimation(.spring(response: 0.58, dampingFraction: 0.78)) { opened = true }
        try? await Task.sleep(for: .milliseconds(240))
        guard !Task.isCancelled else { return }
        withAnimation(.easeInOut(duration: 0.55)) { turned = true }
        try? await Task.sleep(for: .milliseconds(520))
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.18)) { hideSheet = true }
    }
}

private struct ShelfPlank: View {
    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [
                    Color(red: 0.80, green: 0.64, blue: 0.44),
                    Color(red: 0.52, green: 0.34, blue: 0.22)
                ],
                startPoint: .top, endPoint: .bottom)
                .frame(height: 8)
                .overlay(alignment: .top) {
                    Rectangle().fill(Color.white.opacity(0.38)).frame(height: 1)
                }
            LinearGradient(
                colors: [
                    Color(red: 0.34, green: 0.20, blue: 0.13),
                    Color(red: 0.15, green: 0.08, blue: 0.06)
                ],
                startPoint: .top, endPoint: .bottom)
                .frame(height: 14)
        }
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        .shadow(color: .black.opacity(0.5), radius: 8, y: 6)
        .padding(.horizontal, 8)
    }
}

private struct ShelfUpright: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.42, green: 0.28, blue: 0.18),
                        Color(red: 0.18, green: 0.11, blue: 0.08)
                    ],
                    startPoint: .top, endPoint: .bottom)
            )
            .frame(width: 11)
            .overlay(alignment: .leading) {
                Rectangle().fill(Color.white.opacity(0.14)).frame(width: 1)
            }
    }
}

private extension View {
    @ViewBuilder func shelfRemoveMenu(_ action: (() -> Void)?) -> some View {
        if let action {
            self.contextMenu {
                Button("Remove from shelf", systemImage: "trash", role: .destructive, action: action)
            }
        } else {
            self
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > width { x = 0; y += rowH + spacing; rowH = 0 }
            x += sz.width + spacing; rowH = max(rowH, sz.height)
        }
        return CGSize(width: width == .infinity ? x : width, height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing; rowH = max(rowH, sz.height)
        }
    }
}
