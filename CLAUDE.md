# CLAUDE.md

Guida per lavorare in questo repository: cosa contiene, come si tiene insieme e con che procedura si
aggiunge una feature. Per l'uso dell'app c'è [README.md](README.md); per le regole di stampa
[spec/spec.md](spec/spec.md).

## Cos'è

Due applicazioni native della stessa cosa, più un contratto condiviso che le tiene allineate.

| | |
|---|---|
| **macOS** | SwiftUI, `Sources/MTGSheetOptimizer/`. È l'implementazione di riferimento: compilata, testata e in uso. |
| **Windows** | C# in `windows/`: `MTGSheet.Core` (logica, compilata e verificata anche su Mac) e `MTGSheet.App` (WinUI 3, **scritta ma mai compilata**: serve una macchina Windows). |
| **Contratto** | `spec/`: regole di stampa, asset, testi dell'interfaccia, registro delle feature, casi di prova. |

L'app prende una lista di carte in testo, cerca le immagini su [MPCFill](https://mpcfill.com), fa scegliere
la variante di art e impagina le carte su fogli A4 o A3 a 300 DPI, pronti da stampare e tagliare.

## Mappa

```
spec/                    IL CONTRATTO — si cambia per primo
  spec.md                geometria di stampa, piano dei fogli, API, lista
  cases/*.json           casi di prova: ingressi e piano atteso (+ geometria per i render)
  features.json          registro delle feature e su quale piattaforma esistono
  strings.json           unica copia dei testi dell'interfaccia (en/it)
  Resources/             unica copia di mask.png e dei layout A4/A3
  fixtures/              immagini di prova deterministiche (scripts/make-fixtures.py)

Sources/MTGSheetOptimizer/   app macOS
  Render.swift           piano dei fogli, rifilatura, render e anteprima
  MPCFill.swift          client dell'API e lettura della lista
  App.swift              finestre, fase 2 (opzioni, anteprima, export)
  DeckView.swift         fase 1 (lista, griglia, varianti, download)
  Layout.swift           layout A4/A3 e editor
  Settings.swift         impostazioni, lingua, retro delle carte
  Conformance.swift      modalità --conformance
  Strings.generated.swift   GENERATO da spec/strings.json — non modificare a mano
Tests/                   test Swift

windows/src/
  MTGSheet.Core/         Sheets, Imaging, Export, MPCFill, LayoutFile, Localization
                         Strings.generated.cs   GENERATO — non modificare a mano
  MTGSheet.Conformance/  runner dei casi di spec/
  MTGSheet.App/          interfaccia WinUI, scritta in codice senza XAML

scripts/                 gen-strings, check-strings, conformance-diff, make-fixtures, build_dev_mac
.github/workflows/ci.yml macOS + Windows + job di parità
```

## Regola d'oro

**Il contratto viene prima del codice.** Qualunque cosa cambi il risultato stampato (piano dei fogli,
geometria, nomi dei file, retri, comportamento delle opzioni) si scrive prima in `spec/`, poi nelle due app.
Così la funzione nasce già dichiarata su entrambe le piattaforme e la mancanza si vede subito.

## Procedura per una feature nuova

Esempio: "aggiungere i segni di taglio agli angoli".

1. **Spec.** Aggiungi la regola in `spec/spec.md`, un caso in `spec/cases/` con il risultato atteso e la
   voce in `spec/features.json` con `"macos": false, "windows": false`. Da qui entrambe le CI sono rosse:
   la feature esiste e risulta mancante su tutte e due.
