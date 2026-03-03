//
//  ToolCallIndicator.swift
//  FruitcakeAi
//
//  Subtle animated indicator shown in the message thread between the user's
//  message and the first streamed token. Signals that the agent is running a
//  tool (library search, calendar lookup, web research, etc.).
//

import SwiftUI

struct ToolCallIndicator: View {

    var label: String = "Working…"

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(0.7)
                .frame(width: 16, height: 16)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
        .background(.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        ToolCallIndicator()
        ToolCallIndicator(label: "Searching library…")
        ToolCallIndicator(label: "Checking calendar…")
    }
    .padding()
}
