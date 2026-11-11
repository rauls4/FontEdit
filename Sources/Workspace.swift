import SwiftUI

struct Workspace: View {
    @ObservedObject var editor: Editor
    @StateObject private var state = WorkspaceState()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 14) {
                    glyphPanel
                    bankPanel
                }
                .frame(width: 294)
                screenPanel
            }
            .padding(16)
            Divider()
            statusBar
        }
        .background(Color.workspaceBackground)
        .sheet(isPresented: $state.pageDialog) { pageSheet }
        .sheet(isPresented: $state.textDialog) { textSheet }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.grid.3x3.fill")
                .font(.title2).foregroundStyle(Color.atariGreen)
                .frame(width: 38, height: 38)
                .background(Color.atariGreen.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text("FontEdit").font(.system(size: 20, weight: .semibold))
                Text(editor.url?.lastPathComponent ?? "Untitled.atrview")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button("Open View", systemImage: "folder", action: editor.openProject)
            Button("Import Font", systemImage: "square.and.arrow.down", action: editor.importFont)
            Menu("Export") { ExportItems(editor: editor) }.fixedSize()
            Button("Save Project", systemImage: "square.and.arrow.up") { editor.saveProject() }
                .buttonStyle(.borderedProminent)
                .foregroundStyle(.black)
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
    }

    private var glyphPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionTitle("Glyph Editor")
                Spacer()
                Text(String(format: "$%02X", editor.code))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.atariGreen)
                Button { editor.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                    .disabled(!editor.canUndo).help("Undo")
                Button { editor.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                    .disabled(!editor.canRedo).help("Redo")
            }
            HStack {
                Picker("Mode", selection: Binding(get: { editor.project.mode }, set: { mode in
                    editor.change("Switched to \(mode.title)") { $0.mode = mode }
                })) {
                    ForEach(GraphicsMode.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden().frame(width: 106)
                Spacer()
                Toggle("Grid", isOn: $editor.guides).toggleStyle(.checkbox)
            }
            HStack(alignment: .center, spacing: 10) {
                PixelCanvas(editor: editor, kind: .glyph)
                    .frame(width: 176, height: 176)
                    .border(Color.panelBorder)
                VStack(spacing: 5) {
                    ForEach(0..<3) { row in
                        HStack(spacing: 4) {
                            ForEach(GlyphOperation.allCases[row * 3..<row * 3 + 3], id: \.self) { operation in
                                Button {
                                    editor.transform(operation)
                                } label: {
                                    Image(systemName: operation.icon).frame(width: 13)
                                }
                                .disabled(editor.project.mode != .text && operation.isRotation)
                                .help(operation.title)
                                .accessibilityLabel(operation.title)
                            }
                        }
                    }
                    Menu {
                        Button("Copy Glyph Bytes", action: editor.copyGlyph)
                        Button("Paste Glyph Bytes", action: editor.pasteGlyph)
                        Divider()
                        Button("Restore Default", action: editor.restoreGlyph)
                        Button("Restore Saved", action: editor.restoreSavedGlyph)
                        Button("Clear") {
                            editor.setGlyph(Array(repeating: 0, count: 8), label: "Cleared glyph")
                        }
                    } label: { Image(systemName: "ellipsis.circle") }
                    .help("Glyph actions")
                }
            }
            HStack(spacing: editor.project.mode == .mode10 ? 2 : 6) {
                ForEach(0..<inkCount, id: \.self) { value in
                    Button { editor.ink = UInt8(value) } label: {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(cgColor: editor.color(UInt8(value), inverse: editor.code >= 128)))
                            .frame(width: editor.project.mode == .mode10 ? 10 : 16, height: 16)
                            .overlay {
                                RoundedRectangle(cornerRadius: 3)
                                    .stroke(editor.ink == UInt8(value) ? Color.atariGreen : .panelBorder,
                                            lineWidth: editor.ink == UInt8(value) ? 2 : 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .help("Select pixel value \(value)")
                    .accessibilityLabel("Pixel value \(value)")
                }
                Spacer(minLength: 4)
                Menu {
                    Button("Rewrite") { editor.rewrite = true }
                    Button("Insert") { editor.rewrite = false }
                } label: { Text(editor.rewrite ? "Rewrite" : "Insert") }
                .fixedSize()
                .help("Drawing mode")
            }
        }
        .panel()
    }

    private var inkCount: Int {
        editor.project.mode == .mode10 ? 16 : Int(editor.project.mode.mask) + 1
    }

    private var bankPanel: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                sectionTitle("Font Banks")
                Spacer()
                Picker("Bank", selection: $editor.bank) {
                    ForEach(0..<4) { Text("\($0 + 1)").tag($0) }
                }
                .labelsHidden().pickerStyle(.segmented).frame(width: 112)
                Menu {
                    Button("Import into This Bank…", action: editor.importFont)
                    Button("Export This Bank…") { editor.exportFont() }
                    Divider()
                    Button("Restore Default Font") {
                        editor.change("Restored font bank") {
                            $0.fonts[editor.bank] = editor.defaultFont
                            $0.names[editor.bank] = "Default.fnt"
                        }
                    }
                    Button("Clear Font") {
                        editor.change("Cleared font bank") {
                            $0.fonts[editor.bank] = Array(repeating: 0, count: 1024)
                        }
                    }
                } label: { Image(systemName: "ellipsis.circle") }
                .fixedSize()
            }
            Text(editor.project.names[editor.bank])
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                .lineLimit(1)
            GeometryReader { proxy in
                let size = min(proxy.size.width, proxy.size.height)
                PixelCanvas(editor: editor, kind: .bank)
                    .frame(width: size, height: size)
                    .background(.black)
                    .border(Color.panelBorder)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(minHeight: 182, maxHeight: 268)
            HStack {
                Toggle("Show duplicates", isOn: $editor.findDuplicates).toggleStyle(.checkbox)
                Spacer()
                Stepper(value: $editor.code, in: 0...255) {
                    Text(String(format: "$%02X", editor.code)).monospacedDigit()
                }
                .fixedSize()
                .help("Select previous or next character")
            }
        }
        .panel()
    }

    private var screenPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionTitle("Screen Editor")
                Spacer()
                Picker("Page", selection: $editor.pageIndex) {
                    ForEach(editor.project.pages.indices, id: \.self) { index in
                        Text(editor.project.pages[index].name).tag(index)
                    }
                }
                .labelsHidden().frame(width: 140)
                Menu {
                    Button("New Page") { editor.addPage(duplicate: false) }
                    Button("Duplicate Page") { editor.addPage(duplicate: true) }
                    Button("Rename or Resize…", action: editPage)
                    Button("Delete Page", role: .destructive, action: editor.deletePage)
                        .disabled(editor.project.pages.count < 2)
                    Divider()
                    Button("Import Raw Screen…", action: editor.importRaw)
                    Button("Clear Screen") {
                        editor.change("Cleared screen") {
                            $0.pages[editor.pageIndex].cells = Array(repeating: 0, count: editor.page.cells.count)
                        }
                    }
                } label: { Image(systemName: "ellipsis.circle") }
                .fixedSize().help("Page actions")
                Button("Insert Text", systemImage: "text.cursor") { state.textDialog = true }
            }
            HStack {
                Text("\(editor.page.width) × \(editor.page.height) characters")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                Spacer()
                Picker("Zoom", selection: $state.zoom) {
                    ForEach(1...4, id: \.self) { Text("\($0)×").tag($0) }
                }
                .pickerStyle(.segmented).frame(width: 160)
            }
            ScrollView([.horizontal, .vertical]) {
                PixelCanvas(editor: editor, kind: .screen, scale: state.zoom)
                    .frame(width: CGFloat(26 + editor.page.width * 8 * state.zoom),
                           height: CGFloat(editor.page.height * 8 * state.zoom))
                    .padding(12)
                    .accessibilityIdentifier("screenCanvas")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            .overlay { RoundedRectangle(cornerRadius: 6).stroke(Color.panelBorder).allowsHitTesting(false) }
            HStack {
                Text("Paint with the selected glyph. Right-click to pick. Click a row number to switch banks.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            Divider()
            HStack(spacing: 7) {
                Text("Palette").font(.subheadline.weight(.semibold))
                    .padding(.trailing, 4)
                ForEach(activeRegisters, id: \.self) { register in
                    Button { state.paletteRegister = register } label: {
                        RoundedRectangle(cornerRadius: 4).fill(editor.registerColor(register))
                            .frame(width: 23, height: 20)
                            .overlay { RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.25)) }
                    }
                    .buttonStyle(.plain)
                    .help("Edit palette register \(register)")
                    .accessibilityLabel("Palette register \(register)")
                    .popover(isPresented: Binding(get: { state.paletteRegister == register },
                                                  set: { if !$0 { state.paletteRegister = nil } })) {
                        palettePicker(register)
                    }
                }
                Spacer()
                Button("Reset") {
                    editor.change("Reset palette") { $0.colors = AtariProject.defaultColors }
                }.help("Restore the default Atari palette")
            }
        }
        .panel()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var activeRegisters: [Int] {
        switch editor.project.mode {
        case .text: return [0, 1]
        case .mode4, .mode5: return Array(1...5)
        case .mode10: return Array(1...9)
        }
    }

    private func palettePicker(_ register: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Atari Palette")
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(15), spacing: 2), count: 16), spacing: 2) {
                ForEach(0..<256, id: \.self) { index in
                    Button {
                        editor.change("Updated palette") { $0.colors[register] = UInt8(index) }
                        state.paletteRegister = nil
                    } label: {
                        Rectangle().fill(Color(cgColor: editor.atariPalette[index]))
                            .frame(width: 15, height: 15)
                            .border(editor.project.colors[register] == UInt8(index) ? .white : .clear)
                    }
                    .buttonStyle(.plain)
                    .help(String(format: "$%02X", index))
                }
            }
        }
        .padding(14)
    }

    private var statusBar: some View {
        HStack {
            Text(editor.message).lineLimit(1)
            Spacer()
            if editor.dirty {
                Label("Unsaved changes", systemImage: "circle.fill").foregroundStyle(Color.atariGreen)
            }
            Text("Bank \(editor.bank + 1)  /  \(editor.code & 127)\(editor.code >= 128 ? " INV" : "")")
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 18).frame(height: 28)
    }

    private func editPage() {
        state.pageName = editor.page.name
        state.pageWidth = String(editor.page.width)
        state.pageHeight = String(editor.page.height)
        state.pageDialog = true
    }

    private var pageSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Page Settings")
            TextField("Name", text: $state.pageName)
            HStack {
                TextField("Columns", text: $state.pageWidth)
                TextField("Rows", text: $state.pageHeight)
            }
            Text("Reducing the size crops cells outside the new dimensions.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { state.pageDialog = false }.keyboardShortcut(.cancelAction)
                Button("Apply") {
                    guard let width = Int(state.pageWidth), let height = Int(state.pageHeight) else { return }
                    editor.change("Updated page") {
                        try $0.pages[editor.pageIndex].resize(width: width, height: height)
                        $0.pages[editor.pageIndex].name = state.pageName
                    }
                    state.pageDialog = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(state.pageName.isEmpty || !(1...256).contains(Int(state.pageWidth) ?? 0)
                          || !(1...256).contains(Int(state.pageHeight) ?? 0))
            }
        }
        .padding(20).frame(width: 390)
    }

    private var textSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Insert Screen Text")
            TextEditor(text: $state.text).font(.system(.body, design: .monospaced))
                .frame(height: 100).border(Color.panelBorder)
            HStack {
                Stepper("Column \(state.textColumn + 1)", value: $state.textColumn, in: 0...(editor.page.width - 1))
                Stepper("Row \(state.textRow + 1)", value: $state.textRow, in: 0...(editor.page.height - 1))
            }
            HStack {
                Spacer()
                Button("Cancel") { state.textDialog = false }.keyboardShortcut(.cancelAction)
                Button("Insert") {
                    editor.insertText(state.text, x: min(state.textColumn, editor.page.width - 1),
                                      y: min(state.textRow, editor.page.height - 1))
                    state.textDialog = false
                }
                .keyboardShortcut(.defaultAction).disabled(state.text.isEmpty)
            }
        }
        .padding(20).frame(width: 390)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.system(size: 14, weight: .semibold))
    }
}

private extension View {
    func panel() -> some View {
        padding(11)
            .background(Color.panelBackground, in: RoundedRectangle(cornerRadius: 10))
            .overlay { RoundedRectangle(cornerRadius: 10).stroke(Color.panelBorder).allowsHitTesting(false) }
    }
}

private final class WorkspaceState: ObservableObject {
    @Published var zoom = 2
    @Published var pageDialog = false
    @Published var textDialog = false
    @Published var pageName = ""
    @Published var pageWidth = "40"
    @Published var pageHeight = "26"
    @Published var text = ""
    @Published var textColumn = 0
    @Published var textRow = 0
    @Published var paletteRegister: Int?
}
