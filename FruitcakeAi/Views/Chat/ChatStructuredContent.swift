//
//  ChatStructuredContent.swift
//  FruitcakeAi
//
//  Reusable rendering for typed assistant content blocks. The backend keeps
//  the original Markdown alongside normalized data so this view can offer a
//  native table/chart without making the generated prose the source of truth.
//

import SwiftUI
import Charts
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct ChatNewsDigestBlockView: View {
    let block: ChatContentBlock
    let accent: Color

    private var storyCount: Int {
        block.sections.reduce(0) { $0 + $1.items.count }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "newspaper")
                    .foregroundStyle(accent)
                Text((block.title ?? "News Briefing").uppercased())
                    .font(Theme.mono(10.5).weight(.semibold))
                    .tracking(1.1)
                    .foregroundStyle(Theme.textMid)
                Spacer(minLength: 12)
                Text(storyCount == 1 ? "1 story" : "\(storyCount) stories")
                    .font(Theme.mono(9.5))
                    .foregroundStyle(Theme.textFaint)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)

            Rectangle()
                .fill(Theme.stroke)
                .frame(height: 1)

            ForEach(Array(block.sections.enumerated()), id: \.element.id) { sectionIndex, section in
                VStack(alignment: .leading, spacing: 0) {
                    Text(section.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 14)
                        .padding(.top, sectionIndex == 0 ? 12 : 16)
                        .padding(.bottom, 5)

                    ForEach(Array(section.items.enumerated()), id: \.element.id) { itemIndex, item in
                        newsItem(item, index: itemIndex)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.065), lineWidth: 1)
        )
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
    }

    private func newsItem(_ item: ChatNewsItem, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text(String(format: "%02d", index + 1))
                    .font(Theme.mono(9.5).weight(.semibold))
                    .foregroundStyle(accent.opacity(0.75))
                    .frame(width: 20, alignment: .leading)

                VStack(alignment: .leading, spacing: 5) {
                    Text(item.title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)

                    if !item.summary.isEmpty {
                        Text(item.summary)
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.textMid)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if !item.sources.isEmpty {
                        HStack(spacing: 10) {
                            ForEach(item.sources) { source in
                                if let url = URL(string: source.url) {
                                    Link(destination: url) {
                                        HStack(spacing: 3) {
                                            Text(source.label)
                                            Image(systemName: "arrow.up.right")
                                                .font(.system(size: 7.5, weight: .bold))
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .font(Theme.mono(9.5).weight(.medium))
                                    .foregroundStyle(accent)
                                }
                            }
                        }
                    }
                }
            }

            Rectangle()
                .fill(Theme.stroke.opacity(0.7))
                .frame(height: 1)
                .padding(.leading, 29)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }
}

struct ChatStructuredTableBlockView: View {
    let block: ChatContentBlock
    let accent: Color
    let allowsExpansion: Bool

    @State private var presentation: Presentation = .table
    @State private var copied = false
    @State private var showingExpanded = false
    @State private var columnWidths: [CGFloat]

    init(block: ChatContentBlock, accent: Color, allowsExpansion: Bool = true) {
        self.block = block
        self.accent = accent
        self.allowsExpansion = allowsExpansion
        _columnWidths = State(initialValue: Self.initialColumnWidths(for: block))
    }

    private enum Presentation: String, CaseIterable, Identifiable {
        case table = "Table"
        case chart = "Chart"
        var id: String { rawValue }
    }

    private struct ChartPoint: Identifiable {
        let category: String
        let series: String
        let value: Double
        var id: String { "\(category):\(series)" }
    }

    @ViewBuilder
    var body: some View {
        #if os(macOS)
        content
        #else
        content
            .sheet(isPresented: $showingExpanded) {
                ExpandedStructuredTableContent(block: block, accent: accent)
            }
        #endif
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if presentation == .chart, canChart {
                chart
            } else {
                ResizableChatTable(
                    block: block,
                    accent: accent,
                    columnWidths: $columnWidths,
                    allowsVerticalScrolling: !allowsExpansion
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.065), lineWidth: 1)
        )
        .padding(.horizontal, allowsExpansion ? 13 : 0)
        .padding(.vertical, allowsExpansion ? 8 : 0)
        .onChange(of: canChart) { _, available in
            if !available { presentation = .table }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Label("Data", systemImage: "tablecells")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Theme.textMid)

            Spacer(minLength: 8)

