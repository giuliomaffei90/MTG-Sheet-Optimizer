# MTG Sheet Optimizer

A macOS app that takes a Magic: The Gathering deck from a plain text list to A4 or A3 sheets ready to
print and cut. Every file it writes is a transparent PNG at **300 DPI**.

The work is split in two phases:

1. **Deck**: paste the list (a Moxfield export, for instance), the app searches the cards on
   [MPCFill](https://mpcfill.com) and you pick the art you want for each one.
2. **Layout**: choose how to lay them out, check the live preview of the sheets, export.

## Phase 1: Deck

- Reads lines like `1 Abrade`, `11 Island`, `2x Opt (XLN) 65 *F*`, `t:Treasure` (tokens) and
  `Front // Back`. Headers such as `SIDEBOARD:` are ignored.
- Searches MPCFill with the website's own defaults: every source, NSFW excluded. The best variant of each
  card is preselected.
- Every copy is its own card: `10 Island` shows ten Islands (`Island 1/10`…), each with its own art. The
  checkbox under a card leaves it out of the print run.
- Clicking a card opens all of its variants, with source, DPI and file size.
- The slider at the bottom sets how large the cards are, both in the grid and in the variant picker.
- Double-faced cards (recognised by MPCFill, or written as `Front // Back`) also show their back face,
  with its own variant.
- **Download and lay out** fetches the images straight from Google at 2244 px tall (twice what 300 DPI
  needs) and moves on to phase 2. Images stay in `~/Library/Caches/MTG Sheet Optimizer/`, so downloading
  the same variant again is instant.

## Phase 2: Layout

The options sit at the top. Below them the preview shows, live and at low resolution, every sheet that
will be written; it follows any change to the options or to the layout.

- **Layout**: A4 (6 cards) or A3 (14 cards), in the positions set in the layout editor.
- **Export back page**: adds a page with the card back (chosen in Settings) in every slot, mirrored
  horizontally for duplex printing.
- **Extra cards**, for the cards that don't fill the last sheet: *Last page with empty slots*, or
  *As singles* (in the `Singles/` folder).
- **Double-sided**, for cards with two faces:
  - *As singles*: both faces are exported cut, in `Double Sided/`;
  - *Front/back pages*: the front faces are laid out with the other cards (first, so fewer sheets need a
    back page of their own) and every sheet holding one gets its own page of backs, mirrored for a
    long-edge duplex flip. The other slots on that page carry the card back only when *Export back page*
    is on; otherwise they stay empty.
- **Output**: the folder to write into. **Render** writes the files.

Every card is cut out with `mask.png`: the image is scaled to 69.6 × 95 mm and clipped to the real card
(63.5 × 88.9 mm, rounded corners).

| File | Contents |
|---|---|
| `layout_A4_001.png`, `002`… | full sheets |
| `layout_A4_001_back.png` | the backs of sheet 001 (when it holds double-faced cards) |
| `layout_A4_LAST.png` | last sheet, with empty slots |
| `backpage_A4.png` | the backs shared by every other sheet (with *Export back page*) |
| `Singles/*_alpha.png` | leftover cards exported one by one |
| `Double Sided/*_alpha.png` | faces of double-faced cards, when exported as singles |

Several copies of the same card exported as singles are numbered (`Island 2_alpha.png`…), so no copy
overwrites another.

## Settings

**MTG Sheet Optimizer → Settings…** (⌘,):

- **Language**: English or Italian. The app starts in English; switching takes effect at once.
- **Card back**: the back used by *Export back page*, picked from MPCFill's cardbacks. The default is
  ProxyBack by OffPlanetVibes (1240 DPI).
- **Edit layout…** opens the editor for both layouts:
  - click a card to select it, `⇧`+click to add or remove others, click empty space or press `Esc` to
    deselect;
  - drag to move the selection, arrow keys nudge it by 1 px (`⇧`+arrow: 10 px);
  - *Align horizontally* / *Align vertically* put the selected cards on the same row / column as the
    first one selected;
  - *Distribute horizontally* / *vertically* (three cards or more) keep the outermost two and space the
    rest evenly, centre to centre;
  - `r` / `⇧R` rotate the selection 45° left / right, `⌫` resets the rotation;
  - *Reset slots* lays the slots back on a grid, *Load layout…* imports a JSON file.

  Every change is saved immediately, and the phase 2 preview follows as you move the cards.

## Requirements

- macOS 14 or later
- Xcode 26 to build (`actool` compiles the Liquid Glass icon)
- An internet connection for phase 1

## Building

```bash
./build.sh
```

Produces `dist/MTG Sheet Optimizer.app`. While developing, `./scripts/build_dev_mac.sh` quits the running
app, rebuilds it, copies it to `~/Downloads` and launches it again.

Tests:

```bash
swift test
```

The test that talks to the real mpcfill.com and Google only runs when you ask for it:

```bash
MPCFILL_LIVE=1 swift test
```

## Customising

Edited layouts land in `~/Library/Application Support/MTG Sheet Optimizer/`. Any file you drop there wins
over the one bundled in the app — a different `Layout A4.png` as the editor's background, for instance.

## Structure

```
Sources/MTGSheetOptimizer/
  App.swift        windows, phase picker, phase 2 (options, preview, export)
  DeckView.swift   phase 1: list, card grid, variant picker, downloads
  Layout.swift     the A4/A3 layouts and their editor
  MPCFill.swift    mpcfill.com API client and decklist reader
  Render.swift     sheet plan, cutting, full-resolution render and preview
  Settings.swift   settings and translations
Tests/             decklist, sheet plan, double-sided, rotations, 300 DPI
Resources/         mask.png, layout backgrounds and JSON
AppIcon.icon       icon (Icon Composer document)
build.sh           builds the app and the icon
scripts/           development build
```

MPCFill is an open source project ([chilli-axe/mpc-autofill](https://github.com/chilli-axe/mpc-autofill)):
this app uses its public API, with no login.

## License

[MIT](LICENSE). The licence covers this app's code only: the card images come from MPCFill's sources and
from Wizards of the Coast, and none of them ship with the app.
