import Testing
import Foundation
import CoreGraphics
import ImageIO
@testable import MTGSheetOptimizer

private let resources = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Resources")

private func url(_ name: String) -> URL { URL(fileURLWithPath: "/cards/\(name).png") }

@Test func snapping() {
    #expect(snapAngle(-45) == 315)
    #expect(snapAngle(100) == 90)
    #expect(snapAngle(360) == 0)
}

/// A 20×40 card at 90° is 40 wide and 20 tall on the page.
@Test func hitTestFollowsRotation() {
    let slots = [Slot(cx: 100, cy: 100, rot: 90)]
    let card = CGSize(width: 20, height: 40)
    #expect(slotAt(slots, CGPoint(x: 115, y: 100), cardSize: card) == 0)
    #expect(slotAt(slots, CGPoint(x: 100, y: 115), cardSize: card) == nil)
}

/// The outermost cards stay put, the ones in between get evenly spaced; unselected cards and the other axis don't move.
@Test func distributeSpacesCentresEvenly() {
    var slots = [Slot(cx: 0, cy: 5, rot: 0), Slot(cx: 90, cy: 7, rot: 0), Slot(cx: 10, cy: 9, rot: 0), Slot(cx: 500, cy: 0, rot: 0)]
    distribute(&slots, [0, 1, 2], along: \.cx)
    #expect(slots.map(\.cx) == [0, 90, 45, 500])
    #expect(slots.map(\.cy) == [5, 7, 9, 0])
}

@Test func bundledLayoutsMatchSlotCounts() throws {
    for kind in PageKind.allCases {
        let file = try LayoutFile.load(resources.appendingPathComponent(kind.layoutJSON))
        #expect(file.slots.count == kind.slotCount)
        #expect(file.layoutKind == kind.rawValue)
    }
}

/// Double-faced fronts go first. Without the back-page flag their sheet's back holds only their backs,
/// mirrored for a long-edge flip, and the other sheets get no back at all.
@Test func duplexWithoutBackPage() {
    let slots = [Slot(cx: 100, cy: 100, rot: 0), Slot(cx: 300, cy: 100, rot: 90)]
    let cards = [PrintCard(front: url("a")), PrintCard(front: url("f"), back: url("b")),
                 PrintCard(front: url("c")), PrintCard(front: url("d"))]
    let plan = planSheets(cards, slots: slots, pageWidth: 1000, kind: .A4, extra: .singles, doubleSided: .duplex, backPage: false)
    #expect(plan.pages.map(\.name) == ["layout_A4_001.png", "layout_A4_001_back.png", "layout_A4_002.png"])
    #expect(plan.pages[0].items.map { $0.0 } == [.image(url("f")), .image(url("a"))])
    #expect(plan.pages[1].items.map { $0.0 } == [.image(url("b"))])
    #expect(plan.pages[1].items.map { $0.1 } == [Slot(cx: 900, cy: 100, rot: 0)])
}

/// With the flag the other slots get the generic back, and sheets without double-faced cards share one
/// back page. A back on a 90° slot turns to 270°, so it's upright when the cut card is flipped.
@Test func duplexWithBackPage() {
    let slots = [Slot(cx: 100, cy: 100, rot: 90), Slot(cx: 300, cy: 100, rot: 0)]
    let cards = [PrintCard(front: url("a")), PrintCard(front: url("f"), back: url("b")), PrintCard(front: url("c"))]
    let plan = planSheets(cards, slots: slots, pageWidth: 1000, kind: .A3, extra: .emptySlots, doubleSided: .duplex, backPage: true)
    #expect(plan.pages.map(\.name) == ["backpage_A3.png", "layout_A3_001.png", "layout_A3_001_back.png", "layout_A3_LAST.png"])
    #expect(plan.pages[2].items.map { $0.0 } == [.image(url("b")), .cardBack])
    #expect(plan.pages[2].items.map { $0.1 } == [Slot(cx: 900, cy: 100, rot: 270), Slot(cx: 700, cy: 100, rot: 0)])
}

@Test func doubleSidedAsSingles() {
    let slots = [Slot(cx: 100, cy: 100, rot: 0), Slot(cx: 300, cy: 100, rot: 0)]
    let cards = [PrintCard(front: url("a")), PrintCard(front: url("f"), back: url("b")),
                 PrintCard(front: url("c")), PrintCard(front: url("d"))]
    let plan = planSheets(cards, slots: slots, pageWidth: 1000, kind: .A4, extra: .singles, doubleSided: .singles, backPage: false)
    #expect(plan.pages.map(\.name) == ["layout_A4_001.png"])
    #expect(plan.singles == [url("d")])
    #expect(plan.doubleSided == [url("f"), url("b")])
}

