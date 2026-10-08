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
import MapKit
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Single dispatch point for versioned assistant content blocks. Unknown
/// versions/types remain in the original prose because the parser ignores them.
struct ChatStructuredContentBlockView: View {
    let block: ChatContentBlock
    let accent: Color
    var fallbackSources: [ChatNewsSource] = []
    var onContextHandback: ((ChatNativeContextAttachment) -> Void)? = nil

    @ViewBuilder
    var body: some View {
        switch block.kind {
        case .table:
            ChatStructuredTableBlockView(
                block: block,
                accent: accent,
                onContextHandback: onContextHandback
            )
        case .newsDigest:
            ChatNewsDigestBlockView(block: block, accent: accent)
        case .statGroup:
            ChatStatGroupBlockView(block: block, accent: accent)
        case .timeline:
            ChatTimelineBlockView(
                block: block,
                accent: accent,
                fallbackSources: fallbackSources
            )
        case .fileArtifact:
            ChatFileArtifactBlockView(
                block: block,
                accent: accent,
                onContextHandback: onContextHandback
            )
        case .placeGroup:
            ChatPlaceGroupBlockView(
                block: block,
                accent: accent,
                onContextHandback: onContextHandback
            )
        case .codeArtifact:
            ChatCodeArtifactBlockView(block: block, accent: accent)
        case .html, .svg:
            EmptyView()
        case nil:
            EmptyView()
        }
    }
}

struct ChatCodeArtifactBlockView: View {
    let block: ChatContentBlock
    let accent: Color

    @Environment(AuthManager.self) private var authManager
    @State private var copied = false
    @State private var isOpening = false
    @State private var errorMessage: String?

    var body: some View {
        if let artifact = block.code {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 9) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .foregroundStyle(accent)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(block.title ?? artifact.filename ?? "Code")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                        if let path = artifact.path, !path.isEmpty {
                            Text(path)
                                .font(Theme.mono(9))
                                .foregroundStyle(Theme.textFaint)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }

                    Spacer(minLength: 10)

                    Text(artifact.language.uppercased())
                        .font(Theme.mono(8.5).weight(.semibold))
                        .tracking(0.6)
                        .foregroundStyle(Theme.textFaint)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.04), in: Capsule())

                    Button(copied ? "Copied" : "Copy") {
                        copyCode(artifact.content)
                        copied = true
                    }
                    .buttonStyle(.plain)
                    .font(Theme.mono(9.5).weight(.medium))
                    .foregroundStyle(copied ? Theme.ok : accent)

                    if let path = artifact.path, !path.isEmpty {
                        Button {
                            Task { await open(artifact, path: path) }
                        } label: {
                            if isOpening {
                                ProgressView().controlSize(.small)
                            } else {
                                Label("Open", systemImage: "arrow.up.forward.app")
                            }
                        }
                        .buttonStyle(.plain)
                        .font(Theme.mono(9.5).weight(.medium))
                        .foregroundStyle(accent)
                        .disabled(isOpening)
                    }
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 10)

                Rectangle()
                    .fill(Theme.stroke)
                    .frame(height: 1)

                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(alignment: .top, spacing: 13) {
                        Text(lineNumbers(for: artifact.content))
                            .font(Theme.mono(11))
                            .foregroundStyle(Theme.textFaint.opacity(0.75))
                            .multilineTextAlignment(.trailing)
                            .textSelection(.disabled)

                        Rectangle()
                            .fill(Theme.stroke.opacity(0.8))
                            .frame(width: 1)
                            .frame(maxHeight: .infinity)

                        Text(artifact.content)
                            .font(Theme.mono(11.5))
                            .foregroundStyle(Theme.textMid)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: true, vertical: true)
                    }
                    .padding(13)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(Theme.mono(9.5))
                        .foregroundStyle(Theme.onDevice)
                        .padding(.horizontal, 13)
                        .padding(.bottom, 10)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.065), lineWidth: 1)
            )
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
        }
    }

    private func lineNumbers(for content: String) -> String {
        let count = max(content.split(separator: "\n", omittingEmptySubsequences: false).count, 1)
        return (1...count).map(String.init).joined(separator: "\n")
    }

    private func copyCode(_ content: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
        #else
        UIPasteboard.general.string = content
        #endif
    }

    @MainActor
    private func open(_ artifact: ChatCodeArtifact, path: String) async {
        guard !isOpening else { return }
        guard let request = fileRequest(path: path) else {
            errorMessage = "Not connected"
            return
        }
        isOpening = true
        errorMessage = nil
        defer { isOpening = false }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                errorMessage = "File download failed"
                return
            }
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("FruitcakeArtifacts", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let requestedName = artifact.filename ?? URL(fileURLWithPath: path).lastPathComponent
            let safeName = (requestedName as NSString).lastPathComponent
            let localURL = directory.appendingPathComponent(safeName.isEmpty ? "code.txt" : safeName)
            try data.write(to: localURL, options: .atomic)
            #if os(macOS)
            NSWorkspace.shared.open(localURL)
            #else
            await UIApplication.shared.open(localURL)
            #endif
        } catch {
            errorMessage = "File download failed"
        }
    }

    private func fileRequest(path: String) -> URLRequest? {
        guard let baseURL = authManager.serverURL,
              let token = try? authManager.token() else { return nil }
        let url = baseURL.appendingPathComponent("workspace/files")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "path", value: path)]
        guard let finalURL = components?.url else { return nil }
        var request = URLRequest(url: finalURL)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60
        return request
    }
}

