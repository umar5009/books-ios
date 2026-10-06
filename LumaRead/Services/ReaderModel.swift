import SwiftUI
import UIKit

/// Drives a reading session: pagination, the eye-driven reading cursor (current line + word),
/// automatic page turns, air-zoom font changes and progress tracking.
@MainActor
final class ReaderModel: ObservableObject {
    typealias Line = Paginator.Line

    let book: Book
    @Published private(set) var lines: [Line] = []
    @Published private(set) var pageIndex = 0
    @Published private(set) var linesPerPage = 18
    @Published private(set) var isLoading = true
    @Published private(set) var isPaginating = false
    @Published var errorMessage: String?
    @Published private(set) var activeLine: Int?          // index within page
    @Published private(set) var activeWord: Int?
    @Published private(set) var turnDirection: Edge = .trailing
    @Published private(set) var endOfPageArmed = false     // shows the "turning…" indicator
    @Published var fontSize: CGFloat

    private var paragraphs: [String] = []
    private var size: CGSize = .zero
    private var paginationTask: Task<Void, Never>?
    private var pendingAnchor: Int?
    private let sessionStart = Date()

    // Gaze cursor state
    private var candidateLine: Int?
    private var candidateSince: TimeInterval = 0
    private var endArmedAt: TimeInterval?
    private var lastTurn: TimeInterval = 0
    private var wordCache: [Int: [CGFloat]] = [:]   // line index in page → word end x positions

    init(book: Book, fontSize: CGFloat) {
        self.book = book
        self.fontSize = fontSize
    }

    // MARK: Derived

    var uiFont: UIFont { UIFont(name: "Georgia", size: fontSize) ?? .systemFont(ofSize: fontSize) }
    var lineHeight: CGFloat { (uiFont.lineHeight * 1.5).rounded() }
    var totalPages: Int { max(1, Int(ceil(Double(lines.count) / Double(max(1, linesPerPage))))) }
    var pageLines: [Line] {
        guard !lines.isEmpty else { return [] }
        let s = min(pageIndex * linesPerPage, lines.count - 1)
        return Array(lines[s..<min(s + linesPerPage, lines.count)])
    }
    var fraction: Double { totalPages <= 1 ? 0 : Double(pageIndex) / Double(totalPages - 1) }
    var currentOffset: Int { pageLines.first?.offset ?? 0 }
    var isReady: Bool { !lines.isEmpty && pendingAnchor == nil }

    // MARK: Loading & layout

    func load(resumeAt offset: Int) async {
        isLoading = true
        do {
            paragraphs = try await GutendexService.shared.paragraphs(for: book)
            pendingAnchor = offset
            if size != .zero { repaginate() }
        } catch {
            errorMessage = "Couldn't download this book. Check your connection and try again."
        }
        isLoading = false
    }

    func setSize(_ newSize: CGSize) {
        guard abs(newSize.width - size.width) > 1 || abs(newSize.height - size.height) > 1 else { return }
        let anchor = lines.isEmpty ? pendingAnchor : currentOffset
        size = newSize
        pendingAnchor = anchor
        if !paragraphs.isEmpty { repaginate() }
    }

    func zoom(_ direction: AirZoomDetector.Direction) {
        setFont(fontSize + (direction == .zoomIn ? 2 : -2))
    }

    func setFont(_ newSize: CGFloat) {
        let clamped = min(36, max(14, newSize))
        guard clamped != fontSize else { return }
        pendingAnchor = currentOffset
        fontSize = clamped
        if !paragraphs.isEmpty { repaginate() }
    }

    private func repaginate() {
        paginationTask?.cancel()
        let width = max(100, size.width - 4)
        linesPerPage = max(4, Int(size.height / lineHeight))
        let font = uiFont
        let batches = Paginator.batches(paragraphs)
        lines = []
        wordCache = [:]
        isPaginating = true

        paginationTask = Task { [weak self] in
            var offset = 0
            for batch in batches {
                if Task.isCancelled { return }
                let start = offset
                let result = await Task.detached(priority: .userInitiated) {
                    Paginator.layout(paragraphs: batch, startOffset: start, width: width, font: font)
                }.value
                offset = result.end
                guard let self, !Task.isCancelled else { return }
                self.lines.append(contentsOf: result.lines)
                self.resolveAnchorIfPossible()
            }
            self?.isPaginating = false
            self?.resolveAnchorIfPossible(force: true)
        }
    }

    private func resolveAnchorIfPossible(force: Bool = false) {
        guard let anchor = pendingAnchor else { return }
        if let idx = lines.firstIndex(where: { $0.offset >= anchor }) {
            pageIndex = idx / linesPerPage
            pendingAnchor = nil
            resetCursor()
        } else if force {
            pageIndex = max(0, totalPages - 1)
            pendingAnchor = nil
        }
    }

    // MARK: Paging

