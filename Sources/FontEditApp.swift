import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let editor = Editor()

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        editor.confirmDiscard() ? .terminateNow : .terminateCancel
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if ["atrview", "vf2", "vfn"].contains(url.pathExtension.lowercased()) {
                editor.openProject(url)
            } else {
                editor.importFont(url)
            }
        }
    }
}

@main
struct FontEditApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("FontEdit", id: "editor") {
            Workspace(editor: delegate.editor)
                .frame(minWidth: 990, minHeight: 660)
                .preferredColorScheme(.dark)
                .tint(.atariGreen)
        }
        .defaultSize(width: 1200, height: 810)
        .commands {
            EditorCommands(editor: delegate.editor)
        }
    }
}

struct EditorCommands: Commands {
    @ObservedObject var editor: Editor

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Project", action: editor.newProject).keyboardShortcut("n")
            Button("Open Atari View…", action: editor.openProject).keyboardShortcut("o")
            Button("Import Font…", action: editor.importFont).keyboardShortcut("i")
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save Project") { editor.saveProject() }.keyboardShortcut("s")
            Button("Save Project As…") { editor.saveProject(asNew: true) }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            Divider()
            Menu("Export") {
                ExportItems(editor: editor)
            }
        }
        CommandGroup(replacing: .undoRedo) {
            Button("Undo", action: editor.undo).keyboardShortcut("z").disabled(!editor.canUndo)
            Button("Redo", action: editor.redo)
                .keyboardShortcut("z", modifiers: [.command, .shift]).disabled(!editor.canRedo)
        }
        CommandMenu("Glyph") {
            Button("Copy Glyph Bytes", action: editor.copyGlyph).keyboardShortcut("c", modifiers: [.command, .shift])
            Button("Paste Glyph Bytes", action: editor.pasteGlyph).keyboardShortcut("v", modifiers: [.command, .shift])
            Divider()
            ForEach(GlyphOperation.allCases, id: \.self) { operation in
                Button(operation.title) { editor.transform(operation) }
                    .disabled(editor.project.mode != .text && operation.isRotation)
            }
            Divider()
            Button("Clear Glyph") { editor.setGlyph(Array(repeating: 0, count: 8), label: "Cleared glyph") }
            Button("Restore Default Glyph", action: editor.restoreGlyph)
            Button("Restore Saved Glyph", action: editor.restoreSavedGlyph)
        }
    }
}

struct ExportItems: View {
    @ObservedObject var editor: Editor

    var body: some View {
        Button("Current Bank as FNT…") { editor.exportFont() }
        Button("Two Consecutive Banks as FNT…") { editor.exportFont(count: 2) }.disabled(editor.bank == 3)
        Button("All Four Banks as FNT…") { editor.exportFont(count: 4) }
        Divider()
        Button("Current Bank as PNG…") { editor.exportPNG(screen: false) }
        Button("Screen as PNG…") { editor.exportPNG(screen: true) }
        Button("Screen as Raw Bytes…") { editor.export(Data(editor.page.cells), filename: "Screen.raw") }
        Divider()
        Button("Current Bank as Assembly…") { editor.exportSource(assembly: true) }
        Button("Current Bank as C Array…") { editor.exportSource(assembly: false) }
    }
}

extension GlyphOperation {
    var isRotation: Bool { self == .rotateLeft || self == .rotateRight }
}

extension Color {
    static let atariGreen = Color(red: 0.70, green: 0.96, blue: 0.51)
    static let workspaceBackground = Color(red: 0.066, green: 0.075, blue: 0.085)
    static let panelBackground = Color(red: 0.095, green: 0.108, blue: 0.12)
    static let panelBorder = Color.white.opacity(0.10)
}
