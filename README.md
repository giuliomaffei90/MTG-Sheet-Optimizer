# MTG Sheet Optimizer

App macOS che porta un mazzo di Magic: The Gathering dalla lista testuale ai fogli A4 o A3 pronti da
stampare e tagliare. Ogni file generato è un PNG trasparente a **300 DPI**.

Il lavoro è diviso in due fasi:

1. **Mazzo**: incolli la lista (per esempio l'export di Moxfield), l'app cerca le carte su
   [MPCFill](https://mpcfill.com) e per ognuna scegli la variante di art che preferisci.
2. **Impaginazione**: scegli come impaginare, controlli l'anteprima dei fogli ed esporti.

## Fase 1: Mazzo

- Accetta le righe `1 Abrade`, `11 Island`, `2x Opt (XLN) 65 *F*`, `t:Treasure` (pedine) e
  `Fronte // Retro`. Le intestazioni come `SIDEBOARD:` vengono ignorate.
- Cerca su MPCFill con le sue impostazioni predefinite: tutte le fonti, NSFW escluse. Per ogni carta
  preseleziona la variante migliore.
- Ogni copia compare come carta a sé: con `10 Island` vedi 10 Island (`Island 1/10`…) e puoi scegliere
  un'art diversa per ognuna. La spunta sotto la carta la esclude dalla stampa.
- Cliccando una carta si aprono tutte le sue varianti, con fonte, DPI e peso del file.
- Lo slider in basso regola la grandezza delle carte nella griglia e nella scelta delle varianti.
- Le carte fronte-retro (riconosciute da MPCFill o scritte come `Fronte // Retro`) mostrano anche la
  faccia posteriore, con la sua variante.
- **Scarica e impagina** scarica le immagini direttamente da Google, a 2244 px di altezza (il doppio di
  quanto serve a 300 DPI), e passa alla fase 2. Le immagini restano in
  `~/Library/Caches/MTG Sheet Optimizer/`, così i download successivi della stessa variante sono istantanei.

## Fase 2: Impaginazione

In alto scegli come impaginare. Sotto, l'anteprima mostra dal vivo, in bassa risoluzione, tutti i fogli
che verranno generati; cambia appena modifichi un'opzione o il layout.

- **Layout**: A4 (6 carte) o A3 (14 carte), nelle posizioni definite nell'editor del layout.
- **Esporta retro**: aggiunge una pagina con il retro delle carte (scelto nelle Impostazioni) in ogni posto,
  specchiata in orizzontale per la stampa fronte-retro.
- **Carte in più**, per le carte che non riempiono l'ultimo foglio: *Ultima pagina con spazi vuoti*
  oppure *Come singole* (nella cartella `Singles/`).
- **Fronte-retro**, per le carte con due facce:
  - *Come singole*: le due facce vengono esportate rifilate in `Double Sided/`;
  - *Pagine fronte/retro*: le facce anteriori vanno sui fogli insieme alle altre carte (per prime, così
    servono meno pagine di retri) e ogni foglio che ne contiene riceve una sua pagina di retri, specchiata
    per la stampa fronte-retro sul lato lungo. Nei posti delle altre carte va il retro delle carte solo se
    *Esporta retro* è attivo; altrimenti restano vuoti.
- **Output**: la cartella dove scrivere i file. **Render** li genera.

Ogni carta viene rifilata con `mask.png`: l'immagine viene portata a 69,6 × 95 mm e ritagliata sulla carta
vera (63,5 × 88,9 mm, angoli arrotondati).

| File | Contenuto |
|---|---|
| `layout_A4_001.png`, `002`… | fogli completi |
| `layout_A4_001_back.png` | retri del foglio 001 (se contiene carte fronte-retro) |
| `layout_A4_LAST.png` | ultimo foglio con posti vuoti |
| `backpage_A4.png` | retri per tutti gli altri fogli (con *Esporta retro*) |
| `Singles/*_alpha.png` | carte in più esportate singolarmente |
| `Double Sided/*_alpha.png` | facce delle carte fronte-retro, se esportate come singole |

Le copie multiple della stessa carta esportate come singole prendono un numero (`Island 2_alpha.png`…),
così nessuna sovrascrive l'altra.

## Impostazioni

Da **MTG Sheet Optimizer → Impostazioni…** (⌘,):

- **Lingua**: inglese o italiano. Al primo avvio l'app è in inglese; il cambio è immediato.
- **Retro delle carte**: il retro usato da *Esporta retro*, scelto tra i cardback di MPCFill. Il predefinito
  è ProxyBack di OffPlanetVibes (1240 DPI).
- **Modifica layout…** apre l'editor dei due layout:
  - clic su una carta per selezionarla, `⇧`+clic per aggiungerne o toglierne altre, clic nel vuoto o
    `Esc` per deselezionare;
  - trascina per spostare le carte selezionate, le frecce le spostano di 1 px (`⇧`+freccia: 10 px);
  - *Allinea orizzontalmente* / *Allinea verticalmente* mettono le carte selezionate sulla stessa riga /
    colonna della prima selezionata;
  - *Distribuisci orizzontalmente* / *verticalmente* (almeno 3 carte) lasciano ferme le due più esterne e
    mettono quelle in mezzo a distanza uguale, da centro a centro;
  - `r` / `⇧R` ruotano la selezione di 45° a sinistra / a destra, `⌫` azzera la rotazione;
  - *Reimposta slot* rimette i posti su una griglia, *Carica layout…* importa un JSON.

  Ogni modifica viene salvata subito e l'anteprima della fase 2 si aggiorna mentre sposti le carte.

## Requisiti

- macOS 14 o successivo
- Xcode 26 per compilare (serve `actool` per l'icona Liquid Glass)
- Una connessione a internet per la fase 1

## Compilare

```bash
./build.sh
```

Crea `dist/MTG Sheet Optimizer.app`. Per lo sviluppo, `./scripts/build_dev_mac.sh` (o `/build` in
Claude Code) chiude l'app aperta, la ricompila, la copia in `~/Downloads` e la rilancia.

I test si lanciano con:

```bash
swift test
```

Il test che usa il sito vero di MPCFill e Google parte solo se lo chiedi:

```bash
MPCFILL_LIVE=1 swift test
```

## Personalizzare

I layout modificati finiscono in `~/Library/Application Support/MTG Sheet Optimizer/`.
Ogni file che metti lì ha la precedenza su quello incluso nell'app. Per esempio puoi mettere un
`Layout A4.png` diverso come sfondo dell'editor.

## Struttura

```
Sources/MTGSheetOptimizer/
  App.swift        finestre, selettore delle fasi, fase 2 (opzioni, anteprima, export)
  DeckView.swift   fase 1: lista, griglia delle carte, scelta delle varianti, download
  Layout.swift     layout A4/A3 e il loro editor
  MPCFill.swift    client dell'API di mpcfill.com e lettura della lista
  Render.swift     piano dei fogli, rifilatura, render a piena risoluzione e anteprima
  Settings.swift   impostazioni e traduzioni
Tests/             test su lista, piano dei fogli, fronte-retro, rotazioni e 300 DPI
spec/              contratto condiviso: regole, asset, testi, casi di prova
windows/           app Windows in C# (Core condiviso + interfaccia WinUI)
scripts/           generazione testi, confronto di conformità, build di sviluppo
AppIcon.icon       icona (documento di Icon Composer)
build.sh           compila l'app e l'icona
```

MPCFill è un progetto open source ([chilli-axe/mpc-autofill](https://github.com/chilli-axe/mpc-autofill)):
l'app usa la sua API pubblica, senza login.

## Versione Windows

`windows/` contiene la seconda app, in C#: `MTGSheet.Core` (piano dei fogli, rendering con SkiaSharp,
client MPCFill) e `MTGSheet.App`, l'interfaccia WinUI 3. Il cuore è lo stesso della versione macOS, ma
sono due codebase separate: quello che le tiene allineate è `spec/`.

```bash
dotnet build windows/src/MTGSheet.Core          # la libreria compila anche su macOS e Linux
dotnet build windows/src/MTGSheet.App           # l'app WinUI si compila solo su Windows
```

**Stato:** la libreria e il runner di conformità sono compilati e verificati; l'app WinUI è scritta ma va
ancora compilata e provata su una macchina Windows. Finché non succede, in `spec/features.json` le sue
funzioni di interfaccia restano marcate `"windows": false`.

## Come restano allineate le due versioni

Il contratto sta in `spec/` (vedi [spec/spec.md](spec/spec.md)): geometria di stampa, regole del piano dei
fogli, comportamento dell'API MPCFill, testi dell'interfaccia, asset condivisi e casi di prova.

- **Una sola definizione.** `spec/Resources/` contiene l'unica copia di `mask.png` e dei layout, usata da
  entrambe le build. `spec/strings.json` è l'unica copia dei testi: le tabelle Swift e C# si generano con
  `scripts/gen-strings.py`.
- **Un giudice automatico.** Ogni app sa girare i casi di `spec/cases/` e stampare cosa ha prodotto:

  ```bash
  swift run MTGSheetOptimizer --conformance spec --out out/macos.json
  dotnet run --project windows/src/MTGSheet.Conformance -- spec out/windows.json
  scripts/conformance-diff.py out/macos.json out/windows.json
  ```

  Il piano dei fogli deve coincidere esattamente; la posizione delle carte disegnate ha una tolleranza di
  2 px, perché due motori grafici non mettono mai i pixel allo stesso modo. Oggi coincidono anche i DPI.
- **Il debito è visibile.** `spec/features.json` elenca le funzioni e dice su quale piattaforma ci sono.
  La CI fallisce se un'app dichiara una funzione che il registro non prevede, o viceversa.
- **Ordine di lavoro per una feature nuova:** prima il caso in `spec/`, che rende rosse entrambe le CI,
  poi l'implementazione su una piattaforma, poi sull'altra.
