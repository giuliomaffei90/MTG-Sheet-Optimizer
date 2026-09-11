import Testing
import Foundation
@testable import MTGSheetOptimizer

@Test func normalisesLikeMPCFill() {
    #expect(MPCFill.normalise("Baron, Airship Kingdom") == "baron airship kingdom")
    #expect(MPCFill.normalise("Ur-Golem's  Eye") == "ur-golems eye")
}

@Test func parsesMoxfieldList() {
    let deck = MPCFill.parseDecklist("""
        1 Abrade
        11 Island
        2x Opt (XLN) 65 *F*

        SIDEBOARD:
        t:Treasure
        1 Delver of Secrets
        1 Fire // Ice
        """, dfcPairs: ["delver of secrets": "insectile aberration"])
    #expect(deck.map(\.quantity) == [1, 11, 2, 1, 1, 1])
    #expect(deck.map(\.front.query) == ["abrade", "island", "opt", "treasure", "delver of secrets", "fire"])
    #expect(deck[1].name == "Island")
    #expect(deck[3].front.cardType == .token)
    #expect(deck[0].back == nil)
    #expect(deck[4].back?.query == "insectile aberration")
    #expect(deck[5].back?.query == "ice")
}

/// Talks to the real mpcfill.com and Google: `MPCFILL_LIVE=1 swift test`.
@Test(.enabled(if: ProcessInfo.processInfo.environment["MPCFILL_LIVE"] != nil))
func liveSearchAndDownload() async throws {
    let query = MPCFill.Query(query: "abrade", cardType: .card)
    let hits = try await MPCFill.search([query], sources: try await MPCFill.sourceIDs())
    let ids = Array(try #require(hits[query]).prefix(3))
    #expect(!ids.isEmpty)
    let card = try #require(try await MPCFill.cards(ids)[ids[0]])
    #expect(card.name == "Abrade")
    #expect(try await MPCFill.dfcPairs()["delver of secrets"] == "insectile aberration")
    #expect(try await MPCFill.cardbacks(sources: try await MPCFill.sourceIDs()).contains(CardBack.proxyBack.identifier))

    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let image = try loadImage(try await MPCFill.download(card, to: dir))
    #expect(image.height >= 1122)
}
