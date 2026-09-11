import Foundation

/// Client for the public MPC Autofill backend behind mpcfill.com (source: github.com/chilli-axe/mpc-autofill).
/// No login needed: search goes to mpcfill.com, images come straight from Google.
enum MPCFill {
    static let base = URL(string: "https://mpcfill.com/")!
    /// Cloudflare in front of mpcfill.com rejects some default user agents.
    static let userAgent = "Mozilla/5.0 (Macintosh) MTGSheetOptimizer"
    static let maxQueriesPerSearch = 300
    static let maxCardsPerRequest = 1000

    enum CardType: String { case card = "CARD", token = "TOKEN", cardback = "CARDBACK" }

    struct Query: Hashable {
        var query: String
        var cardType: CardType
    }

    struct Card: Codable, Identifiable, Hashable {
        let identifier: String
        let name: String
        let sourceName: String
        let sourceType: String?
        let dpi: Int
        let size: Int
        let `extension`: String
        let smallThumbnailUrl: String
        let downloadLink: String?
        var id: String { identifier }
    }

    // MARK: - API

    /// URLSession can reuse a keep-alive connection the server already closed ("network connection was lost"): retry once.
    private static func retrying<T>(_ operation: () async throws -> T) async throws -> T {
        do { return try await operation() }
        catch let error as URLError where error.code == .networkConnectionLost { return try await operation() }
    }

