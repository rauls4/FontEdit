import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class Editor: ObservableObject {
    let defaultFont: [UInt8]
    let paletteBytes: [UInt8]
    @Published var project: AtariProject
    @Published var bank = 0
    @Published var code = 33
    @Published var pageIndex = 0
    @Published var ink: UInt8 = 1
    @Published var rewrite = true
    @Published var guides = true
    @Published var findDuplicates = false
    @Published var message = "Ready"
    @Published var history = 0
    @Published var saved: AtariProject
    var url: URL?
    private var undoStack: [AtariProject] = []
    private var redoStack: [AtariProject] = []
    private var beforeStroke: AtariProject?

    init() {
        func resource(_ name: String, _ ext: String) -> [UInt8] {
            guard let url = Bundle.main.url(forResource: name, withExtension: ext),
                  let data = try? Data(contentsOf: url) else {
                fatalError("Missing app resource: \(name).\(ext)")
            }
            return Array(data)
        }
        let font = resource("Default", "fnt")
        defaultFont = font
        paletteBytes = resource("Atari", "pal")
        let initial = AtariProject(defaultFont: font)
        project = initial
        saved = initial
    }

    lazy var atariPalette: [CGColor] = {
        let rgb = paletteBytes
        return stride(from: 0, to: rgb.count, by: 3).map { offset in
            let red = CGFloat(rgb[offset]) / 255
            let green = CGFloat(rgb[offset + 1]) / 255
            let blue = CGFloat(rgb[offset + 2]) / 255
            return CGColor(srgbRed: red, green: green, blue: blue, alpha: 1)
        }
    }()

    var page: ScreenPage { project.pages[pageIndex] }
    var glyph: [UInt8] { Array(project.glyph(bank: bank, code: code)) }
    var dirty: Bool { project != saved }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func color(_ value: UInt8, inverse: Bool = false) -> CGColor {
        let register = project.mode.register(value, inverse: inverse)
        return atariPalette[Int(project.colors[register])]
    }

    func registerColor(_ register: Int) -> Color {
        Color(cgColor: atariPalette[Int(project.colors[register])])
    }

    func change(_ label: String, _ action: (inout AtariProject) throws -> Void) {
        do {
            var edited = project
            try action(&edited)
            guard edited != project else { return }
            remember(project)
            project = edited
            clampSelection()
            message = label
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func remember(_ previous: AtariProject) {
        undoStack.append(previous)
        if undoStack.count > 128 { undoStack.removeFirst() }
        redoStack.removeAll()
        history += 1
    }

    private func clampSelection() {
        pageIndex = min(pageIndex, project.pages.count - 1)
        ink = min(ink, project.mode.mask)
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(project)
        pageIndex = min(pageIndex, previous.pages.count - 1)
        project = previous
        clampSelection()
        history += 1
        message = "Undid edit"
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(project)
        pageIndex = min(pageIndex, next.pages.count - 1)
        project = next
        clampSelection()
        history += 1
        message = "Redid edit"
    }

    func startStroke() { beforeStroke = project }

    func endStroke() {
        guard let previous = beforeStroke else { return }
        beforeStroke = nil
        if previous != project { remember(previous) }
    }

    func editPixel(x: Int, y: Int, value: UInt8) {
        let mode = project.mode
        var rows = glyph
        // The editor shows the inverse rendition, while the font stores the base glyph.
        rows[y] = mode.replacing(rows[y], x, with: value)
        project.setGlyph(bank: bank, code: code, rows: rows)
    }

    func setGlyph(_ rows: [UInt8], label: String) {
        change(label) { $0.setGlyph(bank: bank, code: code, rows: rows) }
    }

    func restoreGlyph() {
        let offset = (code & 127) * 8
        setGlyph(Array(defaultFont[offset..<offset + 8]), label: "Restored default glyph")
    }

    func restoreSavedGlyph() {
        setGlyph(Array(saved.glyph(bank: bank, code: code)), label: "Restored saved glyph")
    }

    func transform(_ operation: GlyphOperation) {
        let rows = glyph
        let mode = project.mode
        if operation == .invert {
            setGlyph(rows.map { ~$0 }, label: operation.title)
            return
        }
        var result = [UInt8](repeating: 0, count: 8)
        let width = mode.columns
        for y in 0..<8 {
            for x in 0..<width {
                let source: (Int, Int)
                switch operation {
                case .left: source = ((x + 1) % width, y)
                case .right: source = ((x + width - 1) % width, y)
                case .up: source = (x, (y + 1) % 8)
                case .down: source = (x, (y + 7) % 8)
                case .flipX: source = (width - 1 - x, y)
                case .flipY: source = (x, 7 - y)
                case .rotateLeft: source = (7 - y, x)
                case .rotateRight: source = (y, 7 - x)
                case .invert: return
                }
                if source.0 < width && source.1 < 8 {
                    result[y] = mode.replacing(result[y], x, with: mode.pixel(rows[source.1], source.0))
                }
            }
        }
        setGlyph(result, label: operation.title)
    }

    func copyGlyph() {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(hex(glyph), forType: .string)
        message = "Copied glyph bytes"
    }

    func pasteGlyph() {
        guard let value = NSPasteboard.general.string(forType: .string) else { return }
        let digits = Array(value.trimmingCharacters(in: .whitespacesAndNewlines))
        guard digits.count == 16 else { message = "Clipboard needs 16 hexadecimal digits"; return }
        let bytes = stride(from: 0, to: 16, by: 2).compactMap {
            UInt8(String(digits[$0...$0 + 1]), radix: 16)
        }
        if bytes.count == 8 { setGlyph(bytes, label: "Pasted glyph") }
    }

    func paintScreen(x: Int, y: Int, erase: Bool) {
        if erase {
            bank = Int(page.banks[y]) - 1
            code = Int(page.cells[y * page.width + x])
        } else {
            project.pages[pageIndex].cells[y * page.width + x] = UInt8(code)
        }
    }

    func cycleBank(row: Int, backwards: Bool) {
        change("Changed row font") {
            let old = $0.pages[pageIndex].banks[row]
            $0.pages[pageIndex].banks[row] = (old + (backwards ? 2 : 0)) % 4 + 1
        }
    }

    func addPage(duplicate: Bool) {
        var newPage = duplicate ? page : ScreenPage(width: page.width, height: page.height)
        let used = Set(project.pages.map(\.number))
        let number = (1...project.pages.count + 1).first { !used.contains($0) }!
        newPage.number = number
        newPage.name = "Page \(number)"
        change(duplicate ? "Duplicated page" : "Added page") { $0.pages.append(newPage) }
        pageIndex = project.pages.count - 1
    }

    func deletePage() {
        guard project.pages.count > 1 else { return }
        let index = pageIndex
        if pageIndex == project.pages.count - 1 { pageIndex -= 1 }
        change("Deleted page") { $0.pages.remove(at: index) }
    }

    func insertText(_ text: String, x: Int, y: Int) {
        var row = y
        var column = x
        change("Inserted text") {
            for char in text.utf8 {
                if char == 10 {
                    row += 1
                    column = x
                    continue
                }
                if column >= page.width {
                    row += 1
                    column = 0
                }
                guard row < page.height else { break }
                let code: UInt8
                switch char {
                case 32...95: code = char - 32
                case 96...126: code = char
                default: code = 31
                }
                $0.pages[pageIndex].cells[row * page.width + column] = code
                column += 1
            }
        }
    }

    func confirmDiscard() -> Bool {
        guard dirty else { return true }
        let alert = NSAlert()
        alert.messageText = "Save changes to this project?"
        alert.informativeText = "A project saves all font banks, pages and colors."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return saveProject()
        case .alertSecondButtonReturn: return true
        default: return false
        }
    }

    private func replaceProject(_ newProject: AtariProject, url: URL?) {
        pageIndex = 0
        project = newProject
        saved = newProject
        self.url = url
        undoStack.removeAll()
        redoStack.removeAll()
        beforeStroke = nil
        clampSelection()
        history += 1
    }

    func newProject() {
        guard confirmDiscard() else { return }
        replaceProject(AtariProject(defaultFont: defaultFont), url: nil)
        message = "New project"
    }

    func openProject() {
        guard let selected = openFile("Open Atari View", extensions: ["atrview", "vf2", "vfn"]) else { return }
        openProject(selected)
    }

    func openProject(_ selected: URL) {
        do {
            let data = try Data(contentsOf: selected)
            let ext = selected.pathExtension.lowercased()
            if ext == "vf2" || ext == "vfn" {
                var loaded = project
                try loaded.loadLegacyView(data, vf2: ext == "vf2", palette: paletteBytes)
                change("Imported legacy view") { $0 = loaded }
            } else {
                let loaded = try AtariProject(viewData: data)
                guard confirmDiscard() else { return }
                replaceProject(loaded, url: selected)
            }
            message = "Opened \(selected.lastPathComponent)"
        } catch { NSAlert(error: error).runModal() }
    }

    @discardableResult
    func saveProject(asNew: Bool = false) -> Bool {
        let destination = asNew ? nil : url
        guard let target = destination ?? saveFile("Save Atari View", filename: "Untitled.atrview")
        else { return false }
        do {
            try project.viewData(activePage: pageIndex).write(to: target, options: .atomic)
            saved = project
            url = target
            message = "Saved \(target.lastPathComponent)"
            return true
        } catch {
            NSAlert(error: error).runModal()
            return false
        }
    }

    func importFont() {
        guard let selected = openFile("Import Font into Bank \(bank + 1)") else { return }
        importFont(selected)
    }

    func importFont(_ selected: URL) {
        do {
            let data = try Data(contentsOf: selected)
            var imported = project
            try imported.loadFont(data, at: bank, name: selected.lastPathComponent)
            change("Imported \(selected.lastPathComponent)") { $0 = imported }
        } catch { NSAlert(error: error).runModal() }
    }

    func exportFont(count: Int = 1) {
        let start = count == 4 ? 0 : bank
        guard start + count <= 4 else { return }
        let name = count == 1 ? "Font \(bank + 1).fnt" : "Fonts.fnt"
        export(Data(project.fonts[start..<start + count].flatMap { $0 }), filename: name)
    }

    func exportSource(assembly: Bool) {
        let bytes = project.fonts[bank]
        let lines = stride(from: 0, to: bytes.count, by: 8).map { offset in
            let values = bytes[offset..<offset + 8].map {
                String(format: assembly ? "$%02X" : "0x%02X", Int($0))
            }.joined(separator: ", ")
            return assembly ? "    .byte " + values : "    " + values
        }
        let source = assembly ? "atari_font:\n" + lines.joined(separator: "\n") + "\n" :
            "static const unsigned char atari_font[1024] = {\n" +
            lines.joined(separator: ",\n") + "\n};\n"
        export(Data(source.utf8), filename: assembly ? "font.asm" : "font.h")
    }

    func importRaw() {
        guard let selected = openFile("Import Raw Screen") else { return }
        change("Imported raw screen") {
            let data = try Data(contentsOf: selected)
            guard data.count == page.cells.count else { throw FileProblem.rawSize }
            $0.pages[pageIndex].cells = Array(data)
        }
    }

    func export(_ data: Data, filename: String) {
        guard let target = saveFile("Export", filename: filename) else { return }
        do {
            try data.write(to: target, options: .atomic)
            message = "Exported \(target.lastPathComponent)"
        } catch { NSAlert(error: error).runModal() }
    }

    private func openFile(_ title: String, extensions: [String] = []) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.allowedContentTypes = extensions.compactMap { UTType(filenameExtension: $0) }
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func saveFile(_ title: String, filename: String) -> URL? {
        let panel = NSSavePanel()
        panel.title = title
        panel.nameFieldStringValue = filename
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }
}

enum GlyphOperation: String, CaseIterable {
    case left, right, up, down, flipX, flipY, rotateLeft, rotateRight, invert
    var title: String {
        switch self {
        case .left: return "Shift left"
        case .right: return "Shift right"
        case .up: return "Shift up"
        case .down: return "Shift down"
        case .flipX: return "Flip horizontally"
        case .flipY: return "Flip vertically"
        case .rotateLeft: return "Rotate left"
        case .rotateRight: return "Rotate right"
        case .invert: return "Invert bits"
        }
    }
    var icon: String {
        switch self {
        case .left: return "arrow.left"
        case .right: return "arrow.right"
        case .up: return "arrow.up"
        case .down: return "arrow.down"
        case .flipX: return "arrow.left.and.right"
        case .flipY: return "arrow.up.and.down"
        case .rotateLeft: return "rotate.left"
        case .rotateRight: return "rotate.right"
        case .invert: return "circle.lefthalf.filled"
        }
    }
}
