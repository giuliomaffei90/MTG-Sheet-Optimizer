import SwiftUI
import AppKit
import UniformTypeIdentifiers

let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("MTG Sheet Optimizer", isDirectory: true)

/// A copy in Application Support (saved layouts, custom backs) wins over the bundled default.
func resource(_ name: String) -> URL? {
    let user = supportDir.appendingPathComponent(name)
    if FileManager.default.fileExists(atPath: user.path) { return user }
    return Bundle.main.url(forResource: name, withExtension: nil)
}

func chooseFolder() -> String? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.canCreateDirectories = true
    return panel.runModal() == .OK ? panel.url?.path : nil
}

@main
struct MTGSheetOptimizerApp: App {
    var body: some Scene {
        WindowGroup("MTG Sheet Optimizer") {
            ContentView().frame(minWidth: 820, minHeight: 700)
        }
    }
}

// MARK: - Model

@MainActor @Observable
final class Model {
    var kind: PageKind = .A4
    var slots: [Slot] = []
    var selected: Int?
    var exportBack = false
    var layout: CGImage?
    var status = ""
    var rendering = false
    var inputPath = UserDefaults.standard.string(forKey: "inputPath") ?? "" {
        didSet { UserDefaults.standard.set(inputPath, forKey: "inputPath") }
    }
    var outputPath = UserDefaults.standard.string(forKey: "outputPath") ?? "" {
        didSet { UserDefaults.standard.set(outputPath, forKey: "outputPath") }
    }
    var pendingJob: RenderJob?   // waiting for the "last page" choice
    var missingSlots = 0
    var alertMessage: String?
    var finishedOutput: URL?
    let masker: Masker?
    private var loadedKind: PageKind?

    init() {
        masker = resource("mask.png").flatMap { try? Masker(url: $0) }
        loadKind(.A4)
        if masker == nil { status = "mask.png mancante o non valido." }
    }

    var pageWidth: Double { Double(layout?.width ?? 0) }
    var pageHeight: Double { Double(layout?.height ?? 0) }

    func loadKind(_ k: PageKind) {
        kind = k
        loadedKind = k
        layout = resource(k.layoutPNG).flatMap { try? loadImage($0) }
        slots = []
        selected = nil
        if let url = resource(k.layoutJSON), let file = try? LayoutFile.load(url) {
            apply(file)
            status = "\(url.lastPathComponent) caricato."
        }
        if slots.count != k.slotCount { resetSlots() }
    }

    func kindChanged() {
        if kind != loadedKind { loadKind(kind) }
    }

    func apply(_ file: LayoutFile) {
        slots = file.pageSlots(width: pageWidth, height: pageHeight)
        if let b = file.exportBackPage { exportBack = b }
    }

    func resetSlots() {
        slots = defaultSlots(kind, width: pageWidth, height: pageHeight)
        selected = nil
    }

