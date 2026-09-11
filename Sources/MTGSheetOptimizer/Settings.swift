import SwiftUI

enum Language: String, CaseIterable, Identifiable {
    case en, it
    var id: String { rawValue }
    var name: String { self == .en ? "English" : "Italiano" }
}

/// App language, English on first launch. Views that call `tr` re-render when it changes:
/// Observation tracks the read of `current` during `body`.
@Observable
final class Lang {
    static let shared = Lang()
    var current = Language(rawValue: UserDefaults.standard.string(forKey: "language") ?? "") ?? .en {
        didSet { UserDefaults.standard.set(current.rawValue, forKey: "language") }
    }
}

/// The English text is the key; `args` fill its %d / %@ placeholders.
func tr(_ english: String, _ args: CVarArg...) -> String {
    let text = Lang.shared.current == .it ? italianTranslations[english] ?? english : english
    return args.isEmpty ? text : String(format: text, arguments: args)
}

/// The generic card back: an MPCFill cardback chosen in Settings, ProxyBack by OffPlanetVibes until then.
enum CardBack {
    static let key = "cardBack"
    static let proxyBack = MPCFill.Card(
        identifier: "1Aa98sI-YvFUSnNYGGfJvc7NR9VtUOpNp", name: "ProxyBack", sourceName: "OffPlanetVibes",
        sourceType: "Google Drive", dpi: 1240, size: 8_986_157, extension: "jpg",
        smallThumbnailUrl: "https://drive.google.com/thumbnail?sz=w400-h400&id=1Aa98sI-YvFUSnNYGGfJvc7NR9VtUOpNp",
        downloadLink: nil)

    static func card(from data: Data) -> MPCFill.Card {
        (try? JSONDecoder().decode(MPCFill.Card.self, from: data)) ?? proxyBack
    }
    static func data(_ card: MPCFill.Card) -> Data { (try? JSONEncoder().encode(card)) ?? Data() }
    static var current: MPCFill.Card { card(from: UserDefaults.standard.data(forKey: key) ?? Data()) }
}

struct SettingsView: View {
    @Environment(\.openWindow) private var openWindow
    @AppStorage(CardBack.key) private var cardBackData = Data()

    var body: some View {
        @Bindable var lang = Lang.shared
        let back = CardBack.card(from: cardBackData)
        Form {
            Picker(tr("Language"), selection: $lang.current) {
                ForEach(Language.allCases) { Text($0.name).tag($0) }
            }
            .pickerStyle(.radioGroup)
            LabeledContent("Layout") {
                Button(tr("Edit layout…")) { openWindow(id: "layout-editor") }
            }
            LabeledContent(tr("Card back")) {
                HStack(spacing: 10) {
                    Thumbnail(url: back.smallThumbnailUrl).frame(width: 44)
                    VStack(alignment: .leading) {
                        Text(back.name)
                        Text("\(back.sourceName) · \(back.dpi) DPI").font(.caption).foregroundStyle(.secondary)
                    }
                    Button(tr("Choose…")) { openWindow(id: "card-backs") }
                }
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}

/// MPCFill's cardbacks in their own window: a sheet would overflow the small Settings window.
struct CardBackPicker: View {
    @AppStorage(CardBack.key) private var cardBackData = Data()

    var body: some View {
        VariantPicker(title: tr("Card back"), selected: CardBack.card(from: cardBackData).identifier, load: {
            let sources = try await MPCFill.sourceIDs()
            let ids = try await MPCFill.cardbacks(sources: sources)
            let details = try await MPCFill.cards(ids)
            return ids.compactMap { details[$0] }
        }) { cardBackData = CardBack.data($0) }
    }
}
