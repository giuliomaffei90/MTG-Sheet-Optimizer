import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// The two page layouts: background image and card slots. Edited in the layout editor, saved on every change,
/// read by the output phase (so its preview follows the editor live).
@MainActor @Observable
final class LayoutStore {
    static let shared = LayoutStore()
    let masker: Masker? = resource("mask.png").flatMap { try? Masker(url: $0) }
    private(set) var images: [PageKind: CGImage] = [:]
    var slots: [PageKind: [Slot]] = [:]

    private init() {
        for kind in PageKind.allCases {
            images[kind] = resource(kind.layoutPNG).flatMap { try? loadImage($0) }
            let size = self.size(kind) ?? .zero
            let saved = resource(kind.layoutJSON).flatMap { try? LayoutFile.load($0) }?
                .pageSlots(width: size.width, height: size.height)
            slots[kind] = saved?.count == kind.slotCount ? saved : defaultSlots(kind, width: size.width, height: size.height)
        }
    }

    func size(_ kind: PageKind) -> CGSize? {
        images[kind].map { CGSize(width: $0.width, height: $0.height) }
    }

    func save(_ kind: PageKind) throws {
        let size = self.size(kind) ?? .zero
        try LayoutFile(kind: kind, slots: slots[kind] ?? [], width: size.width, height: size.height)
            .save(supportDir.appendingPathComponent(kind.layoutJSON))
    }

    func reset(_ kind: PageKind) throws {
        let size = self.size(kind) ?? .zero
        slots[kind] = defaultSlots(kind, width: size.width, height: size.height)
        try save(kind)
    }
}

struct LayoutEditorView: View {
    @State private var kind = PageKind.A4
    @State private var selection: [Int] = []          // click order: the first one is the alignment reference
    @State private var dragging = false
    @State private var pressed: Int?
    @State private var dragOrigins: [Int: Slot] = [:]
    @State private var error: String?
    @FocusState private var canvasFocused: Bool
    private let store = LayoutStore.shared

