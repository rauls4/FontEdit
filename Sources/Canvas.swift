import AppKit
import SwiftUI

enum CanvasKind { case glyph, bank, screen }

struct PixelCanvas: NSViewRepresentable {
    @ObservedObject var editor: Editor
    let kind: CanvasKind
    var scale: Int = 2

    func makeNSView(context: Context) -> PixelView {
        PixelView(editor: editor, kind: kind)
    }

    func updateNSView(_ view: PixelView, context: Context) {
        view.scale = scale
        view.needsDisplay = true
    }
}

@MainActor
final class PixelView: NSView {
    let editor: Editor
    let kind: CanvasKind
    var scale = 2
    private var previous: SIMD2<Int>?
    private var strokeValue: UInt8 = 1
    private let rowGutter: CGFloat = 26

    init(editor: Editor, kind: CanvasKind) {
        self.editor = editor
        self.kind = kind
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel(kind == .glyph ? "Glyph pixel grid" :
                              kind == .bank ? "Font bank character grid" : "Atari screen editor")
    }

    required init?(coder: NSCoder) { fatalError("Use init(editor:kind:)") }
    override var isFlipped: Bool { true }

    private var cell: CGSize {
        switch kind {
        case .glyph:
            return CGSize(width: bounds.width / CGFloat(editor.project.mode.columns),
                          height: bounds.height / 8)
        case .bank:
            return CGSize(width: bounds.width / 16, height: bounds.height / 16)
        case .screen:
            return CGSize(width: 8 * scale, height: 8 * scale)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.setShouldAntialias(false)
        let size = cell
        switch kind {
        case .glyph:
            let glyph = editor.glyph
            let mode = editor.project.mode
            for y in 0..<8 {
                for x in 0..<mode.columns {
                    let value = mode.pixel(glyph[y], x)
                    let rect = CGRect(x: CGFloat(x) * size.width, y: CGFloat(y) * size.height,
                                      width: size.width, height: size.height)
                    context.setFillColor(editor.color(value, inverse: editor.code >= 128))
                    context.fill(rect)
                    if editor.guides {
                        context.setStrokeColor(CGColor(gray: 0.5, alpha: 0.55))
                        context.stroke(rect.insetBy(dx: 0.5, dy: 0.5), width: 1)
                    }
                }
            }
        case .bank:
            let selected = editor.glyph
            for index in 0..<256 {
                let rect = CGRect(x: CGFloat(index % 16) * size.width, y: CGFloat(index / 16) * size.height,
                                  width: size.width, height: size.height)
                let inset = rect.insetBy(dx: 1, dy: 1)
                drawCharacter(context, rect: inset, bank: editor.bank, code: index)
                let duplicate = editor.findDuplicates && (index >= 128) == (editor.code >= 128)
                    && editor.project.glyph(bank: editor.bank, code: index).elementsEqual(selected)
                if index == editor.code || duplicate {
                    context.setStrokeColor(index == editor.code ?
                                           CGColor(srgbRed: 0.68, green: 0.95, blue: 0.47, alpha: 1) :
                                           CGColor(srgbRed: 1, green: 0.7, blue: 0.35, alpha: 1))
                    context.stroke(rect.insetBy(dx: 1, dy: 1), width: 2)
                }
            }
        case .screen:
            let page = editor.page
            let firstRow = max(0, Int(dirtyRect.minY / size.height))
            let lastRow = min(page.height, Int(ceil(dirtyRect.maxY / size.height)))
            let firstColumn = max(0, Int((dirtyRect.minX - rowGutter) / size.width))
            let lastColumn = max(0, min(page.width, Int(ceil((dirtyRect.maxX - rowGutter) / size.width))))
            guard firstRow < lastRow else { return }
            for row in firstRow..<lastRow {
                let y = CGFloat(row) * size.height
                let bank = Int(page.banks[row]) - 1
                if dirtyRect.minX < rowGutter {
                    context.setFillColor(CGColor(gray: row.isMultiple(of: 2) ? 0.16 : 0.20, alpha: 1))
                    context.fill(CGRect(x: 0, y: y, width: rowGutter - 1, height: size.height))
                    let label = "\(bank + 1)" as NSString
                    label.draw(at: CGPoint(x: 9, y: y + max(0, (size.height - 12) / 2)),
                               withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 10, weight: .medium),
                                                .foregroundColor: NSColor.white])
                }
                guard firstColumn < lastColumn else { continue }
                for col in firstColumn..<lastColumn {
                    let rect = CGRect(x: rowGutter + CGFloat(col) * size.width, y: y,
                                      width: size.width, height: size.height)
                    drawCharacter(context, rect: rect, bank: bank, code: Int(page.cells[row * page.width + col]))
                }
            }
        }
    }

    private func drawCharacter(_ context: CGContext, rect: CGRect, bank: Int, code: Int) {
        let mode = editor.project.mode
        let inverse = code >= 128
        let glyph = editor.project.glyph(bank: bank, code: code)
        let dx = rect.width / CGFloat(mode.columns)
        let dy = rect.height / 8
        context.setFillColor(editor.color(0, inverse: inverse))
        context.fill(rect)
        for (y, row) in glyph.enumerated() where row != 0 {
            for x in 0..<mode.columns {
                let value = mode.pixel(row, x)
                guard value != 0 else { continue }
                context.setFillColor(editor.color(value, inverse: inverse))
                context.fill(CGRect(x: rect.minX + CGFloat(x) * dx, y: rect.minY + CGFloat(y) * dy,
                                    width: dx, height: dy))
            }
        }
    }

    override func mouseDown(with event: NSEvent) { start(event, right: false) }
    override func rightMouseDown(with event: NSEvent) { start(event, right: true) }
    override func mouseDragged(with event: NSEvent) { drag(event, right: false) }
    override func rightMouseDragged(with event: NSEvent) { drag(event, right: true) }
    override func mouseUp(with event: NSEvent) { finish() }
    override func rightMouseUp(with event: NSEvent) { finish() }

    private func position(_ event: NSEvent) -> SIMD2<Int>? {
        var point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point) else { return nil }
        if kind == .screen {
            if point.x < rowGutter { return SIMD2(-1, Int(point.y / cell.height)) }
            point.x -= rowGutter
        }
        return SIMD2(Int(point.x / cell.width), Int(point.y / cell.height))
    }

    private func start(_ event: NSEvent, right: Bool) {
        guard let point = position(event) else { return }
        window?.makeFirstResponder(nil)
        switch kind {
        case .glyph:
            let mode = editor.project.mode
            let current = mode.pixel(editor.glyph[point.y], point.x)
            let ink = editor.ink
            strokeValue = right ? 0 : (editor.rewrite && current == ink ? 0 : ink)
            editor.startStroke()
        case .bank: break
        case .screen:
            if point.x < 0 {
                editor.cycleBank(row: point.y, backwards: right)
                return
            }
            editor.startStroke()
        }
        previous = point
        apply(point, right: right)
    }

    private func drag(_ event: NSEvent, right: Bool) {
        guard let point = position(event), let from = previous, point.x >= 0 else { return }
        let dx = point.x - from.x
        let dy = point.y - from.y
        let steps = max(abs(dx), abs(dy))
        guard steps > 0 else { return }
        for step in 1...steps {
            let x = from.x + Int((Double(dx * step) / Double(steps)).rounded())
            let y = from.y + Int((Double(dy * step) / Double(steps)).rounded())
            apply(SIMD2(x, y), right: right)
        }
        previous = point
    }

    private func apply(_ point: SIMD2<Int>, right: Bool) {
        switch kind {
        case .glyph: editor.editPixel(x: point.x, y: point.y, value: strokeValue)
        case .bank: editor.code = point.y * 16 + point.x
        case .screen: editor.paintScreen(x: point.x, y: point.y, erase: right)
        }
        needsDisplay = true
    }

    private func finish() {
        previous = nil
        editor.endStroke()
    }
}

