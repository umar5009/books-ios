import Foundation

/// The user's shelf: saved books + reading progress, persisted as JSON.
@MainActor
final class LibraryStore: ObservableObject {
    static let shared = LibraryStore()

    @Published private(set) var saved: [Book] = []
    @Published private(set) var progress: [Int: ReadingProgress] = [:]

    private struct Snapshot: Codable { var saved: [Book]; var progress: [Int: ReadingProgress] }

    private let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("library.json")
    }()

    init() {
        if let data = try? Data(contentsOf: url), let s = try? JSONDecoder().decode(Snapshot.self, from: data) {
            saved = s.saved
            progress = s.progress
        }
    }

    var continueReading: [Book] {
        saved.filter { (progress[$0.id]?.fraction ?? 0) > 0 && !(progress[$0.id]?.finished ?? false) }
            .sorted { (progress[$0.id]?.lastOpened ?? .distantPast) > (progress[$1.id]?.lastOpened ?? .distantPast) }
    }

    func isSaved(_ book: Book) -> Bool { saved.contains { $0.id == book.id } }

    func toggleSave(_ book: Book) {
        if let i = saved.firstIndex(where: { $0.id == book.id }) { saved.remove(at: i) } else { saved.insert(book, at: 0) }
        persist()
    }

    func ensureSaved(_ book: Book) {
        if !isSaved(book) { saved.insert(book, at: 0); persist() }
    }

    func updateProgress(_ book: Book, offset: Int, fraction: Double, addMinutes: Double = 0) {
        var p = progress[book.id] ?? ReadingProgress()
        p.charOffset = offset
        p.fraction = fraction
        p.minutesRead += addMinutes
        p.lastOpened = .now
        if fraction > 0.985 { p.finished = true }
        progress[book.id] = p
        persist()
    }

    private func persist() {
        let snap = Snapshot(saved: saved, progress: progress)
        if let data = try? JSONEncoder().encode(snap) { try? data.write(to: url, options: .atomic) }
    }
}
