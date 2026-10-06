import Foundation

/// Free, legal catalogue of 75k+ public-domain books (Project Gutenberg via the Gutendex API).
actor GutendexService {
    static let shared = GutendexService()

    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.requestCachePolicy = .returnCacheDataElseLoad
        c.urlCache = URLCache(memoryCapacity: 20_000_000, diskCapacity: 200_000_000)
        return URLSession(configuration: c)
    }()

    private struct PageDTO: Decodable {
        let count: Int
        let next: String?
        let results: [BookDTO]
    }
    private struct PersonDTO: Decodable {
        let name: String
        let birth_year: Int?
        let death_year: Int?
    }
    private struct BookDTO: Decodable {
        let id: Int
        let title: String
        let authors: [PersonDTO]
        let subjects: [String]
        let bookshelves: [String]
        let languages: [String]
        let formats: [String: String]
        let download_count: Int
        let summaries: [String]?
    }

    struct Result { let books: [Book]; let hasMore: Bool }

    func fetch(search: String? = nil, topic: String? = nil, page: Int = 1) async throws -> Result {
        var comps = URLComponents(string: "https://gutendex.com/books/")!
        var items = [URLQueryItem(name: "languages", value: "en"),
                     URLQueryItem(name: "mime_type", value: "text/plain")]
        if let search, !search.isEmpty { items.append(URLQueryItem(name: "search", value: search)) }
        if let topic, !topic.isEmpty { items.append(URLQueryItem(name: "topic", value: topic)) }
        if page > 1 { items.append(URLQueryItem(name: "page", value: String(page))) }
        comps.queryItems = items

        let (data, response) = try await session.data(from: comps.url!)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let dto = try JSONDecoder().decode(PageDTO.self, from: data)
        return Result(books: dto.results.map(Self.map), hasMore: dto.next != nil)
    }

    private static func map(_ d: BookDTO) -> Book {
        let textKey = d.formats.keys
            .filter { $0.hasPrefix("text/plain") }
            .sorted { a, b in a.contains("utf-8") && !b.contains("utf-8") }
            .first
        let textURL = textKey.flatMap { d.formats[$0] }
            .flatMap { $0.hasSuffix(".zip") ? nil : URL(string: $0.replacingOccurrences(of: "http://", with: "https://")) }
        let cover = d.formats["image/jpeg"].flatMap { URL(string: $0.replacingOccurrences(of: "http://", with: "https://")) }
            ?? URL(string: "https://www.gutenberg.org/cache/epub/\(d.id)/pg\(d.id).cover.medium.jpg")
        return Book(id: d.id, title: d.title, authors: d.authors.map(\.name), subjects: d.subjects,
                    bookshelves: d.bookshelves, languages: d.languages, coverURL: cover, textURL: textURL,
                    downloadCount: d.download_count, summary: d.summaries?.first,
                    authorBirthYear: d.authors.first?.birth_year, authorDeathYear: d.authors.first?.death_year)
    }

    // MARK: - Full text

    private var cacheDir: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("books")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Downloads, cleans and caches the book's plain text. Returns paragraphs.
    func paragraphs(for book: Book) async throws -> [String] {
        let file = cacheDir.appendingPathComponent("\(book.id).txt")
        let raw: String
        if let cached = try? String(contentsOf: file, encoding: .utf8) {
            raw = cached
        } else {
            guard let url = book.textURL else { throw URLError(.fileDoesNotExist) }
            let (data, _) = try await session.data(from: url)
            raw = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
            try? raw.write(to: file, atomically: true, encoding: .utf8)
        }
        return Self.clean(raw)
    }

    /// Strips the Gutenberg licence header/footer and re-flows hard-wrapped lines into paragraphs.
    static func clean(_ raw: String) -> [String] {
        var body = raw.replacingOccurrences(of: "\r\n", with: "\n")
        if let start = body.range(of: "*** START OF") {
            if let eol = body[start.upperBound...].firstIndex(of: "\n") { body = String(body[body.index(after: eol)...]) }
        }
        if let end = body.range(of: "*** END OF") { body = String(body[..<end.lowerBound]) }

        return body
            .components(separatedBy: "\n\n")
            .map { para in
                para.split(separator: "\n")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .joined(separator: " ")
                    .replacingOccurrences(of: "_", with: "")
                    .replacingOccurrences(of: "  ", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
    }
}