    private static func send(_ path: String, json: Any? = nil) async throws -> Data {
        var request = URLRequest(url: URL(string: path, relativeTo: base)!)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if let json {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
        }
        let (data, response) = try await retrying { try await URLSession.shared.data(for: request) }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw RenderError(tr("MPCFill answered %d to %@", status, path)) }
        return data
    }

    private struct SourcesResponse: Decodable {
        struct Source: Decodable { let pk: Int }
        let results: [String: Source]
    }

    /// Every source, enabled, in the order mpcfill.com searches them by default (ascending primary key).
    static func sourceIDs() async throws -> [Int] {
        let data = try await send("2/sources/")
        return try JSONDecoder().decode(SourcesResponse.self, from: data).results.values.map(\.pk).sorted()
    }

    /// mpcfill.com's default search settings.
    private static func searchSettings(_ sources: [Int]) -> [String: Any] {
        [
            "searchTypeSettings": ["fuzzySearch": false, "filterCardbacks": false],
            "sourceSettings": ["sources": sources.map { [$0, true] as [Any] }],
            "filterSettings": [
                "minimumDPI": 0, "maximumDPI": 1500, "maximumSize": 30,
                "languages": [String](), "includesTags": [String](), "excludesTags": ["NSFW"],
            ],
        ]
    }

    /// Identifiers of every variant of each query, best first.
    static func search(_ queries: [Query], sources: [Int]) async throws -> [Query: [String]] {
        let unique = Array(Set(queries))
        var out: [Query: [String]] = [:]
        for start in stride(from: 0, to: unique.count, by: maxQueriesPerSearch) {
            let chunk = unique[start..<min(start + maxQueriesPerSearch, unique.count)]
            let body: [String: Any] = [
                "queries": chunk.map { ["query": $0.query, "cardType": $0.cardType.rawValue] },
                "searchSettings": searchSettings(sources),
            ]
            // v2 endpoint: the one live on mpcfill.com, kept upstream for third-party clients.
            let data = try await send("2/editorSearch/", json: body)
            let results = try JSONDecoder().decode([String: [String: [String: [String]]]].self, from: data)["results"] ?? [:]
            for q in chunk { out[q] = results[q.query]?[q.cardType.rawValue] ?? [] }
        }
        return out
    }

    private struct CardsResponse: Decodable { let results: [String: Card] }

    static func cards(_ ids: [String]) async throws -> [String: Card] {
        var out: [String: Card] = [:]
        for start in stride(from: 0, to: ids.count, by: maxCardsPerRequest) {
            let data = try await send("2/cards/", json: ["cardIdentifiers": Array(ids[start..<min(start + maxCardsPerRequest, ids.count)])])
            out.merge(try JSONDecoder().decode(CardsResponse.self, from: data).results) { a, _ in a }
        }
        return out
    }

    private struct CardbacksResponse: Decodable { let cardbacks: [String] }

    static func cardbacks(sources: [Int]) async throws -> [String] {
        let data = try await send("2/cardbacks/", json: ["searchSettings": searchSettings(sources)])
        return try JSONDecoder().decode(CardbacksResponse.self, from: data).cardbacks
    }

    private struct DFCResponse: Decodable { let dfcPairs: [String: String] }

    /// Front face → back face of double-faced cards, both normalised like queries.
    static func dfcPairs() async throws -> [String: String] {
        let data = try await send("2/DFCPairs/")
        let pairs = try JSONDecoder().decode(DFCResponse.self, from: data).dfcPairs
        return Dictionary(pairs.map { (normalise($0.key), normalise($0.value)) }, uniquingKeysWith: { a, _ in a })
    }

    // MARK: - Images

    /// Output cards are 1122 px tall: fetch twice that so the downscale stays sharp without pulling ~9 MB originals.
    static func imageURL(_ card: Card) -> URL? {
        if card.sourceType == nil || card.sourceType == "Google Drive" {
            return URL(string: "https://lh4.googleusercontent.com/d/\(card.identifier)=h2244")
        }
        return card.downloadLink.flatMap(URL.init(string:))
    }

    /// Saves the card in `dir` as "Name (identifier).ext", like mpcfill.com exports; reuses earlier downloads.
    static func download(_ card: Card, to dir: URL) async throws -> URL {
        let safeName = card.name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let file = dir.appendingPathComponent("\(safeName) (\(card.identifier)).\(card.extension)")
        if FileManager.default.fileExists(atPath: file.path) { return file }
        guard let url = imageURL(card) else { throw RenderError(tr("No download link for %@", card.name)) }
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (tmp, response) = try await retrying { try await URLSession.shared.download(for: request) }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw RenderError(tr("Download failed: %@", card.name)) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: tmp, to: file)
        return file
    }

    // MARK: - Decklist

    /// Lowercase, drop punctuation except hyphens, collapse whitespace: what mpcfill.com searches for.
    static func normalise(_ s: String) -> String {
        let punctuation = "~`!@#$%^&*(){}[];:\"'’<,.>?/\\|_+="
        return s.lowercased().filter { !punctuation.contains($0) }
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    struct Entry {
        var quantity: Int
        var name: String        // as written, for display
        var front: Query
        var back: Query?
    }

    /// Parses a Moxfield / mpcfill.com list: "2 Opt", "2x Opt (XLN) 65 *F*", "t:Treasure", "Front // Back".
    /// Section headers ("SIDEBOARD:") and comments are skipped. Double-faced cards get their back from `dfcPairs`.
    static func parseDecklist(_ text: String, dfcPairs: [String: String]) -> [Entry] {
        text.split(whereSeparator: \.isNewline).compactMap { raw -> Entry? in
            var line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasSuffix(":") || line.hasPrefix("#") || line.hasPrefix("//") { return nil }

            var quantity = 1
            let parts = line.split(separator: " ", maxSplits: 1)
            if parts.count == 2 {
                let token = parts[0].hasSuffix("x") || parts[0].hasSuffix("X") ? parts[0].dropLast() : parts[0][...]
                if let n = Int(token) { quantity = n; line = String(parts[1]) }
            }
            guard quantity > 0 else { return nil }
            line = line.replacingOccurrences(of: #"\*[A-Z]+\*"#, with: "", options: .regularExpression)

            let faces = line.components(separatedBy: "//").compactMap(parseFace)
            guard let front = faces.first else { return nil }
            let back = faces.count > 1
                ? faces[1].query
                : dfcPairs[front.query.query].map { Query(query: $0, cardType: front.query.cardType) }
            return Entry(quantity: quantity, name: front.name, front: front.query, back: back)
        }
    }

    private static func parseFace(_ raw: String) -> (name: String, query: Query)? {
        var s = raw.trimmingCharacters(in: .whitespaces)
        var type = CardType.card
        if s.lowercased().hasPrefix("t:") { type = .token; s.removeFirst(2) }
        else if s.lowercased().hasPrefix("b:") { type = .cardback; s.removeFirst(2) }
        // Printing info "(SET) 123" and mpcfill's "@identifier" can't be searched for: keep the name only.
        if let cut = s.firstIndex(where: { "([@".contains($0) }) { s = String(s[..<cut]) }
        s = s.trimmingCharacters(in: .whitespaces)
        let query = normalise(s)
        return query.isEmpty ? nil : (s, Query(query: query, cardType: type))
    }
}
