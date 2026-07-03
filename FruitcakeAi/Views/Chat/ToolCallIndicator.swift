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

import SwiftUI

struct ToolCallIndicator: View {

    var label: String = "Working…"
    var detail: String? = nil
    var chips: [String] = []
    var accent: Color = Theme.textDim

    @State private var pulse = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
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
                Text(label)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.textMid)
                Spacer(minLength: 0)
            }
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textDim)
            }
            if !chips.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(chips, id: \.self) { chip in
                            Text(chip)
                                .font(Theme.mono(10))
                                .foregroundStyle(Theme.textDim)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Theme.bg.opacity(0.55), in: Capsule())
                                .overlay(Capsule().stroke(Theme.stroke, lineWidth: 1))
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.stroke, lineWidth: 1))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
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
