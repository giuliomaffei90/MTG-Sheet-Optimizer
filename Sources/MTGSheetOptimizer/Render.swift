import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Output is always 300 DPI: mask.png is 822x1122 px = 69.6x95 mm at 300 DPI.
let outputDPI = 300.0
let doubleSidedDirName = "Double Sided"
let singlesDirName = "Singles"

struct RenderError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

enum PageKind: String, CaseIterable {
    case A4, A3
    var slotCount: Int { self == .A4 ? 6 : 14 }
    var layoutPNG: String { "Layout \(rawValue).png" }
    var layoutJSON: String { "Layout\(rawValue).json" }
}

/// Card centre in page pixels; rotation in degrees clockwise, multiple of 45.
struct Slot: Hashable {
    var cx: Double
    var cy: Double
    var rot: Double
}

func snapAngle(_ deg: Double) -> Double {
    let r = ((deg / 45).rounded() * 45).truncatingRemainder(dividingBy: 360)
    return r < 0 ? r + 360 : r
}

func defaultSlots(_ kind: PageKind, width: Double, height: Double) -> [Slot] {
    let cols = kind == .A3 ? 7 : 3, rows = 2
    let mx = width * 0.06, my = height * 0.06
    let cw = (width - 2 * mx) / Double(cols), ch = (height - 2 * my) / Double(rows)
    return (0..<rows).flatMap { r in
        (0..<cols).map { c in Slot(cx: mx + (Double(c) + 0.5) * cw, cy: my + (Double(r) + 0.5) * ch, rot: 0) }
    }
}

/// Topmost slot whose card, rotated with the slot, contains `p`.
func slotAt(_ slots: [Slot], _ p: CGPoint, cardSize: CGSize) -> Int? {
    slots.indices.last { i in
        let s = slots[i], a = s.rot * .pi / 180
        let dx = p.x - s.cx, dy = p.y - s.cy
        // Undo the slot's clockwise rotation (y points down).
        let lx = dx * cos(a) + dy * sin(a), ly = -dx * sin(a) + dy * cos(a)
        return abs(lx) <= cardSize.width / 2 && abs(ly) <= cardSize.height / 2
    }
}

/// Spaces the cards at `indices` evenly, centre to centre, between the outermost two along `axis`.
func distribute(_ slots: inout [Slot], _ indices: [Int], along axis: WritableKeyPath<Slot, Double>) {
    let sorted = indices.sorted { slots[$0][keyPath: axis] < slots[$1][keyPath: axis] }
    guard sorted.count > 2, let first = sorted.first, let last = sorted.last else { return }
    let start = slots[first][keyPath: axis]
    let step = (slots[last][keyPath: axis] - start) / Double(sorted.count - 1)
    for (k, i) in sorted.enumerated() { slots[i][keyPath: axis] = start + Double(k) * step }
}

// MARK: - Layout JSON (same format as the Python tool; old "dpi"/"background"/"export_back_page" keys are ignored)

struct LayoutFile: Codable {
    struct NormalizedSlot: Codable {
        var cx: Double
        var cy: Double
        var rot: Double?
    }
    var layoutKind: String?
    var slots: [NormalizedSlot]

    init(kind: PageKind, slots: [Slot], width: Double, height: Double) {
        layoutKind = kind.rawValue
        self.slots = slots.map { NormalizedSlot(cx: $0.cx / width, cy: $0.cy / height, rot: snapAngle($0.rot)) }
    }

    static func load(_ url: URL) throws -> LayoutFile {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(LayoutFile.self, from: Data(contentsOf: url))
    }

    func save(_ url: URL) throws {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(self).write(to: url)
    }

    func pageSlots(width: Double, height: Double) -> [Slot] {
        slots.map { Slot(cx: $0.cx * width, cy: $0.cy * height, rot: snapAngle($0.rot ?? 0)) }
    }
}

// MARK: - Images

/// `maxPixelSize` decodes a small copy, much faster for previews.
func loadImage(_ url: URL, maxPixelSize: Int? = nil) throws -> CGImage {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { throw RenderError(tr("Can't read %@", url.lastPathComponent)) }
    let image = maxPixelSize.map {
        CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                                     kCGImageSourceThumbnailMaxPixelSize: $0] as CFDictionary)
    } ?? CGImageSourceCreateImageAtIndex(src, 0, nil)
    guard let image else { throw RenderError(tr("Can't read %@", url.lastPathComponent)) }
    return image
}

func makeContext(_ width: Int, _ height: Int) -> CGContext {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    return ctx
}

