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
    var body: some View {
        @Bindable var lang = Lang.shared
        Form {
            Picker(tr("Language"), selection: $lang.current) {
                ForEach(Language.allCases) { Text($0.name).tag($0) }
            }
            .pickerStyle(.radioGroup)
        }
        .padding(20)
        .frame(width: 320)
    }
}

let italianTranslations: [String: String] = [
    // Window and settings
    "1. Deck": "1. Mazzo",
    "2. Layout": "2. Impaginazione",
    "Phase": "Fase",
    "Language": "Lingua",

    // Deck phase
    "Deck list": "Lista del mazzo",
    "Search MPCFill": "Cerca su MPCFill",
    "Paste the list and press \"Search MPCFill\".": "Incolla la lista e premi \"Cerca su MPCFill\".",
    "Card size": "Grandezza delle carte",
    "%d cards, %d double-sided": "%d carte, %d fronte-retro",
    "Download and lay out": "Scarica e impagina",
    "Choose the variant": "Scegli la variante",
    "Back: %@": "Retro: %@",
    "%@ · %d DPI · %d variants": "%@ · %d DPI · %d varianti",
    "Not found": "Non trovata",
    "Print this card": "Stampa questa carta",
    "%d variants": "%d varianti",
    "Loading %d variants…": "Carico %d varianti…",
    "Searching MPCFill…": "Cerco su MPCFill…",
    "Found all %d cards.": "Trovate tutte le %d carte.",
    "Not found: %@": "Non trovate: %@",
    "Error: %@": "Errore: %@",
    "Downloading %d/%d…": "Scarico %d/%d…",
    "Downloaded %d images.": "Scaricate %d immagini.",
    "MPCFill answered %d to %@": "MPCFill ha risposto %d a %@",
    "No download link for %@": "Nessun link per scaricare %@",
    "Download failed: %@": "Download fallito: %@",

    // Layout phase
    "Export back page": "Esporta retro",
    "Save layout": "Salva layout",
    "Load layout…": "Carica layout…",
    "Reset slots": "Reimposta slot",
    "Deck from MPCFill: %d cards, %d double-sided faces": "Mazzo da MPCFill: %d carte, %d facce fronte-retro",
    "Use a folder": "Usa una cartella",
    "Open output": "Apri output",
    "Choose…": "Scegli…",
    "Layout or mask.png missing": "Layout o mask.png mancanti",
    "mask.png missing or invalid.": "mask.png mancante o non valido.",
    "%@ loaded.": "%@ caricato.",
    "Saved %@.": "Salvato %@.",
    "Loaded %@.": "Caricato %@.",
    "Can't find %@.": "Non trovo %@.",
    "Choose an output folder.": "Scegli la cartella di output.",
    "Choose an input folder.": "Scegli la cartella di input.",
    "No valid images in the input.": "Nessuna immagine valida in input.",
    "Back page is on but back.jpg is missing.": "Retro attivo ma back.jpg non trovato.",
    "Back page is on with 90° cards but back90.jpg is missing.": "Retro attivo con carte a 90° ma back90.jpg non trovato.",
    "Rendering…": "Render in corso…",
    "Error.": "Errore.",
    "Incomplete last page": "Ultima pagina incompleta",
    "The last page is missing %d cards. What do you want to do with the remaining cards?":
        "Nell'ultima pagina mancano %d carte. Cosa vuoi fare con le carte rimanenti?",
    "Export as singles": "Esporta singolarmente",
    "Export page with empty slots": "Esporta pagina con spazi vuoti",
    "Cancel": "Annulla",
    "Cancelled.": "Annullato.",
    "Done": "Completato",
    "Open folder": "Apri cartella",
    "Close": "Chiudi",
    "Error": "Errore",
    "Can't read %@": "Impossibile leggere %@",
    "Can't write %@": "Impossibile scrivere %@",
    "%d %@ pages": "%d layout %@",
    "1 last page with empty slots": "1 ultima pagina con spazi vuoti",
    "%d singles in '%@'": "%d singole in '%@'",
    "%d cut cards in '%@'": "%d alpha in '%@'",
    "1 %@ back page": "1 retro %@",
    "Done: %@.": "Fatto: %@.",
    "nothing to do": "niente da fare",
]
