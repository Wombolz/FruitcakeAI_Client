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
    var accent: Color = Theme.textDim

    @State private var pulse = false

    var body: some View {
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
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.textDim)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(Theme.stroke, lineWidth: 1))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .onAppear { pulse = true }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        ToolCallIndicator()
        ToolCallIndicator(label: "Searching library…", accent: Color(hex: 0x4FC98C))
        ToolCallIndicator(label: "Checking calendar…", accent: Color(hex: 0xE2A94B))
    }
    .padding()
    .background(Theme.bg)
}