struct ChatPlaceGroupBlockView: View {
    let block: ChatContentBlock
    let accent: Color
    var onContextHandback: ((ChatNativeContextAttachment) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "mappin.and.ellipse")
                    .foregroundStyle(accent)
                Text((block.title ?? "Places").uppercased())
                    .font(Theme.mono(10.5).weight(.semibold))
                    .tracking(1.1)
                    .foregroundStyle(Theme.textMid)
                Spacer(minLength: 12)
                if let provider = block.provider, !provider.isEmpty {
                    Text(provider.uppercased())
                        .font(Theme.mono(8.5).weight(.medium))
                        .tracking(0.5)
                        .foregroundStyle(Theme.textFaint)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)

            Rectangle()
                .fill(Theme.stroke)
                .frame(height: 1)

            ForEach(Array(block.places.enumerated()), id: \.element.id) { index, place in
                placeRow(place, index: index)
                if index < block.places.count - 1 {
                    Rectangle()
                        .fill(Theme.stroke.opacity(0.7))
                        .frame(height: 1)
                        .padding(.leading, 48)
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

    private func placeRow(_ place: ChatPlace, index: Int) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Text("\(index + 1)")
                .font(Theme.mono(10).weight(.semibold))
                .foregroundStyle(accent)
                .frame(width: 26, height: 26)
                .background(accent.opacity(0.1), in: Circle())

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(place.name)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)

                    if let priceRange = place.priceRange, !priceRange.isEmpty {
                        Text(priceRange)
                            .font(Theme.mono(9.5))
                            .foregroundStyle(Theme.textFaint)
                    }
                }

                if let category = place.category, !category.isEmpty {
                    Text(category)
                        .font(Theme.mono(9.5).weight(.medium))
                        .foregroundStyle(accent.opacity(0.9))
                }

