import Foundation

enum GraphicsMode: Int, CaseIterable, Identifiable {
    case text, mode4, mode5, mode10

    var id: Int { rawValue }
    var title: String { ["Mode 2", "Mode 4", "Mode 5", "Mode 10"][rawValue] }
    var bits: Int { [1, 2, 2, 4][rawValue] }
    var columns: Int { 8 / bits }
    var mask: UInt8 { UInt8((1 << bits) - 1) }

    func pixel(_ row: UInt8, _ column: Int) -> UInt8 {
        (row >> ((columns - 1 - column) * bits)) & mask
    }

    func replacing(_ row: UInt8, _ column: Int, with value: UInt8) -> UInt8 {
        let shift = (columns - 1 - column) * bits
        return (row & ~(mask << shift)) | ((value & mask) << shift)
    }

    func register(_ value: UInt8, inverse: Bool) -> Int {
        switch self {
        case .text: return Int(inverse ? value : 1 - value)
        case .mode4, .mode5: return inverse && value == 3 ? 5 : Int(value) + 1
        case .mode10:
            let map = [0, 1, 2, 3, 4, 5, 6, 7, 8, 8, 8, 8, 4, 5, 6, 7]
            return map[Int(inverse ? 15 - value : value)] + 1
        }
    }
}

enum FileProblem: LocalizedError {
    case fontSize, bankOverflow, invalidProject, invalidDimensions, rawSize
    var errorDescription: String? {
        switch self {
        case .fontSize: return "A font file must contain 1,024, 2,048, or 4,096 bytes."
        case .bankOverflow: return "This file has more fonts than the remaining banks."
        case .invalidProject: return "The Atari view file contains missing or invalid data."
        case .invalidDimensions: return "Page dimensions must be between 1 and 256 characters."
        case .rawSize: return "The raw screen must contain one byte per cell in the current page."
        }
    }
}

struct ScreenPage: Equatable {
    var number: Int
    var name: String
    var width: Int
    var height: Int
    var cells: [UInt8]
    var banks: [UInt8]

    init(number: Int = 1, name: String = "Page 1", width: Int = 40, height: Int = 26) {
        self.number = number
        self.name = name
        self.width = width
        self.height = height
        cells = .init(repeating: 0, count: width * height)
        banks = .init(repeating: 1, count: height)
    }

    mutating func resize(width: Int, height: Int) throws {
        guard (1...256).contains(width), (1...256).contains(height) else {
            throw FileProblem.invalidDimensions
        }
        var resized = ScreenPage(number: number, name: name, width: width, height: height)
        let columns = min(width, self.width)
        for row in 0..<min(height, self.height) {
            resized.banks[row] = banks[row]
            let start = row * self.width
            resized.cells.replaceSubrange(row * width..<row * width + columns,
                                          with: cells[start..<start + columns])
        }
        self = resized
    }
}

struct AtariProject: Equatable {
    static let defaultColors: [UInt8] = [0x0E, 0, 0x28, 0xCA, 0x94, 0x46, 0x16, 0x1A, 0xB4, 0xBA]
    var fonts: [[UInt8]]
    var names = Array(repeating: "Default.fnt", count: 4)
    var pages = [ScreenPage()]
    var colors = Self.defaultColors
    var mode = GraphicsMode.text
    // Keep upstream tile records when a project is edited and saved.
    var tileRecords: Data?

    init(defaultFont: [UInt8]) {
        precondition(defaultFont.count == 1024)
        fonts = .init(repeating: defaultFont, count: 4)
    }

    func glyph(bank: Int, code: Int) -> ArraySlice<UInt8> {
        let start = (code & 127) * 8
        return fonts[bank][start..<start + 8]
    }

    mutating func setGlyph(bank: Int, code: Int, rows: [UInt8]) {
        let start = (code & 127) * 8
        fonts[bank].replaceSubrange(start..<start + 8, with: rows)
    }

    mutating func loadFont(_ data: Data, at bank: Int, name: String) throws {
        guard [1024, 2048, 4096].contains(data.count) else { throw FileProblem.fontSize }
        let count = data.count / 1024
        guard (0..<4).contains(bank), bank + count <= 4 else { throw FileProblem.bankOverflow }
        let bytes = Array(data)
        for offset in 0..<count {
            fonts[bank + offset] = Array(bytes[offset * 1024..<(offset + 1) * 1024])
            names[bank + offset] = count == 1 ? name : "\(name) · \(offset + 1)"
        }
    }

    init(viewData: Data) throws {
        guard let json = try JSONSerialization.jsonObject(with: viewData) as? [String: Any],
              let version = Int(json["Version"] as? String ?? ""), version >= 1911,
              let fontData = decodeHex(json["Data"]), [2048, 4096].contains(fontData.count)
        else { throw FileProblem.invalidProject }

        let allFonts = fontData.count == 2048 ? fontData + fontData : fontData
        fonts = (0..<4).map { Array(allFonts[$0 * 1024..<($0 + 1) * 1024]) }
        names = (1...4).map { json["Fontname\($0)"] as? String ?? "Default.fnt" }
        mode = GraphicsMode(rawValue: Int(json["ColoredGfx"] as? String ?? "") ?? 0) ?? .text
        if let values = decodeHex(json["Colors"]), [6, 10].contains(values.count) {
            colors.replaceSubrange(0..<values.count, with: values)
        }
        if let tiles = json["Tiles"] as? [[String: Any]] {
            tileRecords = try JSONSerialization.data(withJSONObject: tiles, options: .sortedKeys)
        }

        if let records = json["Pages"] as? [[String: Any]], !records.isEmpty {
            pages = try records.enumerated().map { index, record in
                try Self.page(record, cellsKey: "View", banksKey: "SelectedFont",
                              number: record["Nr"] as? Int ?? index + 1,
                              name: record["Name"] as? String ?? "Page \(index + 1)")
            }
        } else {
            pages = [try Self.page(json, cellsKey: "Chars", banksKey: "Lines",
                                   number: 1, name: "Page 1",
                                   storedWidth: version < 2007 ? 32 : nil)]
        }
    }