2. **Testi.** Se servono frasi nuove, vanno in `spec/strings.json`, poi `scripts/gen-strings.py`.
3. **macOS.** Implementa, `swift test`, la conformità deve tornare verde. Metti `"macos": true`.
4. **Windows.** Implementa in `MTGSheet.Core` (e nell'interfaccia se serve), fai girare la conformità,
   confronta con quella macOS. Metti `"windows": true`.
5. **Rilascio.** Esce quando entrambe sono verdi, oppure esce su una sola e il changelog lo dice.

Una feature di sola interfaccia (un pulsante, una scorciatoia) non ha un caso in `spec/cases/`: si dichiara
comunque in `features.json` e si verifica a mano sulla piattaforma.

## Comandi

```bash
# macOS
swift test                                   # 12 test: lista, piano, rotazioni, 300 DPI
MPCFILL_LIVE=1 swift test                    # aggiunge il test che interroga mpcfill.com davvero
./build.sh                                   # crea dist/MTG Sheet Optimizer.app (serve actool di Xcode)
./scripts/build_dev_mac.sh                   # chiude l'app, ricompila, copia in ~/Downloads, rilancia (skill /build)

# Windows (la libreria compila anche su Mac; l'app WinUI no)
dotnet build windows/src/MTGSheet.Core
dotnet build windows/src/MTGSheet.App        # solo su Windows

# Conformità e parità
swift run MTGSheetOptimizer --conformance spec --out out/macos.json
dotnet run --project windows/src/MTGSheet.Conformance -- "$PWD/spec" out/windows.json
scripts/conformance-diff.py out/macos.json out/windows.json
scripts/check-strings.py                     # ogni testo usato esiste in spec/strings.json
scripts/gen-strings.py                       # rigenera le due tabelle dei testi
```

## Prima di ogni commit

1. `swift test`
2. le due corse di conformità e `conformance-diff.py`: devono dire *same plans, same geometry*
3. `check-strings.py` e `gen-strings.py` (con `git diff` pulito dopo)
4. se hai toccato l'interfaccia macOS, ricompila e guarda l'app: `./scripts/build_dev_mac.sh`

## Convenzioni

- **Geometria.** Slot = centro in pixel di pagina + rotazione oraria, multipli di 45°, normalizzata 0–359.
  I retri stanno alla x specchiata (`pageWidth - cx`) con rotazione invertita (`360 - rot`): è la stampa
  fronte-retro sul lato lungo.
- **300 DPI sempre.** Non esiste un selettore. Su macOS lo scrive ImageIO, su Windows si inserisce a mano
  il chunk `pHYs` (`Imaging.WithDpi`).
- **Un solo posto per ogni cosa.** Asset in `spec/Resources/`, testi in `spec/strings.json`. I file
  `Strings.generated.*` sono prodotti da uno script: modificarli a mano è lavoro perso al primo rigenero.
- **Testi.** La chiave è la frase inglese; l'italiano sta nel JSON. Segnaposto `%d` e `%@` in entrambe le
  lingue, nello stesso ordine (c'è un test che lo verifica).
- **Lingua.** Commenti e nomi nel codice in inglese; README e questo file in italiano.
- **Percorsi a runtime.** macOS: `~/Library/Application Support/MTG Sheet Optimizer` (layout, impostazioni)
  e `~/Library/Caches/...` (immagini scaricate). Windows: `%APPDATA%` e `%LOCALAPPDATA%\...\Cache`.
- **Git.** Niente `windows/**/bin|obj` (sono in `.gitignore`, contengono anche le librerie native di Skia).

## Trappole già incontrate

- **Arrotondamenti.** `Double.rounded()` di Swift arrotonda allontanandosi da zero: in C# serve
  `MidpointRounding.AwayFromZero`, altrimenti i piani divergono sui mezzi.
- **Confronto tra motori grafici.** CoreGraphics e Skia non producono pixel identici: non confrontare mai
  hash di immagini. Si confronta il rettangolo occupato da ogni carta, con tolleranza di 2 px.
- **`dotnet run` passa `--nologo` al programma**, non solo a MSBuild: usa `-v q` e niente `--nologo` quando
  lanci il runner di conformità.
- **La conformità macOS gira dentro l'app grafica** (`Conformance.runIfRequested()` in `App.init`) ed esce
  prima di aprire finestre, quindi funziona anche senza interfaccia.
- **MPCFill.** Serve lo user agent dichiarato nello spec (Cloudflare rifiuta quelli di default), gli
  endpoint sono quelli `2/…` e una richiesta che cade con "network connection was lost" va ripetuta una volta.
- **WinUI senza XAML.** L'app Windows costruisce l'interfaccia in codice: niente compilatore XAML, quindi
  meno cose da indovinare finché non la si compila su Windows davvero.

## Stato e debito

- Il nucleo (lista, ricerca, piano, render) è verificato su entrambe le piattaforme.
- L'interfaccia WinUI non è mai stata compilata: in `spec/features.json` le sue voci `ui` sono `false`.
  Quando la compili su Windows e la provi, aggiorna quei flag nello stesso commit.
- Differenza nota: su macOS il cambio lingua è immediato, su Windows vale per le finestre aperte dopo.
