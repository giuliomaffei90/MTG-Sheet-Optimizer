import Testing
import Foundation
import CoreGraphics
import ImageIO
@testable import MTGSheetOptimizer

private let resources = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Resources")

@Test func snapping() {
    #expect(snapAngle(-45) == 315)
    #expect(snapAngle(100) == 90)
    #expect(snapAngle(360) == 0)
}

@Test func bundledLayoutsMatchSlotCounts() throws {
    for kind in PageKind.allCases {
        let file = try LayoutFile.load(resources.appendingPathComponent(kind.layoutJSON))
        #expect(file.slots.count == kind.slotCount)
        #expect(file.layoutKind == kind.rawValue)
    }
}

/// 7 synthetic cards (top half red, bottom half blue) on A4: 1 page + 1 single, back page, 300 DPI,
/// and 90° slots rotated clockwise like the Python tool.
@Test func renderA4() throws {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: tmp) }
    let input = tmp.appendingPathComponent("in"), output = tmp.appendingPathComponent("out")

    let card = makeContext(600, 820)   // CoreGraphics is y-up: y >= 410 is the top half
    card.setFillColor(red: 0, green: 0, blue: 1, alpha: 1)
    card.fill(CGRect(x: 0, y: 0, width: 600, height: 410))
    card.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
    card.fill(CGRect(x: 0, y: 410, width: 600, height: 410))
    for i in 1...7 { try savePNG(card.makeImage()!, to: input.appendingPathComponent("card\(i).png")) }

    let layout = try loadImage(resources.appendingPathComponent("Layout A4.png"))
    let slots = try LayoutFile.load(resources.appendingPathComponent("LayoutA4.json"))
        .pageSlots(width: Double(layout.width), height: Double(layout.height))
    let job = RenderJob(kind: .A4, slots: slots, pageWidth: layout.width, pageHeight: layout.height,
                        input: input, output: output,
                        back: resources.appendingPathComponent("back.jpg"),
                        back90: resources.appendingPathComponent("back90.jpg"),
                        remainder: .singles)
    let result = try renderAll(job, masker: Masker(url: resources.appendingPathComponent("mask.png")))
    #expect(result.pages == 1 && result.singles == 1 && result.backPage)
    #expect(FileManager.default.fileExists(atPath: output.appendingPathComponent("Singles/card7_alpha.png").path))

    let pageURL = output.appendingPathComponent("layout_A4_001.png")
    let src = try #require(CGImageSourceCreateWithURL(pageURL as CFURL, nil))
    let props = try #require(CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any])
    #expect((props[kCGImagePropertyDPIWidth] as? Double) == 300)

    // 450 px from the centre is inside the card along its long axis (half-length 525 px).
    let px = Pixels(try loadImage(pageURL))
    for s in slots {
        let rotated = s.rot.truncatingRemainder(dividingBy: 180) == 90
        let top = rotated ? px.at(s.cx + 450, s.cy) : px.at(s.cx, s.cy - 450)
        let bottom = rotated ? px.at(s.cx - 450, s.cy) : px.at(s.cx, s.cy + 450)
        #expect(top.a == 255 && top.r == 255 && top.b == 0)
        #expect(bottom.a == 255 && bottom.b == 255 && bottom.r == 0)
    }
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
