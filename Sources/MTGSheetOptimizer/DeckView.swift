import SwiftUI

/// Images picked in phase 1, handed to the layout phase.
struct DeckFiles {
    var cards: [URL]         // one entry per copy, in deck order
    var doubleSided: [URL]   // both faces of double-faced cards, exported as singles
}

let imageCacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("MTG Sheet Optimizer", isDirectory: true)

// MARK: - Model

@MainActor @Observable
final class DeckModel {
    struct Face {
        var query: MPCFill.Query
        var results: [String] = []   // variant identifiers, best first
        var selected: MPCFill.Card?
    }

    struct Row: Identifiable {
        let id = UUID()
        var name: String
        var quantity: Int
        var included = true
        var front: Face
        var back: Face?
    }

    var text = UserDefaults.standard.string(forKey: "deckText") ?? "" {
        didSet { UserDefaults.standard.set(text, forKey: "deckText") }
    }
    var rows: [Row] = []
    var status = ""
    var busy = false
    private var cardCache: [String: MPCFill.Card] = [:]
    private var sources: [Int]?
    private var dfcPairs: [String: String]?

    private var chosen: [Row] { rows.filter { $0.included && $0.front.selected != nil } }
    var pageCards: Int { chosen.filter { $0.back == nil }.reduce(0) { $0 + $1.quantity } }
    var doubleSidedCards: Int { chosen.filter { $0.back != nil }.reduce(0) { $0 + $1.quantity } }

    func search() async {
        busy = true
        defer { busy = false }
        status = "Cerco su MPCFill…"
        do {
            if sources == nil { sources = try await MPCFill.sourceIDs() }
            if dfcPairs == nil { dfcPairs = try await MPCFill.dfcPairs() }
            let entries = MPCFill.parseDecklist(text, dfcPairs: dfcPairs ?? [:])
            let hits = try await MPCFill.search(entries.flatMap { [$0.front] + ($0.back.map { [$0] } ?? []) },
                                                sources: sources ?? [])
            var newRows = entries.map { e in
                Row(name: e.name, quantity: e.quantity,
                    front: Face(query: e.front, results: hits[e.front] ?? []),
                    back: e.back.map { Face(query: $0, results: hits[$0] ?? []) })
            }
            // Best variant of every face preselected, like mpcfill.com.
            let firsts = newRows.flatMap { [$0.front.results.first, $0.back?.results.first] }.compactMap { $0 }
            let details = try await cards(Array(Set(firsts)))
            for i in newRows.indices {
                let front = newRows[i].front.results.first.flatMap { details[$0] }
                let back = newRows[i].back?.results.first.flatMap { details[$0] }
                newRows[i].front.selected = front
                newRows[i].back?.selected = back
                newRows[i].included = front != nil
            }
            rows = newRows
            let missing = rows.filter { $0.front.selected == nil }.map(\.name)
            status = missing.isEmpty ? "Trovate tutte le \(rows.count) carte."
                                     : "Non trovate: " + missing.joined(separator: ", ")
        } catch {
            status = "Errore: \(error.localizedDescription)"
        }
    }

    /// Details of `ids`, in order, each fetched once.
    func variants(_ ids: [String]) async throws -> [MPCFill.Card] {
        let details = try await cards(ids)
        return ids.compactMap { details[$0] }
    }

    private func cards(_ ids: [String]) async throws -> [String: MPCFill.Card] {
        let missing = ids.filter { cardCache[$0] == nil }
        if !missing.isEmpty { cardCache.merge(try await MPCFill.cards(missing)) { a, _ in a } }
        return cardCache
    }

    /// Downloads the chosen variants (4 at a time) and returns them with one entry per copy.
    func download() async -> DeckFiles? {
        busy = true
        defer { busy = false }
        let rows = chosen
        let unique = Array(Set(rows.flatMap { [$0.front.selected, $0.back?.selected] }.compactMap { $0 }))
        var files: [String: URL] = [:]
        do {
            try await withThrowingTaskGroup(of: (String, URL).self) { group in
                for (i, card) in unique.enumerated() {
                    if i >= 4, let done = try await group.next() {
                        files[done.0] = done.1
                        status = "Scarico \(files.count)/\(unique.count)…"
                    }
                    group.addTask { (card.identifier, try await MPCFill.download(card, to: imageCacheDir)) }
                }
                for try await done in group {
                    files[done.0] = done.1
                    status = "Scarico \(files.count)/\(unique.count)…"
                }
            }
        } catch {
            status = "Errore: \(error.localizedDescription)"
            return nil
        }

        var out = DeckFiles(cards: [], doubleSided: [])
        for row in rows {
            let faces = [row.front.selected, row.back?.selected].compactMap { $0.flatMap { files[$0.identifier] } }
            for _ in 0..<row.quantity {
                if row.back == nil { out.cards += faces } else { out.doubleSided += faces }
            }
        }
        status = "Scaricate \(unique.count) immagini."
        return out
    }
}

// MARK: - Views

