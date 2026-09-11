# CLAUDE.md

Guida per lavorare in questo repository. Per l'uso dell'app c'è [README.md](README.md); qui ci sono le
regole del dominio, i comandi e le trappole già incontrate.

## Cos'è

Una sola app macOS in SwiftUI (`Sources/MTGSheetOptimizer/`, SwiftPM). Prende una lista di carte in testo,
cerca le immagini su [MPCFill](https://mpcfill.com), fa scegliere la variante di art e impagina le carte su
fogli A4 o A3 a 300 DPI, pronti da stampare e tagliare.

```
Sources/MTGSheetOptimizer/
  Render.swift     piano dei fogli, rifilatura con la maschera, render e anteprima
  MPCFill.swift    client dell'API e lettura della lista
  App.swift        finestre, selettore delle fasi, fase 2 (opzioni, anteprima, export)
  DeckView.swift   fase 1 (lista, griglia delle carte, varianti, download)
  Layout.swift     layout A4/A3 e il loro editor
  Settings.swift   impostazioni, lingua, retro delle carte, tabella delle traduzioni
Tests/             test su lista, piano dei fogli, fronte-retro, rotazioni, 300 DPI
Resources/         mask.png e i due layout (PNG di sfondo + JSON degli slot)
AppIcon.icon       icona Liquid Glass (documento di Icon Composer)
build.sh           compila app e icona; scripts/build_dev_mac.sh ricompila e rilancia (skill /build)
```

## Regole di stampa (il cuore del progetto)

- **Uscita sempre a 300 DPI**, non c'è un selettore. La scrive ImageIO nei metadati del PNG.
- **Tela della carta**: 69,6 × 95 mm = **822 × 1122 px**, cioè la dimensione di `mask.png`. La carta vera
  (63,5 × 88,9 mm con angoli arrotondati) è il canale alpha della maschera. L'immagine viene stirata sulla
  tela e moltiplicata per quell'alpha: niente ritagli, niente bande.
- **Slot**: centro in pixel di pagina più rotazione oraria, agganciata a 45° e normalizzata tra 0 e 359.
  Nei file JSON dei layout `cx` e `cy` sono frazioni della pagina.
- **Fogli**: A4 2162 × 3183 px, 6 slot; A3 3193 × 4633 px, 14 slot. Non sono fogli A4/A3 interi: sono
  l'area stampabile di **Print then Cut** della Cricut (7,2 × 10,62 pollici su A4, 10,64 × 15,44 su A3) e
  gli angoli a gradini dei PNG di sfondo sono lo spazio riservato ai segni di registro. Lo sfondo
  trasparente attorno alle carte è la linea lungo cui taglia Design Space: per questo l'uscita è PNG con
  alpha e non JPEG.
- **Retri**: ogni retro sta alla x specchiata (`pageWidth - cx`) con rotazione invertita (`360 - rot`).
  È la stampa fronte-retro sul lato lungo: così il retro è dritto quando giri la carta tagliata.
- **Piano dei fogli** (`planSheets` in `Render.swift`): con *Pagine fronte/retro* le facce anteriori delle
  carte fronte-retro vanno in testa alla coda, così servono meno pagine di retri; le carte avanzate seguono
  l'opzione *Carte in più*; un foglio che contiene una carta fronte-retro riceve la sua pagina di retri, e
  gli altri posti prendono il dorso solo se *Esporta retro* è attivo; se almeno un foglio non ha carte
  fronte-retro si scrive una sola `backpage_<formato>.png` all'inizio.
- **Nomi dei file** generati: vedi la tabella nel README. Le singole ripetute prendono un numero
  (`Island 2_alpha.png`), così nessuna copia sovrascrive l'altra.

## MPCFill

API pubblica, senza login, con le stesse impostazioni del sito: tutte le fonti in ordine di chiave
crescente, ricerca non fuzzy, DPI 0–1500, massimo 30 MB, tag `NSFW` escluso.

| Endpoint | Uso |
|---|---|
| `GET 2/sources/` | elenco delle fonti |
| `POST 2/editorSearch/` | nome della carta → identificativi delle varianti, migliore per prima |
| `POST 2/cards/` | identificativi → nome, fonte, DPI, dimensione, miniatura (max 1000 per chiamata) |
| `POST 2/cardbacks/` | i retri proposti nelle impostazioni |
| `GET 2/DFCPairs/` | nomi fronte → retro delle carte fronte-retro |

Le immagini arrivano da Google: `https://lh4.googleusercontent.com/d/<id>=h2244`, il doppio dei 1122 px
che servono. Restano in cache come `<nome> (<identificativo>).<est>`, lo stesso nome che esporta il sito.

## Comandi

```bash
swift test                      # 12 test
MPCFILL_LIVE=1 swift test       # aggiunge il test che interroga mpcfill.com davvero
./build.sh                      # crea dist/MTG Sheet Optimizer.app (serve actool di Xcode)
./scripts/build_dev_mac.sh      # chiude l'app, ricompila, copia in ~/Downloads, rilancia (skill /build)
```

## Prima di ogni commit

1. `swift test`
2. se hai toccato l'interfaccia, ricompila e guardala davvero: `./scripts/build_dev_mac.sh`
3. niente build output in git (`.build/`, `dist/` sono già in `.gitignore`)

## Convenzioni

- **Testi dell'interfaccia**: la chiave è la frase inglese, la traduzione italiana sta nella tabella in
  fondo a `Settings.swift`. Segnaposto `%d` e `%@` nello stesso ordine nelle due lingue: c'è un test che
  lo verifica. L'app parte in inglese.
- **Lingua**: commenti e nomi nel codice in inglese; README in inglese; questo file in italiano.
- **Asset**: una sola copia in `Resources/`, copiata nel bundle da `build.sh`.
- **Percorsi a runtime**: layout e impostazioni in `~/Library/Application Support/MTG Sheet Optimizer/`,
  immagini scaricate in `~/Library/Caches/MTG Sheet Optimizer/`. Un file messo in Application Support ha
  la precedenza su quello incluso nell'app.
- **La lista del mazzo non viene salvata**: a ogni avvio riparte vuota, di proposito.
- **Test**: logica non banale lascia dietro un test eseguibile. Il render è verificato leggendo i pixel
  della pagina prodotta, non a occhio.

## Trappole già incontrate

- **URLSession** può riusare una connessione che il server ha già chiuso ("network connection was lost"):
  ogni richiesta e ogni download vengono ripetuti una volta.
- **User agent obbligatorio** verso mpcfill.com: Cloudflare rifiuta quelli di default.
- **Anteprima**: si ricalcola con `.task(id:)` e un ritardo di 120 ms, così trascinare uno slot
  nell'editor non lancia venti render. Le miniature mascherate sono in cache in un actor.
- **L'editor del layout salva a ogni modifica**: se ci provi sopra, stai riscrivendo il layout dell'utente.
- **Menu a comparsa e ⇧+clic non si possono pilotare in background** con gli strumenti di controllo app:
  per provarli serve il controllo schermo, oppure si scrive la preferenza da riga di comando.
- **Icona**: `AppIcon.icon` è un documento di Icon Composer, compilato da `actool`. Il favicon dell'app non
  va cambiato tra una build e l'altra.

## Release

Convenzione presa da Arcane Manager (`agents/release-notes.md` di quel repo).

- **Numero di versione**: si propone all'utente e si aspetta il suo via libera prima di taggare. Non è
  semver: la major si alza solo se lo chiede lui, la minor per funzioni vere, la patch per correzioni e
  ritocchi. La fonte di verità è `CFBundleShortVersionString` nell'Info.plist dentro `build.sh`, da alzare
  nello stesso commit della release, e il tag `vX.Y.Z` deve combaciare.
- **Changelog**: scritto per intero prima di taggare, in inglese al passato ("Added", "Improved",
  "Fixed"), confrontando con la release precedente e non con l'ultimo commit. Formato: una sezione
  `## Changes` con i punti rivolti all'utente e una `## Notes` con le avvertenze (build non firmata,
  Gatekeeper, requisiti). Niente sezioni su verifica o elenco degli allegati: quelli GitHub li mostra già.
- **Tag**: `git tag -a vX.Y.Z -F <file-changelog> --cleanup=verbatim`. Il `--cleanup=verbatim` è
  obbligatorio: senza, git tratta le righe `## ` come commenti e la release perde i titoli di sezione.
- **Pubblicazione**: build locale con `./build.sh`, DMG con l'app più il collegamento ad Applications, poi
  `gh release create vX.Y.Z --title "MTG Sheet Optimizer X.Y.Z" --notes-file <file-changelog> <dmg>`.
  In Arcane Manager la build la fa la CI al push del tag; qui l'app è solo macOS e il toolchain giusto è
  già in locale, quindi si costruisce e si carica da qui.

## Nota storica

C'è stato un tentativo di seconda app per Windows in C#/WinUI, con un contratto condiviso in `spec/`,
runner di conformità e CI di parità. È stato rimosso: resta nella storia fino al commit `ebf9ace`, se mai
servisse recuperarlo.
