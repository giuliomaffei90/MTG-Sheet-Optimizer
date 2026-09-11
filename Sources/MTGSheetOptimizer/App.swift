import SwiftUI
import AppKit

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
            RootView().frame(minWidth: 900, minHeight: 700)
        }
        Window(tr("Layout editor"), id: "layout-editor") {
            LayoutEditorView()
        }
        Settings { SettingsView() }
    }
}

enum Phase: CaseIterable {
    case deck, layout
    var title: String { self == .deck ? tr("1. Deck") : tr("2. Layout") }
}

struct RootView: View {
    @State private var phase = Phase.deck
    @State private var model = Model()
    @State private var deck = DeckModel()

    var body: some View {
        Group {
            switch phase {
            case .deck:
                DeckView(deck: deck) { cards in
                    model.cards = cards
                    phase = .layout
                }
            case .layout:
                OutputView(model: model)
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker(tr("Phase"), selection: $phase) {
                    ForEach(Phase.allCases, id: \.self) { Text($0.title) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
    }
}

// MARK: - Model

@MainActor @Observable
final class Model {
    var cards: [PrintCard] = []   // from phase 1, one per copy
    var status = ""
    var rendering = false
    var alertMessage: String?
    var finishedOutput: URL?

    func render(_ plan: SheetPlan, kind: PageKind, output: String) {
        guard let masker = LayoutStore.shared.masker, let size = LayoutStore.shared.size(kind) else {
            alertMessage = tr("Layout or mask.png missing")
            return
        }
        guard !output.isEmpty else { alertMessage = tr("Choose an output folder."); return }
        let backs = CardBacks.bundled
        let needsBack = plan.pages.contains { page in page.items.contains { item, _ in item == .cardBack } }
        guard !needsBack || backs.back != nil else { alertMessage = tr("Back page is on but back.jpg is missing."); return }

        let outputURL = URL(fileURLWithPath: output)
        rendering = true
        status = tr("Rendering…")
        Task.detached {
            do {
                let result = try renderPlan(plan, width: Int(size.width), height: Int(size.height), output: outputURL,
                                            masker: masker, backs: backs) { msg in
                    Task { @MainActor in self.status = msg }
                }
                await MainActor.run {
                    self.rendering = false
                    self.status = result.summary(kind)
                    self.finishedOutput = outputURL
                }
            } catch {
                await MainActor.run {
                    self.rendering = false
                    self.status = tr("Error.")
                    self.alertMessage = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Output phase

private struct PreviewKey: Hashable {
    var kind: PageKind
    var backPage: Bool
    var extra: ExtraCards
    var doubleSided: DoubleSidedMode
    var cards: [PrintCard]
    var slots: [Slot]
}

private struct PreviewPage: Identifiable {
    let name: String
    let image: CGImage
    var id: String { name }
}

struct OutputView: View {
    let model: Model
    @AppStorage("kind") private var kind = PageKind.A4
    @AppStorage("backPage") private var backPage = false
    @AppStorage("extraCards") private var extra = ExtraCards.emptySlots
    @AppStorage("doubleSided") private var doubleSided = DoubleSidedMode.singles
    @AppStorage("outputPath") private var outputPath = ""
    @State private var previews: [PreviewPage] = []

    private var store: LayoutStore { .shared }
    private var slots: [Slot] { store.slots[kind] ?? [] }
    private var plan: SheetPlan {
        planSheets(model.cards, slots: slots, pageWidth: Double(store.size(kind)?.width ?? 0), kind: kind,
                   extra: extra, doubleSided: doubleSided, backPage: backPage)
    }

    var body: some View {
        let plan = self.plan
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 16) {
                    Picker("Layout", selection: $kind) {
                        ForEach(PageKind.allCases, id: \.self) { Text($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                    Toggle(tr("Export back page"), isOn: $backPage)
                    Picker(tr("Extra cards"), selection: $extra) {
                        Text(tr("Last page with empty slots")).tag(ExtraCards.emptySlots)
                        Text(tr("As singles")).tag(ExtraCards.singles)
                    }
                    .fixedSize()
                    Picker(tr("Double-sided"), selection: $doubleSided) {
                        Text(tr("As singles")).tag(DoubleSidedMode.singles)
                        Text(tr("Front/back pages")).tag(DoubleSidedMode.duplex)
                    }
                    .fixedSize()
                    Spacer()
                }
                HStack {
                    Text("Output").frame(width: 50, alignment: .leading)
                    Text(outputPath.isEmpty ? "—" : outputPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(tr("Choose…")) { if let p = chooseFolder() { outputPath = p } }
                    Button(tr("Open output")) { NSWorkspace.shared.open(URL(fileURLWithPath: outputPath)) }
                        .disabled(outputPath.isEmpty)
                    Button("Render") { model.render(plan, kind: kind, output: outputPath) }
                        .disabled(model.rendering || model.cards.isEmpty)
                }
                Text(model.status).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(10)
            Divider()
            if model.cards.isEmpty {
                Text(tr("Search and download a deck in \"1. Deck\" first."))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    Text(tr("Sheets: %d · Back pages: %d · Singles: %d",
                            plan.pages.filter { !$0.isBack }.count, plan.pages.filter(\.isBack).count,
                            plan.singles.count + plan.doubleSided.count))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding([.horizontal, .top], 12)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 16)], spacing: 16) {
                        ForEach(previews) { page in
                            VStack(spacing: 4) {
                                Image(decorative: page.image, scale: 1)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .background(Color.white)
                                    .shadow(radius: 2)
                                Text(page.name).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                    .padding(12)
                }
            }
        }
        .task(id: PreviewKey(kind: kind, backPage: backPage, extra: extra, doubleSided: doubleSided,
                             cards: model.cards, slots: slots)) {
            await refreshPreview(plan)
        }
        .alert(tr("Done"),
               isPresented: Binding(get: { model.finishedOutput != nil }, set: { if !$0 { model.finishedOutput = nil } }),
               presenting: model.finishedOutput) { url in
            Button(tr("Open folder")) { NSWorkspace.shared.open(url) }
            Button(tr("Close"), role: .cancel) {}
        } message: { _ in
            Text(model.status)
        }
        .alert(tr("Error"),
               isPresented: Binding(get: { model.alertMessage != nil }, set: { if !$0 { model.alertMessage = nil } }),
               presenting: model.alertMessage) { _ in
            Button("OK", role: .cancel) {}
        } message: { Text($0) }
    }

    /// Low-resolution pages drawn from the same plan the export uses. A newer key cancels this run.
    private func refreshPreview(_ plan: SheetPlan) async {
        guard let masker = store.masker, let size = store.size(kind), !model.cards.isEmpty else {
            previews = []
            return
        }
        try? await Task.sleep(for: .milliseconds(120))   // coalesce slot drags from the layout editor
        guard !Task.isCancelled,
              let images = try? await previewPages(plan, width: Int(size.width), height: Int(size.height),
                                                   scale: 520 / size.height, masker: masker, backs: .bundled)
        else { return }
        previews = zip(plan.pages, images).map { PreviewPage(name: $0.name, image: $1) }
    }
}
