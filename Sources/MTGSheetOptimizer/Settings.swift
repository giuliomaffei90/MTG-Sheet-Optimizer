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

let italianTranslations: [String: String] = [
    // Window and settings
    "1. Deck": "1. Mazzo",
    "2. Layout": "2. Impaginazione",
    "Phase": "Fase",
    "Language": "Lingua",
    "Edit layout…": "Modifica layout…",
    "Layout editor": "Editor del layout",
    "Card back": "Retro delle carte",

    // Deck phase
    "Deck list": "Lista del mazzo",
    "Search MPCFill": "Cerca su MPCFill",
    "Paste the list and press \"Search MPCFill\".": "Incolla la lista e premi \"Cerca su MPCFill\".",
    "Card size": "Grandezza delle carte",
    "Cards: %d · Double-sided: %d": "Carte: %d · Fronte-retro: %d",
    "Download and lay out": "Scarica e impagina",
    "Choose the variant": "Scegli la variante",
    "Back: %@": "Retro: %@",
    "%@ · %d DPI · %d var.": "%@ · %d DPI · %d var.",
    "Not found": "Non trovata",
    "Print this card": "Stampa questa carta",
    "Variants: %d": "Varianti: %d",
    "Loading variants…": "Carico le varianti…",
    "Searching MPCFill…": "Cerco su MPCFill…",
    "Cards found: %d.": "Carte trovate: %d.",
    "Not found: %@": "Non trovate: %@",
    "Error: %@": "Errore: %@",
    "Downloading %d/%d…": "Scarico %d/%d…",
    "Downloaded %d images.": "Scaricate %d immagini.",
    "MPCFill answered %d to %@": "MPCFill ha risposto %d a %@",
    "No download link for %@": "Nessun link per scaricare %@",
    "Download failed: %@": "Download fallito: %@",

    // Layout phase
    "Export back page": "Esporta retro",
    "Extra cards": "Carte in più",
    "Last page with empty slots": "Ultima pagina con spazi vuoti",
    "As singles": "Come singole",
    "Double-sided": "Fronte-retro",
    "Front/back pages": "Pagine fronte/retro",
    "Open output": "Apri output",
    "Choose…": "Scegli…",
    "Search and download a deck in \"1. Deck\" first.": "Prima cerca e scarica un mazzo in \"1. Mazzo\".",
    "Sheets: %d · Back pages: %d · Singles: %d": "Fogli: %d · Pagine di retri: %d · Singole: %d",
    "Layout or mask.png missing": "Layout o mask.png mancanti",
    "Choose an output folder.": "Scegli la cartella di output.",
    "Rendering…": "Render in corso…",
    "Error.": "Errore.",
    "Done": "Completato",
    "Open folder": "Apri cartella",
    "Close": "Chiudi",
    "Error": "Errore",
    "Can't read %@": "Impossibile leggere %@",
    "Can't write %@": "Impossibile scrivere %@",
    "%@ pages: %d": "Pagine %@: %d",
    "Back pages: %d": "Pagine di retri: %d",
    "Singles in '%@': %d": "Singole in '%@': %d",
    "Cut cards in '%@': %d": "Alpha in '%@': %d",
    "Done: %@.": "Fatto: %@.",
    "nothing to do": "niente da fare",

    // Layout editor
    "Load layout…": "Carica layout…",
    "Reset slots": "Reimposta slot",
    "Wrong number of slots for %@.": "Numero di slot sbagliato per %@.",
    "Align horizontally": "Allinea orizzontalmente",
    "Align vertically": "Allinea verticalmente",
    "Puts the selected cards on the same row as the first one you selected.":
        "Mette le carte selezionate sulla stessa riga della prima che hai selezionato.",
    "Puts the selected cards in the same column as the first one you selected.":
        "Mette le carte selezionate nella stessa colonna della prima che hai selezionato.",
    "Distribute horizontally": "Distribuisci orizzontalmente",
    "Distribute vertically": "Distribuisci verticalmente",
    "Spaces the selected cards evenly from left to right.":
        "Distribuisce le carte selezionate a distanza uguale da sinistra a destra.",
    "Spaces the selected cards evenly from top to bottom.":
        "Distribuisce le carte selezionate a distanza uguale dall'alto in basso.",
]