func savePNG(_ img: CGImage, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { throw RenderError(tr("Can't write %@", url.lastPathComponent)) }
    let props = [kCGImagePropertyDPIWidth: outputDPI, kCGImagePropertyDPIHeight: outputDPI] as CFDictionary
    CGImageDestinationAddImage(dest, img, props)
    guard CGImageDestinationFinalize(dest) else { throw RenderError(tr("Can't write %@", url.lastPathComponent)) }
}

struct Masker {
    let mask: CGImage
    var cardSize: CGSize { CGSize(width: mask.width, height: mask.height) }

    init(url: URL) throws { mask = try loadImage(url) }

    /// Card stretched to the mask size, alpha taken from the mask; `height` makes a small copy for previews.
    func card(_ url: URL, height: Int? = nil) throws -> CGImage {
        let h = height ?? mask.height
        let w = mask.width * h / mask.height
        let ctx = makeContext(w, h)
        let rect = CGRect(x: 0, y: 0, width: w, height: h)
        ctx.draw(try loadImage(url, maxPixelSize: height.map { $0 * 2 }), in: rect)
        ctx.setBlendMode(.destinationIn)
        ctx.draw(mask, in: rect)
        return ctx.makeImage()!
    }
}

/// Slots are in full-resolution top-left page coordinates; CoreGraphics is bottom-left, so y is flipped.
/// `scale` < 1 draws a smaller copy of the page.
func renderPage(width: Int, height: Int, scale: Double = 1, cardSize: CGSize, _ placements: [(CGImage, Slot)]) -> CGImage {
    let ctx = makeContext(max(1, Int(Double(width) * scale)), max(1, Int(Double(height) * scale)))
    ctx.scaleBy(x: scale, y: scale)
    for (img, slot) in placements {
        ctx.saveGState()
        ctx.translateBy(x: slot.cx.rounded(), y: Double(height) - slot.cy.rounded())
        ctx.rotate(by: -slot.rot * .pi / 180)
        ctx.draw(img, in: CGRect(x: -cardSize.width / 2, y: -cardSize.height / 2,
                                 width: cardSize.width, height: cardSize.height))
        ctx.restoreGState()
    }
    return ctx.makeImage()!
}

// MARK: - Sheet plan

/// One card to print; `back` is the other face of a double-faced card.
struct PrintCard: Hashable {
    var front: URL
    var back: URL? = nil
    var faces: [URL] { [front] + (back.map { [$0] } ?? []) }
}

enum ExtraCards: String, CaseIterable { case emptySlots, singles }
enum DoubleSidedMode: String, CaseIterable { case singles, duplex }

/// What sits in a slot: a card image, or the generic card back chosen in Settings.
enum PageItem: Hashable {
    case image(URL)
    case cardBack
}

struct PlannedPage {
    var name: String
    var isBack: Bool
    var items: [(PageItem, Slot)]
}

/// Every file an export writes, in print order. Rendering and the live preview both draw this.
struct SheetPlan {
    var pages: [PlannedPage] = []
    var singles: [URL] = []        // → Singles/
    var doubleSided: [URL] = []    // → Double Sided/
    var needsCardBack: Bool { pages.contains { page in page.items.contains { item, _ in item == .cardBack } } }
}

func planSheets(_ cards: [PrintCard], slots: [Slot], pageWidth: Double, kind: PageKind,
                extra: ExtraCards, doubleSided: DoubleSidedMode, backPage: Bool) -> SheetPlan {
    var plan = SheetPlan()
    let n = slots.count
    guard n > 0 else { return plan }
    let doubleFaced = cards.filter { $0.back != nil }
    var onPages = cards.filter { $0.back == nil }
    if doubleSided == .duplex {
        onPages = doubleFaced + onPages   // grouped first, so fewer sheets need a back page of their own
    } else {
        plan.doubleSided = doubleFaced.flatMap(\.faces)
    }

    // The sheet flips on its long edge: x is mirrored and every back turns the opposite way (90° → 270°),
    // so it's upright when the cut card is flipped.
    func behind(_ s: Slot) -> Slot { Slot(cx: pageWidth - s.cx, cy: s.cy, rot: snapAngle(-s.rot)) }
    var sheetsWithoutBack = false
    var number = 0
    for start in stride(from: 0, to: onPages.count, by: n) {
        let chunk = Array(onPages[start..<min(start + n, onPages.count)])
        if chunk.count < n && extra == .singles {
            plan.singles += chunk.flatMap(\.faces)
            continue
        }
        number += 1
        let name = "layout_\(kind.rawValue)_" + (chunk.count < n ? "LAST" : String(format: "%03d", number))
        plan.pages.append(PlannedPage(name: name + ".png", isBack: false,
                                      items: zip(chunk, slots).map { (.image($0.front), $1) }))
        if chunk.contains(where: { $0.back != nil }) {
            // Other slots get the generic back only when the back page is on.
            let backs: [(PageItem, Slot)] = zip(chunk, slots).compactMap { card, slot in
                if let back = card.back { return (.image(back), behind(slot)) }
                return backPage ? (.cardBack, behind(slot)) : nil
            }
            plan.pages.append(PlannedPage(name: name + "_back.png", isBack: true, items: backs))
        } else if backPage {
            sheetsWithoutBack = true
        }
    }
    if sheetsWithoutBack {
        // One back page serves every sheet without double-faced cards.
        plan.pages.insert(PlannedPage(name: "backpage_\(kind.rawValue).png", isBack: true,
                                      items: slots.map { (.cardBack, behind($0)) }), at: 0)
    }
    return plan
}

