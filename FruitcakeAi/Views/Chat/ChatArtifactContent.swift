import SwiftUI
import WebKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct ChatArtifactBlockView: View {
    let artifact: ChatArtifactEnvelope
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(artifact.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    if let summary = artifact.summary, !summary.isEmpty {
                        Text(summary)
                            .font(.system(size: 10.5))
                            .foregroundStyle(Theme.textFaint)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 12)
                Text(typeLabel)
                    .font(Theme.mono(8.5).weight(.semibold))
                    .tracking(0.7)
                    .foregroundStyle(Theme.textFaint)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 10)

            Rectangle().fill(Theme.stroke).frame(height: 1)

            if let content = artifact.content,
               let definition = ArtifactRendererRegistry.resolve(
                    type: artifact.type,
                    schemaVersion: artifact.schemaVersion
               ) {
                switch definition.renderer {
                case .html:
                    RestrictedArtifactWebView(content: content, kind: .html)
                        .frame(height: 320)
                case .svg:
                    RestrictedArtifactWebView(content: content, kind: .svg)
                        .frame(height: 300)
                default:
                    fallbackView
                }
            } else {
                fallbackView
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.20), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.065), lineWidth: 1)
        )
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var fallbackView: some View {
        if let fallback = artifact.fallback {
            ScrollView {
                Text(fallback.content)
                    .font(fallback.mediaType == "text/markdown" ? .system(size: 12.5) : Theme.mono(11))
                    .foregroundStyle(Theme.textMid)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(13)
            }
            .frame(maxHeight: 260)
        } else {
            Text("This artifact does not have a compatible renderer.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textFaint)
                .padding(13)
        }
    }

    private var iconName: String {
        artifact.type == "core.svg" ? "scribble.variable" : "chevron.left.forwardslash.chevron.right"
    }

    private var typeLabel: String {
        artifact.type == "core.svg" ? "SVG" : "STATIC HTML"
    }
}

private enum RestrictedArtifactKind {
    case html
    case svg
}

private func artifactDocument(content: String, kind: RestrictedArtifactKind) -> String {
    let body = kind == .svg ? "<div class=\"svg-host\">\(content)</div>" : content
    return """
    <!doctype html>
    <html>
    <head>
      <meta charset="utf-8">
      <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; style-src 'unsafe-inline'; font-src 'none'; connect-src 'none'; media-src 'none'; frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <style>
        :root { color-scheme: dark; }
        * { box-sizing: border-box; }
        body { margin: 0; padding: 16px; color: #d7d9db; background: #111315; font: 14px -apple-system, BlinkMacSystemFont, sans-serif; line-height: 1.45; }
        h1, h2, h3, h4 { color: #f0f1f2; margin: 0.7em 0 0.35em; }
        p { margin: 0.5em 0; }
        a { color: #3f8c8f; }
        code, pre { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }
        pre { padding: 10px; overflow: auto; background: #0b0d0e; border-radius: 6px; }
        table { width: 100%; border-collapse: collapse; }
        th, td { padding: 7px 9px; text-align: left; border-bottom: 1px solid #303438; }
        .svg-host { display: flex; align-items: flex-start; justify-content: flex-start; min-height: 240px; }
        .svg-host svg { max-width: 100%; max-height: 260px; }
      </style>
    </head>
    <body>\(body)</body>
    </html>
    """
}

#if os(macOS)
private struct RestrictedArtifactWebView: NSViewRepresentable {
    let content: String
    let kind: RestrictedArtifactKind

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        makeWebView(coordinator: context.coordinator)
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(artifactDocument(content: content, kind: kind), baseURL: nil)
    }

    private func makeWebView(coordinator: Coordinator) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = coordinator
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard navigationAction.navigationType == .linkActivated,
                  let url = navigationAction.request.url,
                  ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
                decisionHandler(navigationAction.navigationType == .linkActivated ? .cancel : .allow)
                return
            }
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
        }
    }
}
#else
private struct RestrictedArtifactWebView: UIViewRepresentable {
    let content: String
    let kind: RestrictedArtifactKind

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(artifactDocument(content: content, kind: kind), baseURL: nil)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard navigationAction.navigationType == .linkActivated,
                  let url = navigationAction.request.url,
                  ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
                decisionHandler(navigationAction.navigationType == .linkActivated ? .cancel : .allow)
                return
            }
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
        }
    }
}
#endif
