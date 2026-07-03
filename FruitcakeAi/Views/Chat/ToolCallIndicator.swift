//
//  ToolCallIndicator.swift
//  FruitcakeAi
//
//  Animated indicator shown in the message thread between the user's
//  message and the first streamed token. Signals that the agent is
//  working (tool call, generation, etc.) without naming a specific
//  tool — no live tool-name transport exists yet. `label` and `accent`
//  are the upgrade seam for when that becomes available.
//
//  Styled as the same speaker mid-response: same bubble fill + accent
//  rail as MessageBubble's assistant bubble, so the live-run state reads
//  as a continuation of the thread rather than a floating debug pill.
//

import SwiftUI

struct ToolCallIndicator: View {

    var label: String = "Working…"
    var detail: String? = nil
    var chips: [String] = []
    var accent: Color = Theme.textDim

    var body: some View {
        // An outer HStack + trailing Spacer (mirroring MessageBubble's own
        // wrapper) is what pins this to the left edge and forces the row to
        // claim full width — capping maxWidth on the outermost view instead
        // caps what the LazyVStack row sees as this child's size, so the row
        // falls back to LazyVStack's default *center* alignment.
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 11) {
                    PulseDots(accent: accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(label)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(Theme.textMid)
                        if let detail, !detail.isEmpty {
                            Text(detail)
                                .font(Theme.mono(10.5))
                                .foregroundStyle(Theme.textDim)
                        }
                    }
                }
                if !chips.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(chips, id: \.self) { chip in
                                Text(chip)
                                    .font(Theme.mono(10))
                                    .foregroundStyle(Theme.textMid)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 5))
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Theme.bubble)
            .overlay(alignment: .leading) {
                accent.opacity(0.55).frame(width: 2)
            }
            .clipShape(.rect(topLeadingRadius: 14, bottomLeadingRadius: 4,
                              bottomTrailingRadius: 14, topTrailingRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14).stroke(Theme.stroke, lineWidth: 1)
            )
            .frame(maxWidth: 560, alignment: .leading)

            Spacer(minLength: 48)
        }
        .padding(.horizontal)
    }
}

private struct PulseDots: View {
    let accent: Color

    @State private var pulse = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(accent)
                    .frame(width: 6, height: 6)
                    .opacity(pulse ? 1 : 0.22)
                    .animation(
                        .easeInOut(duration: 1.1).repeatForever().delay(Double(i) * 0.2),
                        value: pulse
                    )
            }
        }
        .onAppear { pulse = true }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        ToolCallIndicator()
        ToolCallIndicator(label: "Searching library…", detail: "Grounding the answer before synthesis.", chips: ["search_library", "summarize_document"], accent: Color(hex: 0x4FC98C))
        ToolCallIndicator(label: "Checking calendar…", detail: "Waiting for approval before creating the event.", chips: ["create_event"], accent: Color(hex: 0xE2A94B))
    }
    .padding()
    .background(Theme.bg)
}