    private var slots: [Slot] { store.slots[kind] ?? [] }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Layout", selection: $kind) {
                    ForEach(PageKind.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                Divider().frame(height: 16)
                Group {
                    Button("↺ 45° (r)") { edit { $0.rot = snapAngle($0.rot - 45) } }
                        .keyboardShortcut("r", modifiers: [])
                    Button("↻ 45° (⇧R)") { edit { $0.rot = snapAngle($0.rot + 45) } }
                        .keyboardShortcut("r", modifiers: .shift)
                    Button("0° (⌫)") { edit { $0.rot = 0 } }
                        .keyboardShortcut(.delete, modifiers: [])
                }
                .disabled(selection.isEmpty)
                Divider().frame(height: 16)
                Group {
                    Button { align(\.cy) } label: {
                        Label(tr("Align horizontally"), systemImage: "align.vertical.center")
                    }
                    .help(tr("Puts the selected cards on the same row as the first one you selected."))
                    Button { align(\.cx) } label: {
                        Label(tr("Align vertically"), systemImage: "align.horizontal.center")
                    }
                    .help(tr("Puts the selected cards in the same column as the first one you selected."))
                }
                .labelStyle(.iconOnly)
                .disabled(selection.count < 2)
                Group {
                    Button { spread(along: \.cx) } label: {
                        Label(tr("Distribute horizontally"), systemImage: "distribute.horizontal.center")
                    }
                    .help(tr("Spaces the selected cards evenly from left to right."))
                    Button { spread(along: \.cy) } label: {
                        Label(tr("Distribute vertically"), systemImage: "distribute.vertical.center")
                    }
                    .help(tr("Spaces the selected cards evenly from top to bottom."))
                }
                .labelStyle(.iconOnly)
                .disabled(selection.count < 3)
                Spacer()
                Button(tr("Load layout…"), action: importLayout)
                Button(tr("Reset slots")) {
                    selection = []
                    persist { try store.reset(kind) }
                }
            }
            .padding(10)
            canvas
        }
        .frame(minWidth: 760, minHeight: 700)
        .onChange(of: kind) { selection = [] }
        .alert(tr("Error"),
               isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } }),
               presenting: error) { _ in
            Button("OK", role: .cancel) {}
        } message: { Text($0) }
    }

    private func persist(_ change: () throws -> Void) {
        do { try change() } catch { self.error = error.localizedDescription }
    }

    /// Applies `change` to every selected slot and saves.
    private func edit(_ change: (inout Slot) -> Void) {
        for i in selection { change(&store.slots[kind, default: []][i]) }
        persist { try store.save(kind) }
    }

    private func align(_ axis: WritableKeyPath<Slot, Double>) {
        guard let first = selection.first else { return }
        let value = slots[first][keyPath: axis]
        edit { $0[keyPath: axis] = value }
    }

    private func spread(along axis: WritableKeyPath<Slot, Double>) {
        distribute(&store.slots[kind, default: []], selection, along: axis)
        persist { try store.save(kind) }
    }

    private func importLayout() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        persist {
            let file = try LayoutFile.load(url)
            if let k = file.layoutKind.flatMap(PageKind.init(rawValue:)) { kind = k }
            let size = store.size(kind) ?? .zero
            let slots = file.pageSlots(width: size.width, height: size.height)
            guard slots.count == kind.slotCount else { throw RenderError(tr("Wrong number of slots for %@.", kind.rawValue)) }
            store.slots[kind] = slots
            selection = []
            try store.save(kind)
        }
    }

    /// Click selects the card under the pointer (⇧ adds or removes it), empty space clears the selection,
    /// dragging moves every selected card.
    private func press(at p: CGPoint) {
        let hit = slotAt(slots, p, cardSize: store.masker?.cardSize ?? .zero)
        let shift = NSEvent.modifierFlags.contains(.shift)
        if let hit {
            if shift {
                if let k = selection.firstIndex(of: hit) { selection.remove(at: k) } else { selection.append(hit) }
            } else if !selection.contains(hit) {
                selection = [hit]
            }
        } else if !shift {
            selection = []
        }
        pressed = hit
        let dragsSelection = hit.map(selection.contains) ?? false
        dragOrigins = dragsSelection ? Dictionary(uniqueKeysWithValues: selection.map { ($0, slots[$0]) }) : [:]
    }

    private var canvas: some View {
        GeometryReader { geo in
            if let layout = store.images[kind], let mask = store.masker?.mask {
                let W = CGFloat(layout.width), H = CGFloat(layout.height)
                let s = min(geo.size.width / W, geo.size.height / H)
                let ox = (geo.size.width - W * s) / 2, oy = (geo.size.height - H * s) / 2
                ZStack {
                    Image(decorative: layout, scale: 1)
                        .resizable()
                        .frame(width: W * s, height: H * s)
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    ForEach(Array(slots.enumerated()), id: \.offset) { i, slot in
                        let isSelected = selection.contains(i)
                        let isReference = selection.first == i && selection.count > 1
                        Image(decorative: mask, scale: 1)
                            .renderingMode(.template)
                            .resizable()
                            .foregroundStyle((isSelected ? Color.cyan : Color.yellow).opacity(isReference ? 0.85 : 0.55))
                            .frame(width: CGFloat(mask.width) * s, height: CGFloat(mask.height) * s)
                            .rotationEffect(.degrees(slot.rot))
                            .position(x: ox + slot.cx * s, y: oy + slot.cy * s)
                        Text("\(i + 1)")
                            .font(.title2.bold())
                            .foregroundStyle(isSelected ? Color.black : Color.black.opacity(0.7))
                            .position(x: ox + slot.cx * s, y: oy + slot.cy * s)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            if !dragging {
                                dragging = true
                                canvasFocused = true
                                press(at: CGPoint(x: (g.startLocation.x - ox) / s, y: (g.startLocation.y - oy) / s))
                            }
                            for (i, o) in dragOrigins {
                                store.slots[kind, default: []][i].cx = min(max(o.cx + g.translation.width / s, 0), W)
                                store.slots[kind, default: []][i].cy = min(max(o.cy + g.translation.height / s, 0), H)
                            }
                        }
                        .onEnded { g in
                            let moved = g.translation != .zero
                            // A plain click on a card of a group narrows the selection to that card.
                            if !moved, let p = pressed, !NSEvent.modifierFlags.contains(.shift) { selection = [p] }
                            if moved && !dragOrigins.isEmpty { persist { try store.save(kind) } }
                            dragging = false
                            pressed = nil
                            dragOrigins = [:]
                        }
                )
            } else {
                Text(tr("Layout or mask.png missing"))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(white: 0.125))
        .focusable()
        .focusEffectDisabled()
        .focused($canvasFocused)
        .onAppear { canvasFocused = true }
        // Arrows nudge the selection 1 px (⇧: 10 px); holding the key repeats.
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow], phases: [.down, .repeat]) { key in
            guard !selection.isEmpty else { return .ignored }
            let step = key.modifiers.contains(.shift) ? 10.0 : 1.0
            switch key.key {
            case .leftArrow: edit { $0.cx -= step }
            case .rightArrow: edit { $0.cx += step }
            case .upArrow: edit { $0.cy -= step }
            default: edit { $0.cy += step }
            }
            return .handled
        }
        .onKeyPress(.escape) {
            selection = []
            return .handled
        }
    }
}