// MARK: - Rendering

struct RenderResult {
    var pages = 0, backPages = 0, singles = 0, doubleSided = 0

    func summary(_ kind: PageKind) -> String {
        var parts: [String] = []
        if pages > 0 { parts.append(tr("%@ pages: %d", kind.rawValue, pages)) }
        if backPages > 0 { parts.append(tr("Back pages: %d", backPages)) }
        if singles > 0 { parts.append(tr("Singles in '%@': %d", singlesDirName, singles)) }
        if doubleSided > 0 { parts.append(tr("Cut cards in '%@': %d", doubleSidedDirName, doubleSided)) }
        return tr("Done: %@.", parts.isEmpty ? tr("nothing to do") : parts.joined(separator: ", "))
    }
}

/// Repeated files (several copies of a card) get " 2", " 3"… so no copy overwrites another.
func exportSingles(_ files: [URL], to dir: URL, masker: Masker) throws -> Int {
    var seen: [String: Int] = [:]
    for f in files {
        let stem = f.deletingPathExtension().lastPathComponent
        seen[stem, default: 0] += 1
        let suffix = seen[stem]! > 1 ? " \(seen[stem]!)" : ""
        try savePNG(masker.card(f), to: dir.appendingPathComponent("\(stem)\(suffix)_alpha.png"))
    }
    return files.count
}

func renderPlan(_ plan: SheetPlan, width: Int, height: Int, output: URL, masker: Masker, back: URL?,
                progress: (String) -> Void = { _ in }) throws -> RenderResult {
    let cardBack = try back.map { try masker.card($0) }   // the same back sits on every back page: mask it once
    var result = RenderResult()
    for (i, page) in plan.pages.enumerated() {
        progress("\(i + 1)/\(plan.pages.count)")
        var placements: [(CGImage, Slot)] = []
        for (item, slot) in page.items {
            switch item {
            case .image(let url):
                placements.append((try masker.card(url), slot))
            case .cardBack:
                if let cardBack { placements.append((cardBack, slot)) }
            }
        }
        try savePNG(renderPage(width: width, height: height, cardSize: masker.cardSize, placements),
                    to: output.appendingPathComponent(page.name))
        if page.isBack { result.backPages += 1 } else { result.pages += 1 }
    }
    result.singles = try exportSingles(plan.singles, to: output.appendingPathComponent(singlesDirName), masker: masker)
    result.doubleSided = try exportSingles(plan.doubleSided, to: output.appendingPathComponent(doubleSidedDirName), masker: masker)
    return result
}

/// Small masked cards for the live preview, made once per image and size.
actor PreviewCache {
    static let shared = PreviewCache()
    private var cards: [String: CGImage] = [:]

    func card(_ url: URL, masker: Masker, height: Int) throws -> CGImage {
        let key = "\(height) \(url.path)"
        if let card = cards[key] { return card }
        let card = try masker.card(url, height: height)
        cards[key] = card
        return card
    }
}

/// Every planned page at `scale` of full size, for the live preview. Throws CancellationError when superseded.
func previewPages(_ plan: SheetPlan, width: Int, height: Int, scale: Double, masker: Masker, back: URL?) async throws -> [CGImage] {
    let cardHeight = max(1, Int(Double(masker.mask.height) * scale))
    var pages: [CGImage] = []
    for page in plan.pages {
        var placements: [(CGImage, Slot)] = []
        for (item, slot) in page.items {
            try Task.checkCancellation()
            let url: URL?
            switch item {
            case .image(let u): url = u
            case .cardBack: url = back
            }
            if let url { placements.append((try await PreviewCache.shared.card(url, masker: masker, height: cardHeight), slot)) }
        }
        pages.append(renderPage(width: width, height: height, scale: scale, cardSize: masker.cardSize, placements))
    }
    return pages
}