    func nextPage() {
        guard pageIndex < totalPages - 1 else { return }
        turnDirection = .trailing
        withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) { pageIndex += 1 }
        resetCursor()
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    func previousPage() {
        guard pageIndex > 0 else { return }
        turnDirection = .leading
        withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) { pageIndex -= 1 }
        resetCursor()
    }

    func jump(toFraction f: Double) {
        pageIndex = Int((Double(totalPages - 1) * f).rounded())
        resetCursor()
    }

    private func resetCursor() {
        activeLine = nil; activeWord = nil; candidateLine = nil
        endArmedAt = nil; endOfPageArmed = false
        wordCache = [:]
        lastTurn = Date().timeIntervalSinceReferenceDate
    }

    // MARK: Eye-driven reading cursor

    /// `point` is the smoothed gaze in screen coords; `frame` is the text area in screen coords.
    func updateGaze(_ point: CGPoint?, in frame: CGRect, autoTurn: Bool) {
        let now = Date().timeIntervalSinceReferenceDate
        guard let point, frame.insetBy(dx: -50, dy: -70).contains(point) else {
            endArmedAt = nil; endOfPageArmed = false
            return  // looking away: freeze cursor
        }
        let page = pageLines
        guard !page.isEmpty else { return }

        // 1) Which line? Nearest non-blank row under the gaze, with hysteresis.
        let localY = point.y - frame.minY
        var row = Int(localY / lineHeight)
        row = min(max(0, row), page.count - 1)
        row = nearestTextLine(row, in: page)

        if row != activeLine {
            if candidateLine != row { candidateLine = row; candidateSince = now }
            let isNaturalNext = activeLine.map { row == nextTextLine(after: $0, in: page) } ?? true
            let returnSweep = (point.x - frame.minX) < frame.width * 0.4
            // Advancing to the next line after a return-sweep is accepted fast; other jumps need a short dwell.
            if (isNaturalNext && returnSweep && now - candidateSince > 0.08) || now - candidateSince > 0.30 {
                activeLine = row
                activeWord = 0
            }
        } else {
            candidateLine = nil
        }

        // 2) Which word? Horizontal position within the line.
        guard let line = activeLine else { return }
        let localX = point.x - frame.minX
        let ends = wordEnds(for: line, text: page[line].text)
        if !ends.isEmpty {
            let w = ends.firstIndex(where: { localX <= $0 }) ?? ends.count - 1
            // Readers rarely jump backwards inside a line; damp regressions.
            if let cur = activeWord, w < cur - 1 || w > cur { activeWord = w } else if activeWord == nil { activeWord = w }
        }

        // 3) Auto page turn: reached the end of the last text line → arm, then turn after a short dwell
        //    or immediately when the eyes sweep back to the top of the page.
        guard autoTurn, now - lastTurn > 1.2 else { return }
        let lastText = lastTextLine(in: page)
        let atEnd = line == lastText && localX > frame.width * 0.6
        if atEnd {
            if endArmedAt == nil { endArmedAt = now; endOfPageArmed = true }
            if now - (endArmedAt ?? now) > 0.9 { nextPage() }
        } else if let armed = endArmedAt {
            if localY < frame.height * 0.25 && now - armed < 2.5 { nextPage() }   // return sweep to top
            else if now - armed > 2.5 { endArmedAt = nil; endOfPageArmed = false }
        }
    }

    private func wordEnds(for row: Int, text: String) -> [CGFloat] {
        if let c = wordCache[row] { return c }
        let font = uiFont
        var ends: [CGFloat] = []
        var prefix = ""
        for (i, word) in text.split(separator: " ", omittingEmptySubsequences: false).enumerated() {
            prefix += (i == 0 ? "" : " ") + word
            ends.append((prefix as NSString).size(withAttributes: [.font: font]).width)
        }
        wordCache[row] = ends
        return ends
    }

    private func nearestTextLine(_ row: Int, in page: [Line]) -> Int {
        if !page[row].isBreak { return row }
        for d in 1..<page.count {
            if row + d < page.count, !page[row + d].isBreak { return row + d }
            if row - d >= 0, !page[row - d].isBreak { return row - d }
        }
        return row
    }

    private func nextTextLine(after row: Int, in page: [Line]) -> Int? {
        var r = row + 1
        while r < page.count { if !page[r].isBreak { return r }; r += 1 }
        return nil
    }

    private func lastTextLine(in page: [Line]) -> Int {
        page.lastIndex(where: { !$0.isBreak }) ?? page.count - 1
    }

    // MARK: Session end

    func close(library: LibraryStore, recommender: RecommendationEngine) {
        paginationTask?.cancel()
        let minutes = Date().timeIntervalSince(sessionStart) / 60
        guard !lines.isEmpty else { return }
        library.updateProgress(book, offset: currentOffset, fraction: fraction, addMinutes: minutes)
        if minutes > 0.5 { recommender.record(.readMinutes(minutes), book: book) }
        if fraction > 0.985 { recommender.record(.finished, book: book) }
    }
}