            if canChart {
                Picker("Presentation", selection: $presentation) {
                    ForEach(Presentation.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 132)
            }

            if allowsExpansion {
                Button {
                    #if os(macOS)
                    StructuredDataWindowController.open(block: block, accent: accent)
                    #else
                    showingExpanded = true
                    #endif
                } label: {
                    Label("Open Window", systemImage: "macwindow.on.rectangle")
                }
                .buttonStyle(.plain)
                .font(Theme.mono(10))
                .foregroundStyle(accent)
                .help("Open this data in a separate resizable window")
            }

            Button(copied ? "Copied" : "Copy CSV") {
                copyCSV()
            }
            .buttonStyle(.plain)
            .font(Theme.mono(10))
            .foregroundStyle(copied ? Theme.ok : accent)
        }
    }

    @ViewBuilder
    private var chart: some View {
        if chartKind == "line" {
            Chart(chartPoints) { point in
                LineMark(
                    x: .value("Category", point.category),
                    y: .value("Value", point.value)
                )
                .foregroundStyle(by: .value("Series", point.series))
                .interpolationMethod(.catmullRom)

                PointMark(
                    x: .value("Category", point.category),
                    y: .value("Value", point.value)
                )
                .foregroundStyle(by: .value("Series", point.series))
            }
            .chartForegroundStyleScale(range: chartColors)
            .chartLegend(position: .bottom, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: allowsExpansion ? 230 : 480, alignment: .leading)
        } else {
            Chart(chartPoints) { point in
                BarMark(
                    x: .value("Category", point.category),
                    y: .value("Value", point.value)
                )
                .foregroundStyle(by: .value("Series", point.series))
                .position(by: .value("Series", point.series))
            }
            .chartForegroundStyleScale(range: chartColors)
            .chartLegend(position: .bottom, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: allowsExpansion ? 230 : 480, alignment: .leading)
        }
    }

    private var chartHint: ChatChartHint? { block.chart }
    private var chartKind: String { chartHint?.kind ?? "bar" }

    private var canChart: Bool {
        guard chartHint != nil else { return false }
        return !chartPoints.isEmpty
    }

    private var chartPoints: [ChartPoint] {
        guard let hint = chartHint,
              block.columns.indices.contains(hint.categoryColumn)
        else { return [] }

        return block.rows.flatMap { row -> [ChartPoint] in
            guard row.indices.contains(hint.categoryColumn) else { return [] }
            let category = row[hint.categoryColumn]
            return hint.valueColumns.compactMap { index in
                guard block.columns.indices.contains(index),
                      row.indices.contains(index),
                      let value = numericValue(row[index])
                else { return nil }
                return ChartPoint(category: category, series: block.columns[index], value: value)
            }
        }
    }

    private var chartColors: [Color] {
        [accent, Theme.ok, .orange, .cyan, .yellow, .pink]
    }

    private func numericValue(_ raw: String) -> Double? {
        let allowed = raw.filter { "0123456789.-".contains($0) }
        guard !allowed.isEmpty, allowed != "-", allowed != "." else { return nil }
        return Double(allowed)
    }

    private func copyCSV() {
        let lines = [block.columns] + block.rows
        let value = lines
            .map { $0.map(csvCell).joined(separator: ",") }
            .joined(separator: "\n")
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        #else
        UIPasteboard.general.string = value
        #endif
        copied = true
    }

    private func csvCell(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else { return value }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func initialColumnWidths(for block: ChatContentBlock) -> [CGFloat] {
        block.columns.indices.map { index in
            let values = [block.columns[index]] + block.rows.compactMap { row in
                row.indices.contains(index) ? row[index] : nil
            }
            let longest = values.map(\.count).max() ?? 12
            return min(max(CGFloat(longest) * 6.5 + 30, 110), 280)
        }
    }
}

private struct ResizableChatTable: View {
    let block: ChatContentBlock
    let accent: Color
    @Binding var columnWidths: [CGFloat]
    let allowsVerticalScrolling: Bool

    @State private var activeResizeIndex: Int?
    @State private var resizeStartWidth: CGFloat = 0

