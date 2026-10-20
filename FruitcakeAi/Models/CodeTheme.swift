import SwiftUI

/// Code presentation only. App chrome, approvals and status colors stay in Theme.
struct CodeTheme: Equatable, Sendable {
    static let schemaVersion = 1
    static let preferenceKey = "appearance.code.theme.v1"

    enum Preset: String, CaseIterable, Identifiable, Sendable {
        case fruitcake, paper, highContrast
        var id: String { rawValue }
        var title: String {
            switch self { case .fruitcake: "Fruitcake"; case .paper: "Paper"; case .highContrast: "High Contrast" }
        }
    }

    let preset: Preset
    let background: UInt
    let foreground: UInt
    let gutter: UInt
    let secondary: UInt
    let selection: UInt
    let search: UInt
    let keyword: UInt
    let string: UInt
    let comment: UInt
    let number: UInt
    let type: UInt
    let function: UInt
    let property: UInt
    let operation: UInt
    let additionText: UInt
    let removalText: UInt
    let additionFill: UInt
    let removalFill: UInt

    var findingMarker: UInt { preset == .paper ? 0x8C5A00 : 0xE2A94B }

    static func resolve(_ stored: String) -> Self { palette(Preset(rawValue: stored) ?? .fruitcake) }
    static func palette(_ preset: Preset) -> Self {
        switch preset {
        case .fruitcake:
            Self(preset: preset, background: 0x0F1113, foreground: 0xE7E9EB, gutter: 0x17191B,
                 secondary: 0x9AA0A6, selection: 0x315C70, search: 0xEAC56C,
                 keyword: 0x91BFFF, string: 0xACD99E, comment: 0x9BA6AE, number: 0xF1BD82,
                 type: 0x81D4CE, function: 0xE8D392, property: 0xB9CFF0, operation: 0xD4D9DF,
                 additionText: 0x9FE0BE, removalText: 0xE8A3A3, additionFill: 0x173B2C, removalFill: 0x432329)
        case .paper:
            Self(preset: preset, background: 0xFAF8F2, foreground: 0x252B30, gutter: 0xF0EDE4,
                 secondary: 0x606870, selection: 0xC9DEED, search: 0xEAC56C,
                 keyword: 0x235A9C, string: 0x32692D, comment: 0x676B6D, number: 0x8D491D,
                 type: 0x146A70, function: 0x7A520B, property: 0x495986, operation: 0x454C55,
                 additionText: 0x175B35, removalText: 0x932F36, additionFill: 0xDCEFE2, removalFill: 0xFBE3E4)
        case .highContrast:
            Self(preset: preset, background: 0x050607, foreground: 0xFFFFFF, gutter: 0x111416,
                 secondary: 0xC4CCD1, selection: 0x375E85, search: 0xFFE478,
                 keyword: 0xA9D1FF, string: 0xC4F4A3, comment: 0xBBC4CB, number: 0xFFD09C,
                 type: 0x98F0E3, function: 0xFFE9A0, property: 0xD6DCFF, operation: 0xFFFFFF,
                 additionText: 0xC5FFDF, removalText: 0xFFD2D2, additionFill: 0x12402A, removalFill: 0x521C29)
        }
    }

    func hex(for kind: CodeTokenKind) -> UInt {
        switch kind {
        case .keyword: keyword; case .string: string; case .comment: comment; case .number: number
        case .type: type; case .function: function; case .property: property; case .operation: operation
        }
    }

    /// A syntax color cannot make a changed row less legible than its diff text.
    func hex(for kind: CodeTokenKind, on fill: UInt?, fallback: UInt) -> UInt {
        let value = hex(for: kind)
        return Self.contrast(value, fill ?? background) >= 4.5 ? value : fallback
    }

    static func contrast(_ first: UInt, _ second: UInt) -> Double {
        func luminance(_ hex: UInt) -> Double {
            func linear(_ byte: UInt) -> Double {
                let value = Double(byte & 255) / 255
                return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(hex >> 16) + 0.7152 * linear(hex >> 8) + 0.0722 * linear(hex)
        }
        let a = luminance(first), b = luminance(second)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}