                if let address = place.address, !address.isEmpty {
                    Text(address)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textMid)
                        .fixedSize(horizontal: false, vertical: true)
                }

                metadata(place)
            }

            Spacer(minLength: 10)

            VStack(alignment: .trailing, spacing: 7) {
                if let onContextHandback {
                    Button {
                        onContextHandback(contextAttachment(for: place))
                    } label: {
                        Label("Ask", systemImage: "text.bubble")
                    }
                    .buttonStyle(.plain)
                    .font(Theme.mono(9.5).weight(.medium))
                    .foregroundStyle(accent)
                }

                if mapsURL(for: place) != nil {
                    Button {
                        openInMaps(place)
                    } label: {
                        Label("Maps", systemImage: "arrow.triangle.turn.up.right.diamond")
                    }
                    .buttonStyle(.plain)
                    .font(Theme.mono(9.5).weight(.medium))
                    .foregroundStyle(accent)
                }

                if let rawURL = place.url, let websiteURL = safeWebURL(rawURL) {
                    Link(destination: websiteURL) {
                        Label("Website", systemImage: "arrow.up.right")
                    }
                    .buttonStyle(.plain)
                    .font(Theme.mono(9.5).weight(.medium))
                    .foregroundStyle(accent)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    @ViewBuilder
    private func metadata(_ place: ChatPlace) -> some View {
        let hasRating = place.rating != nil
        let hasDistance = place.distance != nil && !(place.distanceUnit ?? "").isEmpty
        let hasPhone = !(place.phone ?? "").isEmpty
        if hasRating || hasDistance || hasPhone {
            HStack(spacing: 10) {
                if let rating = place.rating {
                    Label {
                        Text(rating.formatted(.number.precision(.fractionLength(1))))
                        if let reviewCount = place.reviewCount {
                            Text("(\(reviewCount))")
                                .foregroundStyle(Theme.textFaint)
                        }
                    } icon: {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                    }
                }
                if let distance = place.distance, let unit = place.distanceUnit, !unit.isEmpty {
                    Label("\(distance.formatted(.number.precision(.fractionLength(0...1)))) \(unit)", systemImage: "location")
                }
                if let phone = place.phone, !phone.isEmpty {
                    Text(phone)
                }
            }
            .font(Theme.mono(9.5))
            .foregroundStyle(Theme.textMid)
        }
    }

    private func mapsURL(for place: ChatPlace) -> URL? {
        var components = URLComponents(string: "https://maps.apple.com/")
        var queryItems = [URLQueryItem(name: "q", value: place.name)]
        if let latitude = place.latitude, let longitude = place.longitude {
            queryItems.append(URLQueryItem(name: "ll", value: "\(latitude),\(longitude)"))
        } else if let address = place.address, !address.isEmpty {
            queryItems[0] = URLQueryItem(name: "q", value: "\(place.name), \(address)")
        } else {
            return nil
        }
        components?.queryItems = queryItems
        return components?.url
    }

    private func openInMaps(_ place: ChatPlace) {
        if let latitude = place.latitude, let longitude = place.longitude {
            let placemark = MKPlacemark(
                coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            )
            let mapItem = MKMapItem(placemark: placemark)
            mapItem.name = place.name
            mapItem.openInMaps()
            return
        }
        guard let url = mapsURL(for: place) else { return }
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        UIApplication.shared.open(url)
        #endif
    }

    private func safeWebURL(_ value: String) -> URL? {
        guard let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            return nil
        }
        return url
    }

    private func contextAttachment(for place: ChatPlace) -> ChatNativeContextAttachment {
        var lines = ["- Name: \(place.name)"]
        if let category = place.category, !category.isEmpty { lines.append("- Category: \(category)") }
        if let address = place.address, !address.isEmpty { lines.append("- Address: \(address)") }
        if let rating = place.rating {
            let reviews = place.reviewCount.map { ", \($0) reviews" } ?? ""
            lines.append("- Rating: \(rating)\(reviews)")
        }
        if let priceRange = place.priceRange, !priceRange.isEmpty { lines.append("- Price: \(priceRange)") }
        if let distance = place.distance, let unit = place.distanceUnit, !unit.isEmpty {
            lines.append("- Distance: \(distance) \(unit)")
        }
        if let phone = place.phone, !phone.isEmpty { lines.append("- Phone: \(phone)") }
        if let url = place.url, safeWebURL(url) != nil { lines.append("- Website: \(url)") }
        return ChatNativeContextAttachment(
            blockId: block.id,
            sourceFingerprint: block.sourceFingerprint,
            title: place.name,
            kind: "place",
            selectionSummary: "One selected place",
            content: lines.joined(separator: "\n")
        )
    }
}

struct ChatFileArtifactBlockView: View {
    let block: ChatContentBlock
    let accent: Color
    var onContextHandback: ((ChatNativeContextAttachment) -> Void)? = nil

    @Environment(AuthManager.self) private var authManager
    @Environment(ArtifactInspectorState.self) private var artifactInspector
    @State private var copied = false
    @State private var isOpening = false
    @State private var errorMessage: String?