extension Editor {
    func exportPNG(screen: Bool) {
        let mode = project.mode
        let currentPage = page
        let width = (screen ? currentPage.width : 16) * 8
        let height = (screen ? currentPage.height : 8) * 8
        guard let image = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width,
                                            pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
                                            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                            bytesPerRow: width * 4, bitsPerPixel: 32),
              let pixels = image.bitmapData else { return }
        let palette = atariPalette.map { color -> [UInt8] in
            (color.components ?? [0, 0, 0, 1]).map { UInt8(($0 * 255).rounded()) }
        }
        for y in 0..<height {
            for x in 0..<width {
                let row = y / 8
                let column = x / 8
                let code = screen ? Int(currentPage.cells[row * currentPage.width + column]) : row * 16 + column
                let bank = screen ? Int(currentPage.banks[row]) - 1 : bank
                let glyph = project.glyph(bank: bank, code: code)
                let value = mode.pixel(glyph[glyph.startIndex + y % 8], x % 8 / mode.bits)
                let rgb = palette[Int(project.colors[mode.register(value, inverse: code >= 128)])]
                let index = y * image.bytesPerRow + x * 4
                for channel in 0..<4 { pixels[index + channel] = rgb[channel] }
            }
        }
        if let png = image.representation(using: .png, properties: [:]) {
            export(png, filename: screen ? "Screen.png" : "Font.png")
        }
    }
}
