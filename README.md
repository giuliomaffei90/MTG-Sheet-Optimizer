# MTG Sheet Optimizer

App macOS che porta un mazzo di Magic: The Gathering dalla lista testuale ai fogli A4 o A3 pronti da
stampare e tagliare. Ogni file generato è un PNG trasparente a **300 DPI**.

Il lavoro è diviso in due fasi:

1. **Mazzo**: incolli la lista (per esempio l'export di Moxfield), l'app cerca le carte su
   [MPCFill](https://mpcfill.com) e per ognuna scegli la variante di art che preferisci.
2. **Impaginazione**: le carte scelte vengono rifilate e impaginate sui fogli.

## Fase 1: Mazzo

- Accetta le righe `1 Abrade`, `11 Island`, `2x Opt (XLN) 65 *F*`, `t:Treasure` (pedine) e
  `Fronte // Retro`. Le intestazioni come `SIDEBOARD:` vengono ignorate.
- Cerca su MPCFill con le sue impostazioni predefinite: tutte le fonti, NSFW escluse. Per ogni carta
  preseleziona la variante migliore.
- Cliccando una carta si aprono tutte le sue varianti, con fonte, DPI e peso del file.
- Per ogni carta puoi cambiare le copie o escluderla dalla stampa.
- Le carte fronte-retro (riconosciute da MPCFill o scritte come `Fronte // Retro`) mostrano anche la
  faccia posteriore. Entrambe le facce finiscono tra le carte fronte-retro, esportate come singole.
- **Scarica e impagina** scarica le immagini direttamente da Google, a 2244 px di altezza (il doppio di
  quanto serve a 300 DPI), e passa alla fase 2. Le immagini restano in
  `~/Library/Caches/MTG Sheet Optimizer/`, così i download successivi della stessa variante sono istantanei.

Per avere varianti diverse della stessa carta (per esempio più Island con art diverse), dividi la riga
nella lista: `5 Island` e `6 Island`.

## Fase 2: Impaginazione

- **Input**: il mazzo scaricato nella fase 1, oppure una cartella di immagini ("Usa una cartella").
  Dalla cartella le carte sono prese in ordine alfabetico, e quelle nella sottocartella `Double Sided/`
  sono trattate come fronte-retro.
- **Rifila le carte** con `mask.png`: ogni immagine viene portata a 69,6 × 95 mm e ritagliata sulla
  carta vera (63,5 × 88,9 mm, angoli arrotondati).
- **Impagina** 6 carte su A4 o 14 su A3, nelle posizioni e rotazioni del layout.
- **Ultima pagina incompleta**: puoi esportare le carte rimanenti singolarmente oppure una pagina
  con i posti vuoti.
- **Pagina dei dorsi** (opzionale): una pagina con `back.jpg` in ogni posto, specchiata in orizzontale
  per la stampa fronte-retro. Le carte ruotate di 90° usano `back90.jpg`.

Comandi dell'anteprima:
- trascina per spostare il posto più vicino al punto in cui clicchi;
- `r` / `⇧R` ruotano di 45° a sinistra / a destra, `⌫` azzera la rotazione;
- "Reimposta slot" rimette i posti su una griglia, "Salva layout" memorizza le posizioni.

File generati nella cartella di output:

| File | Contenuto |
|---|---|
| `layout_A4_001.png`, `002`… | pagine complete |
| `layout_A4_LAST.png` | ultima pagina con posti vuoti |
| `Singles/*_alpha.png` | carte rimanenti esportate singolarmente |
| `Double Sided/*_alpha.png` | carte fronte-retro rifilate |
| `backpage_A4.png` | pagina dei dorsi |

Le copie multiple della stessa carta esportate come singole prendono un numero (`Island 2_alpha.png`…),
così nessuna sovrascrive l'altra.

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

I layout salvati finiscono in `~/Library/Application Support/MTG Sheet Optimizer/`.
Ogni file che metti lì ha la precedenza su quello incluso nell'app. Per esempio puoi mettere un tuo
`back.jpg` / `back90.jpg`, oppure un `Layout A4.png` diverso come sfondo dell'anteprima.

## Struttura

```
Sources/MTGSheetOptimizer/
  App.swift        finestra, selettore delle fasi, fase 2 (impaginazione)
  DeckView.swift   fase 1: lista, griglia delle carte, scelta delle varianti, download
  MPCFill.swift    client dell'API di mpcfill.com e lettura della lista
  Render.swift     rifilatura, impaginazione, formato dei layout JSON
Tests/             test su lista, impaginazione, rotazioni e 300 DPI
Resources/         mask.png, sfondi e JSON dei layout, dorsi
AppIcon.icon       icona (documento di Icon Composer)
build.sh           compila l'app e l'icona
scripts/           build di sviluppo
```

MPCFill è un progetto open source ([chilli-axe/mpc-autofill](https://github.com/chilli-axe/mpc-autofill)):
l'app usa la sua API pubblica, senza login.