    var body: some View {
        if let artifact = block.file {
            HStack(spacing: 12) {
                Image(systemName: fileIcon(for: artifact))
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(accent)
                    .frame(width: 38, height: 38)
                    .background(accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text(artifact.filename)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)

                    HStack(spacing: 7) {
                        Text(artifact.operation == "appended" ? "UPDATED" : "CREATED")
                            .font(Theme.mono(9).weight(.semibold))
                            .tracking(0.6)
                            .foregroundStyle(accent)
                        Text(artifact.path)
                            .font(Theme.mono(9.5))
                            .foregroundStyle(Theme.textFaint)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(Theme.mono(9.5))
                            .foregroundStyle(Theme.onDevice)
                    }
                }

                Spacer(minLength: 10)

                if let onContextHandback {
                    Button {
                        onContextHandback(contextAttachment(for: artifact))
                    } label: {
                        Label("Ask", systemImage: "text.bubble")
                    }
                    .buttonStyle(.plain)
                    .font(Theme.mono(10.5))
                    .foregroundStyle(accent)
                }

                Button(copied ? "Copied" : "Copy Path") {
                    copyPath(artifact.path)
                    copied = true
                }
                .buttonStyle(.plain)
                .font(Theme.mono(10.5))
                .foregroundStyle(copied ? Theme.ok : accent)

                Button {
                    artifactInspector.open(
                        ArtifactReference(
                            id: "chat:\(block.id):\(artifact.path)",
                            path: artifact.path,
                            filename: artifact.filename,
                            mediaType: artifact.mediaType,
                            title: artifact.filename,
                            origin: .chat(sessionID: nil)
                        )
                    )
                } label: {
                    Label("Preview", systemImage: "sidebar.trailing")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button {
                    Task { await open(artifact) }
                } label: {
                    if isOpening {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("External", systemImage: "arrow.up.forward.app")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isOpening)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(13)
            .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.065), lineWidth: 1)
            )
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
        }
    }

    private func fileIcon(for artifact: ChatFileArtifact) -> String {
        if artifact.mediaType == "application/pdf" { return "doc.richtext" }
        if artifact.mediaType.contains("spreadsheet") || artifact.mediaType == "text/csv" {
            return "tablecells"
        }
        if artifact.mediaType.hasPrefix("image/") { return "photo" }
        if artifact.mediaType.hasPrefix("text/") { return "doc.text" }
        return "doc"
    }

    private func copyPath(_ path: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
        #else
        UIPasteboard.general.string = path
        #endif
    }

    private func contextAttachment(for artifact: ChatFileArtifact) -> ChatNativeContextAttachment {
        ChatNativeContextAttachment(
            blockId: block.id,
            sourceFingerprint: block.sourceFingerprint,
            title: artifact.filename,
            kind: "file",
            selectionSummary: "Workspace file reference",
            content: """
            - Filename: \(artifact.filename)
            - Workspace path: `\(artifact.path)`
            - Media type: \(artifact.mediaType)
            - Operation: \(artifact.operation)
            """
        )
    }

    @MainActor
    private func open(_ artifact: ChatFileArtifact) async {
        guard !isOpening else { return }
        guard let request = fileRequest(path: artifact.path) else {
            errorMessage = "Not connected"
            return
        }
        isOpening = true
        errorMessage = nil
        defer { isOpening = false }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                errorMessage = "File download failed"
                return
            }
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("FruitcakeArtifacts", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let safeName = (artifact.filename as NSString).lastPathComponent
            let localURL = directory.appendingPathComponent(safeName.isEmpty ? "artifact" : safeName)
            try data.write(to: localURL, options: .atomic)
            #if os(macOS)
            NSWorkspace.shared.open(localURL)
            #else
            await UIApplication.shared.open(localURL)
            #endif
        } catch {
            errorMessage = "File download failed"
        }
    }

    private func fileRequest(path: String) -> URLRequest? {
        guard let baseURL = authManager.serverURL,
              let token = try? authManager.token() else { return nil }
        let url = baseURL.appendingPathComponent("workspace/files")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "path", value: path)]
        guard let finalURL = components?.url else { return nil }
        var request = URLRequest(url: finalURL)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60
        return request
    }
}

