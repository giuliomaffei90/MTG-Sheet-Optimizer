import Foundation
import CoreGraphics
import ImageIO

/// Runs the shared cases in spec/ and prints what this implementation produced, so the Windows build can be
/// compared against it (see spec/spec.md). Triggered by `--conformance <specDir> [--out file.json]`.
enum Conformance {
    /// What this build implements, checked against spec/features.json by scripts/conformance-diff.py.
    static let features = ["decklist-parse", "mpcfill-search", "sheet-plan", "render-300dpi",
                           "deck-phase", "live-preview", "layout-editor", "card-back-picker", "language-switch"]

    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let flag = args.firstIndex(of: "--conformance"), flag + 1 < args.count else { return }
        let spec = URL(fileURLWithPath: args[flag + 1])
        let out = args.firstIndex(of: "--out").map { URL(fileURLWithPath: args[$0 + 1]) }
        do {
            let failures = try run(spec: spec, out: out)
            exit(failures == 0 ? 0 : 1)
        } catch {
            FileHandle.standardError.write("conformance: \(error.localizedDescription)\n".data(using: .utf8)!)
            exit(2)
        }
    }

    private static func round4(_ v: Double) -> Double { (v * 10000).rounded() / 10000 }

    private static func id(_ item: PageItem) -> String {
        switch item {
        case .cardBack: return "$back"
        case .image(let url): return url.deletingPathExtension().lastPathComponent
        }
    }

    private static func json(_ plan: SheetPlan) -> [String: Any] {
        ["pages": plan.pages.map { page -> [String: Any] in
            ["name": page.name, "isBack": page.isBack,
             "items": page.items.map { [id($0.0), round4($0.1.cx), round4($0.1.cy), round4($0.1.rot)] as [Any] }]
        },
         "singles": plan.singles.map { $0.deletingPathExtension().lastPathComponent },
         "doubleSided": plan.doubleSided.map { $0.deletingPathExtension().lastPathComponent }]
    }

    /// Alpha bounding box of a page holding one card only: the geometry two graphics engines can agree on.
    private static func box(_ image: CGImage) -> [Int] {
        let ctx = makeContext(image.width, image.height)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let data = ctx.data!.assumingMemoryBound(to: UInt8.self)
        var minX = image.width, minY = image.height, maxX = -1, maxY = -1
        for y in 0..<image.height {
            for x in 0..<image.width where data[y * ctx.bytesPerRow + x * 4 + 3] > 8 {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        return maxX < 0 ? [0, 0, 0, 0] : [minX, minY, maxX - minX + 1, maxY - minY + 1]
    }

    private static func run(spec: URL, out: URL?) throws -> Int {
        let masker = try Masker(url: spec.appendingPathComponent("Resources/mask.png"))
        let fixtures = spec.appendingPathComponent("fixtures")
        let caseFiles = try FileManager.default.contentsOfDirectory(at: spec.appendingPathComponent("cases"),
                                                                    includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        var cases: [String: Any] = [:]
        var failures = 0

        for file in caseFiles {
            let c = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
            let name = c["name"] as! String
            let width = c["pageWidth"] as! Double, height = c["pageHeight"] as! Double
            let slots = (c["slots"] as! [[Double]]).map { Slot(cx: $0[0], cy: $0[1], rot: $0[2]) }
            let url = { (id: String) in fixtures.appendingPathComponent("\(id).png") }
            let cards = (c["cards"] as! [[String]]).map { PrintCard(front: url($0[0]), back: $0.count > 1 ? url($0[1]) : nil) }
            let plan = planSheets(cards, slots: slots, pageWidth: width, kind: PageKind(rawValue: c["kind"] as! String)!,
                                  extra: ExtraCards(rawValue: c["extra"] as! String)!,
                                  doubleSided: DoubleSidedMode(rawValue: c["doubleSided"] as! String)!,
                                  backPage: c["backPage"] as! Bool)
            var result: [String: Any] = ["plan": json(plan)]
            let expected = c["expected"] as? [String: Any] ?? [:]

            if c["render"] as? Bool == true {
                var geometry: [String: [[Int]]] = [:]
                var firstPage: CGImage?
                for page in plan.pages {
                    geometry[page.name] = try page.items.map { item, slot in
                        let image = try masker.card(url(id(item) == "$back" ? "back" : id(item)))
                        let sheet = renderPage(width: Int(width), height: Int(height),
                                               cardSize: masker.cardSize, [(image, slot)])
                        if firstPage == nil { firstPage = sheet }
                        return box(sheet)
                    }
                }
                result["geometry"] = geometry
                result["dpi"] = try firstPage.map(writtenDPI) ?? NSNull()
                if let want = expected["geometry"] as? [String: [[Int]]], !want.isEmpty {
                    for (page, boxes) in want where geometry[page].map({ !close($0, boxes) }) ?? true {
                        print("✘ \(name): geometry differs on \(page)")
                        failures += 1
                    }
                }
            }
            if let pages = expected["pages"], !((pages as? [Any])?.isEmpty ?? true) {
                let want: [String: Any] = ["pages": pages, "singles": expected["singles"] ?? [],
                                           "doubleSided": expected["doubleSided"] ?? []]
                if !(result["plan"] as! NSDictionary).isEqual(to: want) {
                    print("✘ \(name): plan differs from spec")
                    failures += 1
                }
            }
            cases[name] = result
        }

        let document: [String: Any] = ["implementation": "macos-swift", "features": features, "cases": cases]
        let data = try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys])
        if let out {
            try FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: out)
        } else {
            FileHandle.standardOutput.write(data)
        }
        print(failures == 0 ? "✔ \(caseFiles.count) cases match the spec" : "✘ \(failures) mismatches")
        return failures
    }

    /// The DPI a saved page really carries, so the 300 DPI promise is machine-checked on both platforms.
    private static func writtenDPI(_ page: CGImage) throws -> Int {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("conformance-\(UUID().uuidString).png")
        try savePNG(page, to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let source = CGImageSourceCreateWithURL(file as CFURL, nil)
        let properties = source.flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] }
        return Int(properties?[kCGImagePropertyDPIWidth] as? Double ?? 0)
    }

    /// Two graphics engines never place a pixel identically; 2 px is the agreed tolerance.
    private static func close(_ a: [[Int]], _ b: [[Int]]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { zip($0, $1).allSatisfy { abs($0 - $1) <= 2 } }
    }
}
