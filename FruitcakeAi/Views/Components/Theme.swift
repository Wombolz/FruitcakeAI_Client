//
//  Theme.swift
//  FruitcakeAi
//
//  Dark-console design tokens for the chat surfaces (header, bubbles,
//  composer, tool indicator, sidebar, profile sheet, task draft card).
//  Reference: "FruitcakeAI Redesign.dc.html" mock + accompanying handoff.
//

import SwiftUI

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(.sRGB,
                  red:   Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8)  & 0xFF) / 255,
                  blue:  Double( hex        & 0xFF) / 255,
                  opacity: alpha)
    }
}

enum Theme {
    // Surfaces (back-to-front)
    static let bg       = Color(hex: 0x0F1113)   // detail pane background
    static let sidebar  = Color(hex: 0x141618)
    static let titlebar = Color(hex: 0x1B1D1F)
    static let field    = Color(hex: 0x17191B)   // composer input, cards
    static let bubble   = Color(hex: 0x1A1D20)   // assistant bubble
    static let composer = Color(hex: 0x121417)
    static let card      = Color(hex: 0x16191C)

    // Lines
    static let stroke   = Color.white.opacity(0.06)
    static let strokeUp = Color.white.opacity(0.10)  // interactive borders

    // Text
    static let text      = Color(hex: 0xE7E9EB)
    static let textMid   = Color(hex: 0xC6CACE)
    static let textDim   = Color(hex: 0x9AA0A6)
    static let textFaint = Color(hex: 0x5C636A)

    // Status
    static let online   = Color(hex: 0x28C840)
    static let onDevice = Color(hex: 0xE2A94B)

    /// Mono label style — model names, tool names, section headers, timestamps.
    /// The mono/system font pairing is the core of the visual language.
    static func mono(_ size: CGFloat = 11, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Persona accent

/// Personas are backend-driven, free-form keys (e.g. "family_assistant") with no fixed
/// enum in this app, so accents are derived deterministically rather than hardcoded —
/// any persona key gets a stable color/monogram without a frontend change when the
/// backend adds or renames personas.
enum PersonaAccent {
    private static let palette: [Color] = [
        Color(hex: 0x4FB6D9), // cyan
        Color(hex: 0x4FC98C), // green
        Color(hex: 0xE2A94B), // amber
        Color(hex: 0xC98DE0), // violet
        Color(hex: 0xE0708D), // rose
        Color(hex: 0x7FA8E0), // blue
    ]

    static func color(for personaKey: String) -> Color {
        guard !personaKey.isEmpty else { return palette[0] }
        let hash = personaKey.unicodeScalars.reduce(UInt64(5381)) { acc, scalar in
            acc &* 33 &+ UInt64(scalar.value)
        }
        return palette[Int(hash % UInt64(palette.count))]
    }

    static func monogram(for displayName: String, personaKey: String) -> String {
        let source = displayName.trimmingCharacters(in: .whitespaces).isEmpty ? personaKey : displayName
        let words = source
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .filter { !$0.isEmpty }
        let letters = words.prefix(2).compactMap { $0.first }
        let monogram = String(letters).uppercased()
        return monogram.isEmpty ? "?" : monogram
    }
}

// MARK: - Reusable components

/// Pill chip used in the header and composer (model, reasoning, persona).
struct ConsoleChip: View {
    var text: String
    var accentDot: Color? = nil
    var mono: Bool = true

    var body: some View {
        HStack(spacing: 6) {
            if let dot = accentDot {
                Circle().fill(dot).frame(width: 7, height: 7)
            }
            Text(text)
                .font(mono ? Theme.mono(11) : .system(size: 11.5, weight: .medium))
                .foregroundStyle(Theme.textDim)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .overlay(Capsule().stroke(Theme.strokeUp, lineWidth: 1))
    }
}

/// Persona avatar — mono initials in a tinted rounded square.
struct PersonaAvatar: View {
    var personaKey: String
    var displayName: String
    var size: CGFloat = 36

    private var accent: Color { PersonaAccent.color(for: personaKey) }
    private var monogram: String { PersonaAccent.monogram(for: displayName, personaKey: personaKey) }

    var body: some View {
        Text(monogram)
            .font(Theme.mono(size * 0.33, weight: .bold))
            .foregroundStyle(accent)
            .frame(width: size, height: size)
            .background(accent.opacity(0.16), in: RoundedRectangle(cornerRadius: size * 0.25))
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.25)
                    .stroke(accent.opacity(0.42), lineWidth: 1)
            )
    }
}