    func saveLayout() {
        let url = supportDir.appendingPathComponent(kind.layoutJSON)
        do {
            try LayoutFile(kind: kind, exportBackPage: exportBack, slots: slots, width: pageWidth, height: pageHeight).save(url)
            status = "Salvato \(url.lastPathComponent)."
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func loadLayoutManually() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let file = try LayoutFile.load(url)
            loadKind(PageKind(rawValue: file.layoutKind ?? "") ?? kind)
            apply(file)
            if slots.count != kind.slotCount { resetSlots() }
            status = "Caricato \(url.lastPathComponent)."
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func rotateSelected(by deg: Double) {
        guard let i = selected else { return }
        slots[i].rot = snapAngle(slots[i].rot + deg)
    }

    func resetRotation() {
        guard let i = selected else { return }
        slots[i].rot = 0
    }

    func startRender() {
        guard masker != nil else { alertMessage = "mask.png mancante o non valido."; return }
        guard layout != nil else { alertMessage = "Non trovo \(kind.layoutPNG)."; return }
        guard !inputPath.isEmpty, !outputPath.isEmpty else { alertMessage = "Scegli la cartella di input e di output."; return }
        let input = URL(fileURLWithPath: inputPath)
        let cards = listImages(input)
        guard !cards.isEmpty || !listImages(input.appendingPathComponent(doubleSidedDirName)).isEmpty else {
            alertMessage = "Nessuna immagine valida in input."
            return
        }

        var job = RenderJob(kind: kind, slots: slots, pageWidth: Int(pageWidth), pageHeight: Int(pageHeight),
                            input: input, output: URL(fileURLWithPath: outputPath))
        if exportBack {
            guard let back = resource("back.jpg") else { alertMessage = "Retro attivo ma back.jpg non trovato."; return }
            job.back = back
            if slots.contains(where: { $0.rot.truncatingRemainder(dividingBy: 180) == 90 }) {
                guard let back90 = resource("back90.jpg") else {
                    alertMessage = "Retro attivo con carte a 90° ma back90.jpg non trovato."
                    return
                }
                job.back90 = back90
            }
        }

        let remainder = cards.count % slots.count
        if remainder > 0 {
            missingSlots = slots.count - remainder
            pendingJob = job
        } else {
            run(job)
        }
    }

    func run(_ job: RenderJob, remainder: RemainderAction = .onePage) {
        guard let masker else { return }
        var job = job
        job.remainder = remainder
        rendering = true
        status = "Render in corso..."
        Task.detached {
            do {
                let result = try renderAll(job, masker: masker) { msg in
                    Task { @MainActor in self.status = msg }
                }
                await MainActor.run {
                    self.rendering = false
                    self.status = result.summary(job.kind)
                    self.finishedOutput = job.output
                }
            } catch {
                await MainActor.run {
                    self.rendering = false
                    self.status = "Errore."
                    self.alertMessage = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Views

struct ContentView: View {
    @State private var model = Model()
    @State private var dragOrigin: Slot?

    var body: some View {
        VStack(spacing: 0) {
            controls
            canvas
        }
        .onChange(of: model.kind) { model.kindChanged() }
        .alert("Ultima pagina incompleta",
               isPresented: Binding(get: { model.pendingJob != nil }, set: { if !$0 { model.pendingJob = nil } }),
               presenting: model.pendingJob) { job in
            Button("Esporta singolarmente") { model.run(job, remainder: .singles) }
            Button("Esporta pagina con spazi vuoti") { model.run(job, remainder: .onePage) }
            Button("Annulla", role: .cancel) { model.status = "Annullato." }
        } message: { _ in
            Text("Nell'ultima pagina mancano \(model.missingSlots) carte. Cosa vuoi fare con le carte rimanenti?")
        }
        .alert("Completato",
               isPresented: Binding(get: { model.finishedOutput != nil }, set: { if !$0 { model.finishedOutput = nil } }),
               presenting: model.finishedOutput) { url in
            Button("Apri cartella") { NSWorkspace.shared.open(url) }
            Button("Chiudi", role: .cancel) {}
        } message: { _ in
            Text(model.status)
        }
        .alert("Errore",
               isPresented: Binding(get: { model.alertMessage != nil }, set: { if !$0 { model.alertMessage = nil } }),
               presenting: model.alertMessage) { _ in
            Button("OK", role: .cancel) {}
        } message: { Text($0) }
    }

    private var controls: some View {
        @Bindable var m = model
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("Layout", selection: $m.kind) {
                    ForEach(PageKind.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                Toggle("Esporta retro", isOn: $m.exportBack)
                Spacer()
                Button("Salva layout", action: model.saveLayout)
                Button("Carica layout…", action: model.loadLayoutManually)
                Button("Reimposta slot", action: model.resetSlots)
            }
            folderRow("Input", path: $m.inputPath)
            folderRow("Output", path: $m.outputPath)
            HStack {
                Button("Render") { model.startRender() }
                    .disabled(model.rendering)
                Button("Apri output") { NSWorkspace.shared.open(URL(fileURLWithPath: model.outputPath)) }
                    .disabled(model.outputPath.isEmpty)
                Divider().frame(height: 16)
                Group {
                    Button("↺ 45° (r)") { model.rotateSelected(by: -45) }
                        .keyboardShortcut("r", modifiers: [])
                    Button("↻ 45° (⇧R)") { model.rotateSelected(by: 45) }
                        .keyboardShortcut("r", modifiers: .shift)
                    Button("0° (⌫)") { model.resetRotation() }
                        .keyboardShortcut(.delete, modifiers: [])
                }
                .disabled(model.selected == nil)
                Text(model.status)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(10)
    }

    private func folderRow(_ label: String, path: Binding<String>) -> some View {
        HStack {
            Text(label).frame(width: 50, alignment: .leading)
            Text(path.wrappedValue.isEmpty ? "—" : path.wrappedValue)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Scegli…") {
                if let p = chooseFolder() { path.wrappedValue = p }
            }
        }
    }

    private var canvas: some View {
        GeometryReader { geo in
            if let layout = model.layout, let mask = model.masker?.mask {
                let W = CGFloat(layout.width), H = CGFloat(layout.height)
                let s = min(geo.size.width / W, geo.size.height / H)
                let ox = (geo.size.width - W * s) / 2, oy = (geo.size.height - H * s) / 2
                ZStack {
                    Image(decorative: layout, scale: 1)
                        .resizable()
                        .frame(width: W * s, height: H * s)
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    ForEach(Array(model.slots.enumerated()), id: \.offset) { i, slot in
                        let isSelected = model.selected == i
                        let color: Color = isSelected ? .cyan : .yellow
                        Image(decorative: mask, scale: 1)
                            .renderingMode(.template)
                            .resizable()
                            .foregroundStyle(color.opacity(isSelected ? 0.65 : 0.55))
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
                            if dragOrigin == nil {
                                let p = CGPoint(x: (g.startLocation.x - ox) / s, y: (g.startLocation.y - oy) / s)
                                model.selected = nearestSlot(model.slots, to: p)
                                dragOrigin = model.selected.map { model.slots[$0] }
                            }
                            guard let i = model.selected, let o = dragOrigin else { return }
                            model.slots[i].cx = min(max(o.cx + g.translation.width / s, 0), W)
                            model.slots[i].cy = min(max(o.cy + g.translation.height / s, 0), H)
                        }
                        .onEnded { _ in dragOrigin = nil }
                )
            } else {
                Text("Layout o mask.png mancanti")
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(white: 0.125))
    }
}