    @ViewBuilder
    var body: some View {
        if allowsVerticalScrolling {
            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                tableContent
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            // The conversation already owns vertical scrolling. A nested
            // vertical ScrollView causes LazyVStack to cache the wrong row
            // height when multiple tables and prose share one response.
            ScrollView(.horizontal, showsIndicators: true) {
                tableContent
                    .fixedSize(horizontal: true, vertical: false)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var tableContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            row(block.columns, isHeader: true, rowIndex: nil)
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
            ForEach(Array(block.rows.enumerated()), id: \.offset) { index, values in
                row(values, isHeader: false, rowIndex: index)
                if index < block.rows.count - 1 {
                    Rectangle().fill(Color.white.opacity(0.035)).frame(height: 1)
                }
            }
        }
        .padding(.horizontal, 2)
    }

    private func row(_ values: [String], isHeader: Bool, rowIndex: Int?) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(block.columns.indices, id: \.self) { columnIndex in
                ZStack(alignment: .trailing) {
                    cellText(cell(values, at: columnIndex))
                        .font(.system(size: 11, weight: isHeader ? .semibold : .regular))
                        .foregroundStyle(cellColor(isHeader: isHeader, rowIndex: rowIndex))
                        .tint(accent)
                        .textSelection(.enabled)
                        .lineLimit(isHeader ? 2 : 4)
                        .frame(width: width(at: columnIndex) - 20, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, isHeader ? 8 : 7)

                    if columnIndex < block.columns.count - 1 {
                        resizeHandle(columnIndex)
                    }
                }
                .frame(width: width(at: columnIndex), alignment: .leading)
                .background(rowBackground(rowIndex))
            }
        }
    }

    private func resizeHandle(_ index: Int) -> some View {
        Rectangle()
            .fill(activeResizeIndex == index ? Theme.textDim.opacity(0.65) : Color.white.opacity(0.09))
            .frame(width: activeResizeIndex == index ? 2 : 1)
            .frame(maxHeight: .infinity)
            .overlay {
                Color.clear
                    .frame(width: 12)
                    .contentShape(Rectangle())
                    .gesture(resizeGesture(index))
                    #if os(macOS)
                    .onHover { hovering in
                        if hovering {
                            NSCursor.resizeLeftRight.set()
                        } else {
                            NSCursor.arrow.set()
                        }
                    }
                    #endif
            }
    }

    private func resizeGesture(_ index: Int) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard columnWidths.indices.contains(index) else { return }
                if activeResizeIndex != index {
                    activeResizeIndex = index
                    resizeStartWidth = columnWidths[index]
                }
                columnWidths[index] = min(max(resizeStartWidth + value.translation.width, 80), 520)
            }
            .onEnded { _ in
                activeResizeIndex = nil
            }
    }

    private func width(at index: Int) -> CGFloat {
        columnWidths.indices.contains(index) ? columnWidths[index] : 140
    }

    private func cell(_ values: [String], at index: Int) -> String {
        values.indices.contains(index) ? values[index] : ""
    }

    @ViewBuilder
    private func cellText(_ value: String) -> some View {
        if let attributed = attributedCell(value) {
            Text(attributed)
        } else {
            Text(value)
        }
    }

    /// Preserve inline Markdown styling and links, then linkify bare URLs and
    /// domains that models commonly place in table cells without Markdown.
    private func attributedCell(_ value: String) -> AttributedString? {
        guard let markdown = try? AttributedString(
            markdown: value,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) else { return nil }

        let rendered = String(markdown.characters)
        guard let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.link.rawValue
        ) else { return markdown }

        let mutable = NSMutableAttributedString(attributedString: NSAttributedString(markdown))
        let range = NSRange(rendered.startIndex..<rendered.endIndex, in: rendered)
        for match in detector.matches(in: rendered, range: range) {
            guard let url = match.url else { continue }
            mutable.addAttribute(.link, value: url, range: match.range)
        }
        return AttributedString(mutable)
    }

    private func cellColor(isHeader: Bool, rowIndex: Int?) -> Color {
        if isHeader { return Theme.text }
        return (rowIndex ?? 0).isMultiple(of: 2) ? Theme.textMid : Theme.textDim
    }

    private func rowBackground(_ rowIndex: Int?) -> Color {
        guard let rowIndex else { return Color.white.opacity(0.025) }
        return rowIndex.isMultiple(of: 2) ? Color.clear : Color.white.opacity(0.012)
    }
}

private struct ExpandedStructuredTableContent: View {
    let block: ChatContentBlock
    let accent: Color

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Structured Data")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text("Resize columns, switch views, or copy the data as CSV.")
                        .font(Theme.mono(10.5))
                        .foregroundStyle(Theme.textDim)
                }
                Spacer()
            }
            .padding(18)

            Rectangle().fill(Theme.stroke).frame(height: 1)

            ChatStructuredTableBlockView(
                block: block,
                accent: accent,
                allowsExpansion: false
            )
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(Theme.bg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#if os(macOS)
@MainActor
private final class StructuredDataWindowController: NSWindowController, NSWindowDelegate {
    private static var activeWindows: [UUID: StructuredDataWindowController] = [:]

    private let windowID: UUID

    static func open(block: ChatContentBlock, accent: Color) {
        let id = UUID()
        let controller = StructuredDataWindowController(id: id, block: block, accent: accent)
        activeWindows[id] = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    private init(id: UUID, block: ChatContentBlock, accent: Color) {
        windowID = id
        let content = ExpandedStructuredTableContent(block: block, accent: accent)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_150, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Structured Data"
        window.minSize = NSSize(width: 640, height: 420)
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.contentViewController = NSHostingController(rootView: content)
        window.center()
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func windowWillClose(_ notification: Notification) {
        Self.activeWindows[windowID] = nil
    }
}
#endif

#Preview {
    ChatStructuredTableBlockView(
        block: ChatContentBlock(
            id: "benchmark",
            type: "table",
            sourceMarkdown: "",
            columns: ["Benchmark", "Qwen 3.6", "Qwen 3.8"],
            rows: [
                ["DeepSWE 1.1", "13.3", "42.2"],
                ["SWE-bench Pro", "53.5", "61.7"],
                ["Terminal-Bench", "63.4", "73.0"]
            ],
            chart: ChatChartHint(kind: "bar", categoryColumn: 0, valueColumns: [1, 2])
        ),
        accent: Color(hex: 0x3F8C8F)
    )
    .padding()
    .frame(width: 900)
    .background(Theme.bg)
}