struct DeckView: View {
    @Bindable var deck: DeckModel
    let onReady: (DeckFiles) -> Void
    @State private var picking: Pick?

    struct Pick: Identifiable {
        let row: UUID
        let back: Bool
        var id: String { "\(row)-\(back)" }
    }

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Lista del mazzo").font(.headline)
                Text("Incolla l'export di Moxfield: \"1 Abrade\", \"11 Island\"…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $deck.text)
                    .font(.system(.body, design: .monospaced))
                    .border(Color.secondary.opacity(0.3))
                Button("Cerca su MPCFill") { Task { await deck.search() } }
                    .disabled(deck.busy || deck.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(10)
            .frame(minWidth: 220, idealWidth: 280, maxWidth: 420)

            VStack(spacing: 0) {
                if deck.rows.isEmpty {
                    Text("Incolla la lista e premi \"Cerca su MPCFill\".")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 16) {
                            ForEach($deck.rows) { $row in
                                FaceTile(row: $row, back: false) { picking = Pick(row: row.id, back: false) }
                                if row.back != nil {
                                    FaceTile(row: $row, back: true) { picking = Pick(row: row.id, back: true) }
                                }
                            }
                        }
                        .padding(12)
                    }
                }
                Divider()
                HStack {
                    if deck.busy { ProgressView().controlSize(.small) }
                    Text(deck.status).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Text("\(deck.pageCards) carte, \(deck.doubleSidedCards) fronte-retro")
                    Button("Scarica e impagina") {
                        Task { if let files = await deck.download() { onReady(files) } }
                    }
                    .disabled(deck.busy || deck.pageCards + deck.doubleSidedCards == 0)
                }
                .padding(10)
            }
            .frame(minWidth: 500)
        }
        .sheet(item: $picking) { pick in
            if let i = deck.rows.firstIndex(where: { $0.id == pick.row }),
               let face = pick.back ? deck.rows[i].back : deck.rows[i].front as DeckModel.Face? {
                VariantPicker(title: face.selected?.name ?? deck.rows[i].name, face: face, deck: deck) { card in
                    if pick.back { deck.rows[i].back?.selected = card } else { deck.rows[i].front.selected = card }
                }
            }
        }
    }
}

private struct FaceTile: View {
    @Binding var row: DeckModel.Row
    let back: Bool
    let pick: () -> Void

    var body: some View {
        let face = back ? row.back : row.front
        VStack(spacing: 4) {
            Button(action: pick) { Thumbnail(url: face?.selected?.smallThumbnailUrl) }
                .buttonStyle(.plain)
                .disabled(face?.results.isEmpty ?? true)
                .opacity(row.included ? 1 : 0.35)
                .help("Scegli la variante")
            Text(back ? "Retro: \(face?.selected?.name ?? "")" : row.name)
                .font(.caption.bold())
                .lineLimit(1)
            if let face, let card = face.selected {
                Text("\(card.sourceName) · \(card.dpi) DPI · \(face.results.count) varianti")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("Non trovata").font(.caption2).foregroundStyle(.red)
            }
            if !back {
                HStack(spacing: 4) {
                    Toggle("", isOn: $row.included)
                        .labelsHidden()
                        .disabled(row.front.selected == nil)
                    Stepper("×\(row.quantity)", value: $row.quantity, in: 1...99)
                        .font(.caption)
                }
            }
        }
    }
}

private struct Thumbnail: View {
    let url: String?

    var body: some View {
        AsyncImage(url: url.flatMap(URL.init(string:))) { image in
            image.resizable().scaledToFit()
        } placeholder: {
            RoundedRectangle(cornerRadius: 6)
                .fill(.quaternary)
                .overlay { if url != nil { ProgressView().controlSize(.small) } }
        }
        .aspectRatio(822.0 / 1122.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct VariantPicker: View {
    let title: String
    let face: DeckModel.Face
    let deck: DeckModel
    let onPick: (MPCFill.Card) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var cards: [MPCFill.Card] = []
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.headline)
                Text("\(face.results.count) varianti").foregroundStyle(.secondary)
                Spacer()
                Button("Chiudi") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(12)
            Divider()
            ScrollView {
                if let error { Text(error).foregroundStyle(.red).padding() }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 14) {
                    ForEach(cards) { card in
                        Button {
                            onPick(card)
                            dismiss()
                        } label: {
                            VStack(spacing: 3) {
                                Thumbnail(url: card.smallThumbnailUrl)
                                    .overlay {
                                        if card.identifier == face.selected?.identifier {
                                            RoundedRectangle(cornerRadius: 6).stroke(Color.accentColor, lineWidth: 3)
                                        }
                                    }
                                Text(card.sourceName).font(.caption).lineLimit(1)
                                Text("\(card.dpi) DPI · \(String(format: "%.1f", Double(card.size) / 1_000_000)) MB")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
            }
        }
        .frame(minWidth: 600, idealWidth: 820, minHeight: 440, idealHeight: 640)
        .task {
            do { cards = try await deck.variants(face.results) } catch { self.error = error.localizedDescription }
        }
    }
}