/// Full-resolution export with synthetic cards (top half red, bottom half blue): one double-faced card in
/// duplex plus 8 singles on A4. Checks 300 DPI, clockwise 90° slots like the Python tool, numbered singles,
/// and the double-faced back mirrored and turned the other way.
@Test func renderA4() throws {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: tmp) }
    let output = tmp.appendingPathComponent("out")

    let card = makeContext(600, 820)   // CoreGraphics is y-up: y >= 410 is the top half
    card.setFillColor(red: 0, green: 0, blue: 1, alpha: 1)
    card.fill(CGRect(x: 0, y: 0, width: 600, height: 410))
    card.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
    card.fill(CGRect(x: 0, y: 410, width: 600, height: 410))
    let files = (1...7).map { tmp.appendingPathComponent("in/card\($0).png") }
    for f in files { try savePNG(card.makeImage()!, to: f) }

    let layout = try loadImage(resources.appendingPathComponent("Layout A4.png"))
    let slots = try LayoutFile.load(resources.appendingPathComponent("LayoutA4.json"))
        .pageSlots(width: Double(layout.width), height: Double(layout.height))
    let cards = files.map { PrintCard(front: $0) } + [PrintCard(front: files[6]), PrintCard(front: files[0], back: files[1])]
    // Double-faced card first, then card1…5 fill the sheet; card6, card7, card7 are left over as singles.
    let plan = planSheets(cards, slots: slots, pageWidth: Double(layout.width), kind: .A4,
                          extra: .singles, doubleSided: .duplex, backPage: true)
    let result = try renderPlan(plan, width: layout.width, height: layout.height, output: output,
                                masker: Masker(url: resources.appendingPathComponent("mask.png")),
                                backs: CardBacks(back: resources.appendingPathComponent("back.jpg"),
                                                 back90: resources.appendingPathComponent("back90.jpg")))
    #expect(result.pages == 1 && result.backPages == 1 && result.singles == 3)
    for name in ["layout_A4_001_back.png", "Singles/card7_alpha.png", "Singles/card7 2_alpha.png"] {
        #expect(FileManager.default.fileExists(atPath: output.appendingPathComponent(name).path))
    }

    let pageURL = output.appendingPathComponent("layout_A4_001.png")
    let src = try #require(CGImageSourceCreateWithURL(pageURL as CFURL, nil))
    let props = try #require(CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any])
    #expect((props[kCGImagePropertyDPIWidth] as? Double) == 300)

    // 450 px from the centre is inside the card along its long axis (half-length 525 px).
    let front = Pixels(try loadImage(pageURL))
    for s in slots {
        let rotated = s.rot.truncatingRemainder(dividingBy: 180) == 90
        let top = rotated ? front.at(s.cx + 450, s.cy) : front.at(s.cx, s.cy - 450)
        let bottom = rotated ? front.at(s.cx - 450, s.cy) : front.at(s.cx, s.cy + 450)
        #expect(top.a == 255 && top.r == 255 && top.b == 0)
        #expect(bottom.a == 255 && bottom.b == 255 && bottom.r == 0)
    }

    // Slot 1 is at 90°: its double-faced back sits at the mirrored x, turned to 270° (top half on the left).
    let back = Pixels(try loadImage(output.appendingPathComponent("layout_A4_001_back.png")))
    let x = Double(layout.width) - slots[0].cx
    #expect(slots[0].rot == 90)
    #expect(back.at(x - 450, slots[0].cy).r == 255)
    #expect(back.at(x + 450, slots[0].cy).b == 255)
}

private struct Pixels {
    let ctx: CGContext
    init(_ img: CGImage) {
        ctx = makeContext(img.width, img.height)
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
    }
    /// Top-left page coordinates.
    func at(_ x: Double, _ y: Double) -> (r: UInt8, b: UInt8, a: UInt8) {
        let p = ctx.data!.assumingMemoryBound(to: UInt8.self) + Int(y) * ctx.bytesPerRow + Int(x) * 4
        return (p[0], p[2], p[3])
    }
}
