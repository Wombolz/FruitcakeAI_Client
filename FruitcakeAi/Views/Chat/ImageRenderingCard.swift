//
//  ImageRenderingCard.swift
//  FruitcakeAi
//
//  First-class live chat card for long-running image renders. It is driven by
//  tool-call metadata before the renderer returns, then replaced by the final
//  image artifact once the assistant message is persisted.
//

import SwiftUI

struct ImageRenderLiveInfo: Equatable {
    let prompt: String
    let model: String?
    let workflow: String?
    let steps: String?
    let seed: String?
    let width: String?
    let height: String?
    let cfgScale: String?

    init?(toolDetails: [ChatLiveToolDetail]) {
        guard let detail = toolDetails.first(where: { $0.toolName == "generate_image" }) else {
            return nil
        }
        let args = detail.arguments
        let prompt = args["prompt"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.prompt = prompt.isEmpty ? "Rendering requested image" : prompt
        self.model = args["model"]
        self.workflow = args["workflow"]
        self.steps = args["steps"]
        self.seed = args["seed"]
        self.width = args["width"]
        self.height = args["height"]
        self.cfgScale = args["cfg_scale"]
    }

    var sizeLabel: String? {
        guard let width, let height, !width.isEmpty, !height.isEmpty else { return nil }
        return "\(width)x\(height)"
    }
}

struct ImageRenderingCard: View {
    let info: ImageRenderLiveInfo
    var accent: Color = Theme.onDevice

    @State private var animate = false

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    renderGlyph
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Rendering image…")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.text)
                        Text("This can take a few minutes for larger models.")
                            .font(Theme.mono(10.5))
                            .foregroundStyle(Theme.textDim)
                    }
                    Spacer(minLength: 0)
                }

                Text(info.prompt)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textMid)
                    .lineLimit(4)
                    .lineSpacing(3)

                metadataChips
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Theme.bubble)
            .overlay(alignment: .leading) {
                accent.opacity(0.65).frame(width: 2)
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
        .onAppear { animate = true }
    }

    private var renderGlyph: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    LinearGradient(
                        colors: [
                            accent.opacity(animate ? 0.35 : 0.12),
                            Color.white.opacity(animate ? 0.06 : 0.16),
                            accent.opacity(animate ? 0.14 : 0.32),
                        ],
                        startPoint: animate ? .topLeading : .bottomTrailing,
                        endPoint: animate ? .bottomTrailing : .topLeading
                    )
                )
                .frame(width: 44, height: 44)
                .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: animate)

            Image(systemName: "sparkles")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(accent)
        }
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(accent.opacity(0.3), lineWidth: 1))
    }

    @ViewBuilder
    private var metadataChips: some View {
        let values = chipValues
        if !values.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(values, id: \.self) { value in
                        Text(value)
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

    private var chipValues: [String] {
        var values: [String] = []
        if let model = info.model, !model.isEmpty { values.append(model) }
        if let workflow = info.workflow, !workflow.isEmpty { values.append(workflow) }
        if let steps = info.steps, !steps.isEmpty { values.append("\(steps) steps") }
        if let seed = info.seed, !seed.isEmpty { values.append("seed \(seed)") }
        if let size = info.sizeLabel { values.append(size) }
        if let cfg = info.cfgScale, !cfg.isEmpty { values.append("cfg \(cfg)") }
        return values
    }
}

#Preview {
    ImageRenderingCard(
        info: ImageRenderLiveInfo(
            toolDetails: [
                ChatLiveToolDetail(
                    toolName: "generate_image",
                    arguments: [
                        "prompt": "A cinematic fruitcake laboratory with glowing render machines and little robots.",
                        "model": "sd3.5-large",
                        "workflow": "FruitcakeImageLab",
                        "steps": "40",
                        "seed": "12345",
                        "width": "1024",
                        "height": "1024",
                    ]
                )
            ]
        )!
    )
    .padding()
    .background(Theme.bg)
}
