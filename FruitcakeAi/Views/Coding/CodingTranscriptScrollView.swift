#if os(macOS)
import SwiftUI

struct CodingTranscriptGeometry: Equatable {
    let contentSize: CGSize
    let viewportSize: CGSize
    let offsetY: CGFloat
    let bottomDistance: CGFloat

    init(_ geometry: ScrollGeometry) {
        contentSize = geometry.contentSize
        viewportSize = geometry.containerSize
        offsetY = geometry.contentOffset.y
        bottomDistance = max(0, geometry.contentSize.height - geometry.visibleRect.maxY)
    }

    init(contentSize: CGSize, viewportSize: CGSize, offsetY: CGFloat, bottomDistance: CGFloat) {
        self.contentSize = contentSize
        self.viewportSize = viewportSize
        self.offsetY = offsetY
        self.bottomDistance = bottomDistance
    }

    var isNearBottom: Bool { bottomDistance <= 48 }
}

@Observable @MainActor
final class CodingTranscriptScrollState {
    private(set) var followsBottom = true
    private(set) var userIsScrolling = false
    private(set) var pinRevision = 0
    private var pinPending = true

    func jumpToLatest() {
        followsBottom = true
        pinPending = true
        pinRevision += 1
    }

    func phaseChanged(from oldPhase: ScrollPhase, to newPhase: ScrollPhase, geometry: CodingTranscriptGeometry) {
        func isUserPhase(_ phase: ScrollPhase) -> Bool {
            phase == .tracking || phase == .interacting || phase == .decelerating
        }
        userIsScrolling = isUserPhase(newPhase)
        if isUserPhase(oldPhase), newPhase == .idle {
            followsBottom = geometry.isNearBottom
            pinPending = false
        }
    }

    func geometryChanged(from old: CodingTranscriptGeometry, to new: CodingTranscriptGeometry) {
        let resized = old.contentSize != new.contentSize || old.viewportSize != new.viewportSize
        if userIsScrolling {
            // Layout changes alone are not evidence that the user scrolled up.
            if !resized || old.offsetY != new.offsetY {
                followsBottom = new.isNearBottom
                pinPending = false
            }
            return
        }
        if resized, followsBottom {
            pinPending = true
            pinRevision += 1
        } else if !resized, old.offsetY != new.offsetY {
            if new.isNearBottom {
                followsBottom = true
                pinPending = false
            } else if !pinPending || (old.isNearBottom && new.offsetY < old.offsetY) {
                // Also honor keyboard and scrollbar scrolling without a phase.
                followsBottom = false
            }
        }
    }
}

struct CodingTranscriptScrollView<Content: View>: View {
    @State private var scroll: CodingTranscriptScrollState
    private let content: Content
    private let latestRunID: String?
    private let bottomID = "coding-transcript-bottom"

    init(scroll: CodingTranscriptScrollState? = nil, latestRunID: String? = nil, @ViewBuilder content: () -> Content) {
        _scroll = State(initialValue: scroll ?? CodingTranscriptScrollState())
        self.latestRunID = latestRunID
        self.content = content()
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    content
                    Color.clear.frame(height: 1).id(bottomID)
                }
                .frame(maxWidth: .infinity)
            }
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            .onChange(of: latestRunID) { _, new in
                if new != nil { scroll.jumpToLatest() }
            }
            .onScrollPhaseChange { old, new, context in
                scroll.phaseChanged(from: old, to: new, geometry: CodingTranscriptGeometry(context.geometry))
            }
            .onScrollGeometryChange(for: CodingTranscriptGeometry.self) { CodingTranscriptGeometry($0) } action: { old, new in
                scroll.geometryChanged(from: old, to: new)
            }
            .task(id: scroll.pinRevision) {
                // Coalesce layout updates; never animate each streaming token.
                await Task.yield()
                guard !Task.isCancelled, scroll.followsBottom, !scroll.userIsScrolling else { return }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { proxy.scrollTo(bottomID, anchor: .bottom) }
            }
            .overlay(alignment: .bottomTrailing) {
                if !scroll.followsBottom {
                    Button("Jump to Latest", systemImage: "arrow.down") { scroll.jumpToLatest() }
                        .font(.system(size: 11)).buttonStyle(.bordered)
                        .padding(12)
                }
            }
        }
    }
}

struct CodingUserMessageBubble: View {
    let text: String
    var occurredAt: Date? = nil
    private var accent: Color { Theme.codeAccent }

    var body: some View {
        HStack {
            Spacer(minLength: 48)
            VStack(alignment: .trailing, spacing: 4) {
                MessageProse(text: text).font(.system(size: 13.5)).foregroundStyle(Theme.text)
                .lineSpacing(4)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(accent.opacity(0.14))
                .clipShape(.rect(topLeadingRadius: 14, bottomLeadingRadius: 14,
                                 bottomTrailingRadius: 4, topTrailingRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(accent.opacity(0.30), lineWidth: 1))
                if let occurredAt {
                    MessageTimestamp(date: occurredAt).foregroundStyle(Theme.textFaint).padding(.horizontal, 4)
                }
            }.frame(maxWidth: Theme.chatUserMaxWidth, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}
#endif