    private static func page(_ record: [String: Any], cellsKey: String, banksKey: String,
                             number: Int, name: String, storedWidth: Int? = nil) throws -> ScreenPage {
        let fileWidth = record["Width"] as? Int ?? 40
        let fileHeight = record["Height"] as? Int ?? 26
        let width = fileWidth == 0 ? 40 : fileWidth
        let height = fileHeight == 0 ? 26 : fileHeight
        let stride = storedWidth ?? width
        guard (1...256).contains(width), (1...256).contains(height), stride <= width,
              let bytes = decodeHex(record[cellsKey]), bytes.count >= stride * height,
              let banks = decodeHex(record[banksKey]), banks.count >= height,
              banks.prefix(height).allSatisfy({ (1...4).contains($0) })
        else { throw FileProblem.invalidProject }
        var page = ScreenPage(number: number, name: name, width: width, height: height)
        page.banks = Array(banks.prefix(height))
        for row in 0..<height {
            page.cells.replaceSubrange(row * width..<row * width + stride,
                                       with: bytes[row * stride..<(row + 1) * stride])
        }
        return page
    }

    func viewData(activePage: Int) throws -> Data {
        let page = pages[activePage]
        var json: [String: Any] = [
            "Version": "2023", "ColoredGfx": String(mode.rawValue),
            "Chars": hex(page.cells), "Lines": hex(page.banks), "Colors": hex(colors),
            "Width": page.width, "Height": page.height, "Data": hex(fonts.flatMap { $0 }),
            "FortyBytes": page.width == 32 ? "0" : (page.width == 48 ? "2" : "1"),
            "Pages": pages.map {
                ["Nr": $0.number, "Name": $0.name, "Width": $0.width, "Height": $0.height,
                 "View": hex($0.cells), "SelectedFont": hex($0.banks)] as [String: Any]
            }
        ]
        for (index, name) in names.enumerated() { json["Fontname\(index + 1)"] = name }
        if let tileRecords { json["Tiles"] = try JSONSerialization.jsonObject(with: tileRecords) }
        return try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys, .prettyPrinted])
    }
}

func hex(_ bytes: [UInt8]) -> String {
    let digits = Array("0123456789ABCDEF".utf8)
    return String(decoding: bytes.flatMap { [digits[Int($0 >> 4)], digits[Int($0 & 15)]] },
                  as: UTF8.self)
}

private func decodeHex(_ value: Any?) -> [UInt8]? {
    guard let value = value as? String else { return nil }
    let input = Array(value.utf8)
    guard input.count.isMultiple(of: 2) else { return nil }
    var bytes: [UInt8] = []
    bytes.reserveCapacity(input.count / 2)
    for index in stride(from: 0, to: input.count, by: 2) {
        guard let high = nibble(input[index]), let low = nibble(input[index + 1]) else { return nil }
        bytes.append(high << 4 | low)
    }
    return bytes
}

private func nibble(_ ascii: UInt8) -> UInt8? {
    switch ascii {
    case 48...57: return ascii - 48
    case 65...70: return ascii - 55
    case 97...102: return ascii - 87
    default: return nil
    }
}

extension AtariProject {
    mutating func loadLegacyView(_ data: Data, vf2: Bool, palette: [UInt8]) throws {
        let bytes = Array(data)
        let version = vf2 ? bytes.first : nil
        let width: Int
        let height: Int
        let headerSize: Int
        switch (vf2, version) {
        case (true, 2): (width, height, headerSize) = (31, 8, 34)
        case (true, 3): (width, height, headerSize) = (32, 26, 34)
        case (false, _): (width, height, headerSize) = (31, 6, 1)
        default: throw FileProblem.invalidProject
        }
        let start = headerSize + 18
        guard bytes.count >= start + width * height else { throw FileProblem.invalidProject }

        mode = GraphicsMode(rawValue: Int(bytes[vf2 ? 1 : 0])) ?? .text
        var page = ScreenPage(width: width, height: height)
        if vf2 {
            for row in 0..<8 {
                let bank = bytes[2 + row * 4]
                if (1...4).contains(bank) { page.banks[row] = bank }
            }
        }
        for register in 0..<6 {
            let input = headerSize + register * 3
            var bestDistance = Int.max
            for index in 0..<256 {
                let offset = index * 3
                let r = Int(bytes[input]) - Int(palette[offset])
                let g = Int(bytes[input + 1]) - Int(palette[offset + 1])
                let b = Int(bytes[input + 2]) - Int(palette[offset + 2])
                let distance = r * r + g * g + b * b
                if distance < bestDistance {
                    bestDistance = distance
                    colors[register] = UInt8(index)
                }
            }
        }
        for row in 0..<height {
            for column in 0..<width {
                let offset = vf2 ? row * width + column : column * height + row
                page.cells[row * width + column] = bytes[start + offset]
            }
        }
        pages = [page]
    }
}
