import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Output is always 300 DPI: mask.png is 822x1122 px = 69.6x95 mm at 300 DPI.
let outputDPI = 300.0
let validExtensions: Set<String> = ["png", "jpg", "jpeg", "tif", "tiff", "webp"]
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
struct Slot: Equatable {
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

func nearestSlot(_ slots: [Slot], to p: CGPoint) -> Int? {
    slots.indices.min { a, b in
        hypot(slots[a].cx - p.x, slots[a].cy - p.y) < hypot(slots[b].cx - p.x, slots[b].cy - p.y)
    }
}

// MARK: - Layout JSON (same format as the Python tool; old "dpi"/"background" keys are ignored)

struct LayoutFile: Codable {
    struct NormalizedSlot: Codable {
        var cx: Double
        var cy: Double
        var rot: Double?
    }
    var layoutKind: String?
    var exportBackPage: Bool?
    var slots: [NormalizedSlot]

    init(kind: PageKind, exportBackPage: Bool, slots: [Slot], width: Double, height: Double) {
        layoutKind = kind.rawValue
        self.exportBackPage = exportBackPage
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

func loadImage(_ url: URL) throws -> CGImage {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let img = CGImageSourceCreateImageAtIndex(src, 0, nil)
    else { throw RenderError(tr("Can't read %@", url.lastPathComponent)) }
    return img
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

    init(url: URL) throws { mask = try loadImage(url) }

    /// Card stretched to the mask size, alpha taken from the mask.
    func card(_ url: URL) throws -> CGImage {
        let ctx = makeContext(mask.width, mask.height)
        let rect = CGRect(x: 0, y: 0, width: mask.width, height: mask.height)
        ctx.draw(try loadImage(url), in: rect)
        ctx.setBlendMode(.destinationIn)
        ctx.draw(mask, in: rect)
        return ctx.makeImage()!
    }
}

/// Slots are in top-left page coordinates; CoreGraphics is bottom-left, so y is flipped here.
func renderPage(width: Int, height: Int, _ placements: [(CGImage, Slot)]) -> CGImage {
    let ctx = makeContext(width, height)
    for (img, slot) in placements {
        ctx.saveGState()
        ctx.translateBy(x: slot.cx.rounded(), y: Double(height) - slot.cy.rounded())
        ctx.rotate(by: -slot.rot * .pi / 180)
        ctx.draw(img, in: CGRect(x: -Double(img.width) / 2, y: -Double(img.height) / 2,
                                 width: Double(img.width), height: Double(img.height)))
        ctx.restoreGState()
    }
    return ctx.makeImage()!
}

func listImages(_ dir: URL) -> [URL] {
    let items = (try? FileManager.default.contentsOfDirectory(
        at: dir, includingPropertiesForKeys: [.isRegularFileKey], options: .skipsHiddenFiles)) ?? []
    return items
        .filter { validExtensions.contains($0.pathExtension.lowercased()) }
        .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
        .sorted { $0.lastPathComponent.lowercased() < $1.lastPathComponent.lowercased() }
}

// MARK: - Render job

enum RemainderAction { case singles, onePage }

struct RenderJob {
    var kind: PageKind
    var slots: [Slot]
    var pageWidth: Int
    var pageHeight: Int
    var cards: [URL]          // one entry per copy, placed on pages in order
    var doubleSided: [URL]    // exported as singles only
    var output: URL
    var back: URL? = nil
    var back90: URL? = nil
    var remainder: RemainderAction = .onePage
}

struct RenderResult {
    var pages = 0, singles = 0, doubleSided = 0
    var lastPage = false, backPage = false

    func summary(_ kind: PageKind) -> String {
        var parts: [String] = []
        if pages > 0 { parts.append(tr("%d %@ pages", pages, kind.rawValue)) }
        if lastPage { parts.append(tr("1 last page with empty slots")) }
        if singles > 0 { parts.append(tr("%d singles in '%@'", singles, singlesDirName)) }
        if doubleSided > 0 { parts.append(tr("%d cut cards in '%@'", doubleSided, doubleSidedDirName)) }
        if backPage { parts.append(tr("1 %@ back page", kind.rawValue)) }
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

func renderAll(_ job: RenderJob, masker: Masker, progress: (String) -> Void = { _ in }) throws -> RenderResult {
    var result = RenderResult()
    let n = job.slots.count
    let cards = job.cards
    let kind = job.kind.rawValue

    func page(_ files: [URL], _ name: String) throws {
        let placements = try zip(files, job.slots).map { (try masker.card($0), $1) }
        try savePNG(renderPage(width: job.pageWidth, height: job.pageHeight, placements),
                    to: job.output.appendingPathComponent(name))
    }

    // Back page: slots mirrored horizontally for duplex; 90° slots use the 180°-flipped back.
    if let backURL = job.back {
        let back = try masker.card(backURL)
        let back90 = try job.back90.map(masker.card) ?? back
        let placements = job.slots.map { s in
            (s.rot.truncatingRemainder(dividingBy: 180) == 90 ? back90 : back,
             Slot(cx: Double(job.pageWidth) - s.cx, cy: s.cy, rot: s.rot))
        }
        try savePNG(renderPage(width: job.pageWidth, height: job.pageHeight, placements),
                    to: job.output.appendingPathComponent("backpage_\(kind).png"))
        result.backPage = true
    }

    let fullPages = cards.count / n
    for start in stride(from: 0, to: cards.count, by: n) {
        let chunk = Array(cards[start..<min(start + n, cards.count)])
        if chunk.count == n {
            result.pages += 1
            progress("Layout \(result.pages)/\(fullPages)")
            try page(chunk, "layout_\(kind)_\(String(format: "%03d", result.pages)).png")
        } else if job.remainder == .onePage {
            try page(chunk, "layout_\(kind)_LAST.png")
            result.lastPage = true
        } else {
            result.singles = try exportSingles(chunk, to: job.output.appendingPathComponent(singlesDirName), masker: masker)
        }
    }

    if !job.doubleSided.isEmpty {
        result.doubleSided = try exportSingles(job.doubleSided, to: job.output.appendingPathComponent(doubleSidedDirName), masker: masker)
    }
    return result
}