struct ChatTimelineBlockView: View {
    let block: ChatContentBlock
    let accent: Color
    let fallbackSources: [ChatNewsSource]
    @Environment(\.openURL) private var openURL
    @State private var expandedEventID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                    .foregroundStyle(accent)
                Text((block.title ?? "Timeline").uppercased())
                    .font(Theme.mono(10.5).weight(.semibold))
                    .tracking(1.1)
                    .foregroundStyle(Theme.textMid)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)

            Rectangle()
                .fill(Theme.stroke)
                .frame(height: 1)

            ForEach(Array(block.events.enumerated()), id: \.element.id) { index, event in
                HStack(alignment: .top, spacing: 11) {
                    VStack(spacing: 0) {
                        Circle()
                            .fill(accent)
                            .frame(width: 7, height: 7)
                            .padding(.top, 4)

                        if index < block.events.count - 1 {
                            Rectangle()
                                .fill(accent.opacity(0.25))
                                .frame(width: 1)
                                .frame(minHeight: 34)
                        }
                    }
                    .frame(width: 9)

                    VStack(alignment: .leading, spacing: 7) {
                        let eventSources = sources(for: event)
                        if eventSources.isEmpty {
                            eventText(event, sourceCount: 0, usesSharedSources: false)
                        } else {
                            Button {
                                openOrReveal(event, sources: eventSources)
                            } label: {
                                eventText(
                                    event,
                                    sourceCount: eventSources.count,
                                    usesSharedSources: event.sources.isEmpty
                                )
                            }
                            .buttonStyle(.plain)
                            .contentShape(Rectangle())
                            .help(
                                eventSources.count == 1
                                    ? "Open source article"
                                    : "Show related source articles"
                            )
                        }

                        if expandedEventID == event.id, eventSources.count > 1 {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 7) {
                                    ForEach(eventSources) { source in
                                        if let url = URL(string: source.url) {
                                            Link(destination: url) {
                                                HStack(spacing: 4) {
                                                    Text(source.label)
                                                        .lineLimit(1)
                                                    Image(systemName: "arrow.up.right")
                                                        .font(.system(size: 7, weight: .bold))
                                                }
                                                .font(Theme.mono(9.5).weight(.medium))
                                                .foregroundStyle(accent)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 5)
                                                .background(accent.opacity(0.09), in: Capsule())
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.bottom, index < block.events.count - 1 ? 8 : 0)
                }
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 12)
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

    @ViewBuilder
    private func eventText(
        _ event: ChatTimelineEvent,
        sourceCount: Int,
        usesSharedSources: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(event.label.uppercased())
                    .font(Theme.mono(9.5).weight(.semibold))
                    .tracking(0.5)
                    .foregroundStyle(accent)

                Spacer(minLength: 8)

                if sourceCount > 0 {
                    HStack(spacing: 4) {
                        Text(sourceCount == 1 ? "SOURCE" : "\(sourceCount) SOURCES")
                        Image(systemName: sourceCount == 1 ? "arrow.up.right" : "chevron.down")
                            .rotationEffect(
                                .degrees(sourceCount > 1 && expandedEventID == event.id ? 180 : 0)
                            )
                    }
                    .font(Theme.mono(8.5).weight(.semibold))
                    .foregroundStyle(usesSharedSources ? Theme.textFaint : accent.opacity(0.85))
                }
            }

            Text(attributedDetail(event.detail))
                .font(.system(size: 13))
                .foregroundStyle(Theme.textMid)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func sources(for event: ChatTimelineEvent) -> [ChatNewsSource] {
        if !event.sources.isEmpty { return event.sources }
        return block.sources.isEmpty ? fallbackSources : block.sources
    }

    private func attributedDetail(_ value: String) -> AttributedString {
        (try? AttributedString(
            markdown: value,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(value)
    }

    private func openOrReveal(_ event: ChatTimelineEvent, sources: [ChatNewsSource]) {
        if sources.count == 1, let url = URL(string: sources[0].url) {
            openURL(url)
            return
        }
        withAnimation(.easeOut(duration: 0.16)) {
            expandedEventID = expandedEventID == event.id ? nil : event.id
        }
    }
}

struct ChatStatGroupBlockView: View {
    let block: ChatContentBlock
    let accent: Color

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 8, alignment: .topLeading)]

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                Image(systemName: "gauge.with.dots.needle.33percent")
                    .foregroundStyle(accent)
                Text((block.title ?? "Summary").uppercased())
                    .font(Theme.mono(10.5).weight(.semibold))
                    .tracking(1.1)
                    .foregroundStyle(Theme.textMid)
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(block.items) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.label.uppercased())
                            .font(Theme.mono(9))
                            .tracking(0.7)
                            .foregroundStyle(Theme.textFaint)
                        Text(item.value)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.065), lineWidth: 1)
        )
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
    }
}

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
    var onContextHandback: ((ChatNativeContextAttachment) -> Void)?

    @State private var presentation: Presentation
    @State private var copied = false
    @State private var showingExpanded = false
    @State private var columnWidths: [CGFloat]
    @State private var filterText = ""
    @State private var sortColumn: Int?
    @State private var sortAscending = true
    @State private var selectedCategory: String?
    @State private var selectedRowKeys: Set<String> = []
    @State private var showingCSVExporter = false

    init(
        block: ChatContentBlock,
        accent: Color,
        allowsExpansion: Bool = true,
        onContextHandback: ((ChatNativeContextAttachment) -> Void)? = nil
    ) {
        self.block = block
        self.accent = accent
        self.allowsExpansion = allowsExpansion
        self.onContextHandback = onContextHandback
        _columnWidths = State(initialValue: Self.savedColumnWidths(for: block) ?? Self.initialColumnWidths(for: block))
        _presentation = State(initialValue: Self.savedPresentation(for: block) ?? .table)
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
                ExpandedStructuredTableContent(
                    block: block,
                    accent: accent,
                    onContextHandback: onContextHandback
                )
            }
        #endif
    }

    private var content: some View {
        persistedContent
            .fileExporter(
                isPresented: $showingCSVExporter,
                document: ChatCSVDocument(text: csvText),
                contentType: .commaSeparatedText,
                defaultFilename: csvFilename
            ) { _ in }
    }

    private var persistedContent: some View {
        tableSurface
            .onChange(of: canChart) { _, available in
                if !available { presentation = .table }
            }
            .onChange(of: presentation) { _, value in
                UserDefaults.standard.set(value.rawValue, forKey: stateKey("presentation"))
            }
            .onChange(of: columnWidths) { _, value in
                UserDefaults.standard.set(value.map(Double.init), forKey: stateKey("widths"))
            }
            .onChange(of: filterText) { _, _ in
                selectedCategory = nil
                selectedRowKeys.removeAll()
            }
    }

    private var tableSurface: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if !allowsExpansion {
                inspectorControls
            }

            activePresentation
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
    }

    @ViewBuilder
    private var activePresentation: some View {
        if presentation == .chart, canChart {
            chart
        } else {
            ResizableChatTable(
                block: block,
                accent: accent,
                rows: displayedRows,
                columnWidths: $columnWidths,
                allowsVerticalScrolling: !allowsExpansion,
                allowsRowSelection: !allowsExpansion,
                selectedRowKeys: $selectedRowKeys
            )
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Label(block.title ?? "Data", systemImage: "tablecells")
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
                    StructuredDataWindowController.open(
                        block: block,
                        accent: accent,
                        onContextHandback: onContextHandback
                    )
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

            if let onContextHandback {
                Button {
                    onContextHandback(contextAttachment)
                } label: {
                    Label(contextActionLabel, systemImage: "text.bubble")
                }
                .buttonStyle(.plain)
                .font(Theme.mono(10))
                .foregroundStyle(accent)
                .help("Attach the current bounded data view to the chat composer")
            }

            Button(copied ? "Copied" : "Copy CSV") {
                copyCSV()
            }
            .buttonStyle(.plain)
            .font(Theme.mono(10))
            .foregroundStyle(copied ? Theme.ok : accent)

            if !allowsExpansion {
                Button {
                    showingCSVExporter = true
                } label: {
                    Label("Export CSV", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.plain)
                .font(Theme.mono(10))
                .foregroundStyle(accent)
            }
        }
    }

    private var inspectorControls: some View {
        HStack(spacing: 10) {
            TextField("Filter rows", text: $filterText)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 180, idealWidth: 260, maxWidth: 360)

            Picker("Sort", selection: $sortColumn) {
                Text("Original order").tag(Int?.none)
                ForEach(block.columns.indices, id: \.self) { index in
                    Text(block.columns[index]).tag(Int?.some(index))
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 220)

            Button {
                sortAscending.toggle()
            } label: {
                Label(
                    sortAscending ? "Ascending" : "Descending",
                    systemImage: sortAscending ? "arrow.up" : "arrow.down"
                )
            }
            .buttonStyle(.plain)
            .font(Theme.mono(9.5))
            .foregroundStyle(sortColumn == nil ? Theme.textFaint : accent)
            .disabled(sortColumn == nil)

            Spacer(minLength: 8)

            if !selectedRowKeys.isEmpty {
                Button("Clear \(selectedRowKeys.count) selected") {
                    selectedRowKeys.removeAll()
                }
                .buttonStyle(.plain)
                .font(Theme.mono(9.5))
                .foregroundStyle(accent)
            } else {
                Text("Select rows to narrow Ask About")
                    .font(Theme.mono(9.5))
                    .foregroundStyle(Theme.textFaint)
            }

            Text("\(displayedRows.count) of \(block.rows.count) rows")
                .font(Theme.mono(9.5))
                .foregroundStyle(Theme.textFaint)
        }
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: 10) {
            Chart(chartPoints) { point in
                if chartKind == "line" {
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
                } else {
                    BarMark(
                        x: .value("Category", point.category),
                        y: .value("Value", point.value)
                    )
                    .foregroundStyle(by: .value("Series", point.series))
                    .position(by: .value("Series", point.series))
                }
            }
            .chartForegroundStyleScale(range: chartColors)
            .chartLegend(position: .bottom, alignment: .leading)
            .chartXSelection(value: $selectedCategory)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: allowsExpansion ? 230 : 480, alignment: .leading)

            if let selectedCategory, !selectedChartPoints.isEmpty {
                HStack(spacing: 12) {
                    Text(selectedCategory)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    ForEach(selectedChartPoints) { point in
                        HStack(spacing: 4) {
                            Text(point.series)
                                .foregroundStyle(Theme.textFaint)
                            Text(point.value.formatted(.number.precision(.fractionLength(0...3))))
                                .foregroundStyle(accent)
                        }
                        .font(Theme.mono(9.5))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
            }
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

        return displayedRows.flatMap { row -> [ChartPoint] in
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

    private var selectedChartPoints: [ChartPoint] {
        guard let selectedCategory else { return [] }
        return chartPoints.filter { $0.category == selectedCategory }
    }

    private var displayedRows: [[String]] {
        let query = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        var rows = query.isEmpty ? block.rows : block.rows.filter { row in
            row.contains { $0.localizedCaseInsensitiveContains(query) }
        }
        guard let sortColumn else { return rows }
        rows.sort { lhs, rhs in
            let left = lhs.indices.contains(sortColumn) ? lhs[sortColumn] : ""
            let right = rhs.indices.contains(sortColumn) ? rhs[sortColumn] : ""
            let comparison: ComparisonResult
            if let leftNumber = numericValue(left), let rightNumber = numericValue(right) {
                comparison = leftNumber == rightNumber ? .orderedSame : (leftNumber < rightNumber ? .orderedAscending : .orderedDescending)
            } else {
                comparison = left.localizedStandardCompare(right)
            }
            return sortAscending ? comparison == .orderedAscending : comparison == .orderedDescending
        }
        return rows
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
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(csvText, forType: .string)
        #else
        UIPasteboard.general.string = csvText
        #endif
        copied = true
    }

    private var csvText: String {
        ([block.columns] + displayedRows)
            .map { $0.map(csvCell).joined(separator: ",") }
            .joined(separator: "\n")
    }

    private var contextActionLabel: String {
        if !selectedRowKeys.isEmpty { return "Ask About Rows" }
        return selectedCategory == nil ? "Ask About" : "Ask About Point"
    }

    private var contextAttachment: ChatNativeContextAttachment {
        let selectedRows: [[String]]
        let selectionSummary: String
        if presentation == .table, !selectedRowKeys.isEmpty {
            selectedRows = displayedRows.filter { selectedRowKeys.contains(rowKey($0)) }
            selectionSummary = "\(selectedRows.count) selected rows"
        } else if let selectedCategory, let categoryColumn = block.chart?.categoryColumn {
            selectedRows = displayedRows.filter { row in
                row.indices.contains(categoryColumn) && row[categoryColumn] == selectedCategory
            }
            selectionSummary = "Chart category \"\(selectedCategory)\""
        } else {
            selectedRows = displayedRows
            selectionSummary = filterText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Current view, \(displayedRows.count) rows"
                : "Filtered view, \(displayedRows.count) rows"
        }

        let boundedRows = Array(selectedRows.prefix(12))
        let boundedColumns = Array(block.columns.prefix(8))
        let markdownRows = boundedRows.map { row in
            boundedColumns.indices.map { index in
                let value = row.indices.contains(index) ? row[index] : ""
                return value.replacingOccurrences(of: "|", with: "\\|").prefix(160).description
            }
        }
        var lines = [
            "| " + boundedColumns.joined(separator: " | ") + " |",
            "| " + boundedColumns.map { _ in "---" }.joined(separator: " | ") + " |",
        ]
        lines.append(contentsOf: markdownRows.map { "| " + $0.joined(separator: " | ") + " |" })
        if selectedRows.count > boundedRows.count {
            lines.append("\n_\(selectedRows.count - boundedRows.count) additional rows omitted from this bounded attachment._")
        }
        return ChatNativeContextAttachment(
            blockId: block.id,
            sourceFingerprint: block.sourceFingerprint,
            title: block.title ?? "Structured Data",
            kind: presentation == .chart ? "chart" : "table",
            selectionSummary: selectionSummary,
            content: lines.joined(separator: "\n")
        )
    }

    private func rowKey(_ row: [String]) -> String {
        row.joined(separator: "\u{1F}")
    }

    private var csvFilename: String {
        let title = (block.title ?? "Fruitcake Data")
            .replacingOccurrences(of: "[^A-Za-z0-9._-]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return title.isEmpty ? "Fruitcake-Data.csv" : "\(title).csv"
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

    private func stateKey(_ suffix: String) -> String {
        Self.stateKey(for: block, suffix: suffix)
    }

    private static func stateKey(for block: ChatContentBlock, suffix: String) -> String {
        "chat.structured-table.\(block.sourceFingerprint ?? block.id).\(suffix)"
    }

    private static func savedColumnWidths(for block: ChatContentBlock) -> [CGFloat]? {
        guard let storedValues = UserDefaults.standard.array(forKey: stateKey(for: block, suffix: "widths")),
              storedValues.count == block.columns.count else { return nil }
        let values = storedValues.compactMap { ($0 as? NSNumber)?.doubleValue }
        guard values.count == storedValues.count else { return nil }
        return values.map { CGFloat(min(max($0, 80), 520)) }
    }

    private static func savedPresentation(for block: ChatContentBlock) -> Presentation? {
        guard let raw = UserDefaults.standard.string(forKey: stateKey(for: block, suffix: "presentation")) else {
            return nil
        }
        return Presentation(rawValue: raw)
    }
}

private struct ResizableChatTable: View {
    let block: ChatContentBlock
    let accent: Color
    let rows: [[String]]
    @Binding var columnWidths: [CGFloat]
    let allowsVerticalScrolling: Bool
    let allowsRowSelection: Bool
    @Binding var selectedRowKeys: Set<String>

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
            ForEach(Array(rows.enumerated()), id: \.offset) { index, values in
                row(values, isHeader: false, rowIndex: index)
                if index < rows.count - 1 {
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
                        .frame(
                            width: width(at: columnIndex) - 20,
                            alignment: alignment(at: columnIndex)
                        )
                        .padding(.horizontal, 10)
                        .padding(.vertical, isHeader ? 8 : 7)

                    if columnIndex < block.columns.count - 1 {
                        resizeHandle(columnIndex)
                    }
                }
                .frame(width: width(at: columnIndex), alignment: .leading)
                .background(rowBackground(rowIndex, values: values))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard allowsRowSelection, !isHeader else { return }
            let key = rowKey(values)
            if selectedRowKeys.contains(key) {
                selectedRowKeys.remove(key)
            } else {
                selectedRowKeys.insert(key)
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

    private func alignment(at index: Int) -> Alignment {
        guard block.columnAlignments.indices.contains(index) else { return .leading }
        switch block.columnAlignments[index] {
        case "center": return .center
        case "right": return .trailing
        default: return .leading
        }
    }

    private func cell(_ values: [String], at index: Int) -> String {
        values.indices.contains(index) ? values[index] : ""
    }

    private func rowKey(_ row: [String]) -> String {
        row.joined(separator: "\u{1F}")
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

    private func rowBackground(_ rowIndex: Int?, values: [String]) -> Color {
        guard let rowIndex else { return Color.white.opacity(0.025) }
        if allowsRowSelection, selectedRowKeys.contains(rowKey(values)) {
            return accent.opacity(0.14)
        }
        return rowIndex.isMultiple(of: 2) ? Color.clear : Color.white.opacity(0.012)
    }
}

private struct ChatCSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }

    let text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let value = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = value
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

private struct ExpandedStructuredTableContent: View {
    let block: ChatContentBlock
    let accent: Color
    var onContextHandback: ((ChatNativeContextAttachment) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(block.title ?? "Structured Data")
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
                allowsExpansion: false,
                onContextHandback: onContextHandback
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

    static func open(
        block: ChatContentBlock,
        accent: Color,
        onContextHandback: ((ChatNativeContextAttachment) -> Void)?
    ) {
        let id = UUID()
        let controller = StructuredDataWindowController(
            id: id,
            block: block,
            accent: accent,
            onContextHandback: onContextHandback
        )
        activeWindows[id] = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    private init(
        id: UUID,
        block: ChatContentBlock,
        accent: Color,
        onContextHandback: ((ChatNativeContextAttachment) -> Void)?
    ) {
        windowID = id
        let content = ExpandedStructuredTableContent(
            block: block,
            accent: accent,
            onContextHandback: onContextHandback
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_150, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = block.title ?? "Structured Data"
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
