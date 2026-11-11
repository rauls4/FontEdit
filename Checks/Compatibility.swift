import Foundation

@main
struct Compatibility {
    static func main() throws {
        let font = Array(try Data(contentsOf: URL(fileURLWithPath: "Resources/Default.fnt")))
        let palette = Array(try Data(contentsOf: URL(fileURLWithPath: "Resources/Atari.pal")))
        var project = AtariProject(defaultFont: font)
        for mode in GraphicsMode.allCases {
            for input in UInt8.min...UInt8.max {
                for column in 0..<mode.columns {
                    let updated = mode.replacing(input, column, with: mode.mask)
                    precondition(mode.pixel(updated, column) == mode.mask)
                    for other in 0..<mode.columns where other != column {
                        precondition(mode.pixel(updated, other) == mode.pixel(input, other))
                    }
                }
            }
        }
        let fontPair = Data(repeating: 0xBA, count: 2048)
        try project.loadFont(fontPair, at: 2, name: "pair.fnt")
        precondition(Data(project.fonts[2] + project.fonts[3]) == fontPair)
        do {
            try project.loadFont(fontPair, at: 3, name: "overflow.fnt")
            preconditionFailure("Accepted overflowing font pair")
        } catch FileProblem.bankOverflow {}
        project.mode = .mode10
        project.pages[0].cells[41] = 193
        project.pages[0].banks[1] = 4
        try project.pages[0].resize(width: 48, height: 27)
        precondition(project.pages[0].cells[49] == 193)
        precondition(project.pages[0].banks[1] == 4)
        project.pages.append(ScreenPage(number: 2, name: "Another Page", width: 32, height: 20))
        project.tileRecords = Data("[{\"Nr\":1}]".utf8)
        let roundTrip = try AtariProject(viewData: project.viewData(activePage: 1))
        precondition(roundTrip == project)

        var legacy = Data(repeating: 0, count: 52 + 832)
        legacy[0] = 3
        legacy[1] = 1
        legacy[2] = 3
        legacy[52] = 42
        try project.loadLegacyView(legacy, vf2: true, palette: palette)
        precondition(project.pageCheck(32, 26, bank: 3, firstCell: 42))

        var vfn = Data(repeating: 0, count: 19 + 186)
        vfn[19 + 6] = 9
        try project.loadLegacyView(vfn, vf2: false, palette: palette)
        precondition(project.pages[0].cells[1] == 9)

        if CommandLine.arguments.count == 2 {
            let upstream = URL(fileURLWithPath: CommandLine.arguments[1])
            let original = try AtariProject(viewData: Data(contentsOf: upstream))
            precondition(original.fonts[0] == font)
            precondition(original.pages[0].cells.contains(0x34))
            let reloaded = try AtariProject(viewData: original.viewData(activePage: 0))
            precondition(reloaded == original)
        }
        print("Font, pixel, screen, legacy import and project round-trip checks passed.")
    }
}

private extension AtariProject {
    func pageCheck(_ width: Int, _ height: Int, bank: UInt8, firstCell: UInt8) -> Bool {
        let page = pages[0]
        return page.width == width && page.height == height && page.banks[0] == bank && page.cells[0] == firstCell
    }
}
