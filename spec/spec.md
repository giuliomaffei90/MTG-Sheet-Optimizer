# MTG Sheet Optimizer — shared contract

The macOS (SwiftUI) and Windows (WinUI) apps are separate codebases. This folder is the single source
of truth for everything a user can see in the **printed output**: change it first, then make both apps
match it. Interface, packaging and platform conventions may differ freely.

## Print geometry

| Value | |
|---|---|
| Output | transparent PNG, always **300 DPI** (PNG `pHYs` chunk = 11811 px/m) |
| Card canvas | 69.6 × 95 mm → **822 × 1122 px** (the size of `mask.png`) |
| Visible card | 63.5 × 88.9 mm, rounded corners — comes from `mask.png`'s alpha |
| Sheets | A4: 2162 × 3183 px, 6 slots · A3: 3193 × 4633 px, 14 slots |

A card is stretched to the card canvas and multiplied by the mask's alpha; nothing is cropped or letterboxed.

## Slots

A slot is a card centre in page pixels plus a rotation: `cx`, `cy`, `rot`. Rotation is **clockwise**,
snapped to 45°, normalised to 0–359. Layout files store `cx`/`cy` as fractions of the page
(`LayoutA4.json`, `LayoutA3.json`; keys `layout_kind`, `slots[].cx|cy|rot`; unknown keys are ignored).

## Sheet plan

`planSheets(cards, slots, pageWidth, kind, extra, doubleSided, backPage)` decides every file an export
writes. `cards` is one entry per copy, in deck order; a double-faced card carries a `back` face.

1. With `doubleSided = singles`, double-faced cards are not laid out: both faces go to `Double Sided/`.
   With `doubleSided = duplex`, their fronts are moved **to the front of the queue** and laid out with the
   rest, so fewer sheets need a back page of their own.
2. Cards fill the slots in order, `slots.count` per sheet: `layout_<kind>_001.png`, `002`, …
3. The leftover cards (fewer than a full sheet) follow `extra`: `emptySlots` writes
   `layout_<kind>_LAST.png` with the remaining slots empty, `singles` sends every face to `Singles/`.
4. A sheet holding a double-faced card gets `<sheet name>_back.png`. Every back sits at the **mirrored**
   position `cx → pageWidth - cx` (the sheet flips on its long edge) and is turned the opposite way,
   `rot → (360 - rot) mod 360`, so the back is upright once the cut card is flipped. On that page the
   other slots carry the generic card back only when `backPage` is on; otherwise they stay empty.
5. If `backPage` is on and at least one sheet has no double-faced card, a single `backpage_<kind>.png`
   with the generic back in every (mirrored, counter-rotated) slot is written **first**.
6. `Singles/` and `Double Sided/` files are named `<file stem>_alpha.png`; repeats of the same stem get
   ` 2`, ` 3`… so no copy overwrites another.

## MPCFill

Both apps talk to the public backend of [mpc-autofill](https://github.com/chilli-axe/mpc-autofill) at
`https://mpcfill.com` with no login, mirroring the website's defaults: every source enabled in ascending
primary key, fuzzy search off, DPI 0–1500, max size 30 MB, tag `NSFW` excluded.

| Endpoint | Use |
|---|---|
| `GET 2/sources/` | source list (order = ascending `pk`) |
| `POST 2/editorSearch/` | card name → variant identifiers, best first |
| `POST 2/cards/` | identifiers → name, source, DPI, size, thumbnail (≤ 1000 per call) |
| `POST 2/cardbacks/` | the cardbacks offered in Settings |
| `GET 2/DFCPairs/` | front → back names of double-faced cards |

Images come straight from Google: `https://lh4.googleusercontent.com/d/<identifier>=h2244`, twice the
1122 px the output needs. Cached as `<name> (<identifier>).<ext>`, the naming mpcfill.com exports use.
A request that fails with "network connection was lost" is retried once. User agent:
`Mozilla/5.0 (Macintosh) MTGSheetOptimizer` (Cloudflare rejects some defaults).

## Decklist

Moxfield's plain text: `1 Abrade`, `11 Island`, `2x Opt (XLN) 65 *F*`, `t:Treasure` (token),
`b:` (cardback), `Front // Back`. Lines that are empty, end with `:` or start with `#` or `//` are skipped;
`(set) number`, `*F*` markers and `@identifier` are dropped. A name is normalised like the website does:
lowercase, punctuation removed except hyphens, whitespace collapsed. Without an explicit back face, the
front is looked up in the DFC pairs.

## Conformance

`spec/cases/*.json` hold inputs and the expected plan; render cases also hold the expected geometry of
each drawn card (alpha bounding box in page pixels, tolerance ±2 px — two graphics engines never produce
identical pixels). Each app runs them and prints one JSON document:

```
{ "implementation": "...", "features": [...], "cases": { "<name>": { "plan": {...}, "geometry": {...} } } }
```

macOS: `swift run MTGSheetOptimizer --conformance spec --out out/macos.json`
Windows: `dotnet run --project windows/src/MTGSheet.Conformance -- spec out/windows.json`

`scripts/conformance-diff.py` compares the two and checks them against `spec/features.json`.
CI runs both and fails on any difference, so a feature that exists on one side only is visible at once.
