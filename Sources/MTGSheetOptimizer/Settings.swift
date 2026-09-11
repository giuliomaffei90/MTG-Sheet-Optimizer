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

struct SettingsView: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var lang = Lang.shared
        Form {
            Picker(tr("Language"), selection: $lang.current) {
                ForEach(Language.allCases) { Text($0.name).tag($0) }
            }
            .pickerStyle(.radioGroup)
            LabeledContent("Layout") {
                Button(tr("Edit layout…")) { openWindow(id: "layout-editor") }
            }
        }
        .padding(20)
        .frame(width: 360)
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
    "Back page is on but back.jpg is missing.": "Retro attivo ma back.jpg non trovato.",
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
