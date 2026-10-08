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
                case .mcpApp:
                    MCPAppArtifactView(artifact: artifact, accent: accent)
                default:
                    fallbackView
                }
            } else if ArtifactRendererRegistry.resolve(
                type: artifact.type,
                schemaVersion: artifact.schemaVersion
            )?.renderer == .mcpApp {
                MCPAppArtifactView(artifact: artifact, accent: accent)
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
        if artifact.type == "core.mcp_app" { return "app.badge" }
        return artifact.type == "core.svg" ? "scribble.variable" : "chevron.left.forwardslash.chevron.right"
    }

    private var typeLabel: String {
        if artifact.type == "core.mcp_app" { return "MCP APP" }
        return artifact.type == "core.svg" ? "SVG" : "STATIC HTML"
    }
}

private struct MCPAppArtifactView: View {
    @Environment(AuthManager.self) private var authManager
    let artifact: ChatArtifactEnvelope
    let accent: Color

    @State private var resource: MCPAppResourceResponse?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let resource {
                MCPAppWebView(
                    html: restrictedMCPAppDocument(resource.html),
                    toolInput: artifact.payload?["tool_input"] ?? .object([:]),
                    toolResult: artifact.payload?["tool_result"] ?? .object([:])
                )
                .frame(minHeight: 260, idealHeight: 360, maxHeight: 520)
            } else if let errorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Interactive view unavailable")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text(errorMessage)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textFaint)
                    if let fallback = artifact.fallback {
                        Text(fallback.content)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.textMid)
                            .textSelection(.enabled)
                    }
                }
                .padding(13)
            } else {
                HStack(spacing: 9) {
                    ProgressView().controlSize(.small).tint(accent)
                    Text("Loading interactive view…")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textFaint)
                }
                .padding(13)
            }
        }
        .task(id: resourceKey) {
            await loadResource()
        }
    }

    private var resourceKey: String {
        "\(artifact.provenance?.server ?? ""):\(artifact.presentation.uiResource ?? "")"
    }

    private func loadResource() async {
        guard let server = artifact.provenance?.server, !server.isEmpty,
              let uri = artifact.presentation.uiResource, uri.hasPrefix("ui://") else {
            errorMessage = "This artifact is missing its MCP server or UI resource."
            return
        }
        do {
            resource = try await APIClient(authManager: authManager)
                .fetchMCPAppResource(server: server, uri: uri)
            errorMessage = nil
        } catch {
            resource = nil
            errorMessage = "Fruitcake could not load the MCP App resource."
        }
    }
}

private func restrictedMCPAppDocument(_ html: String) -> String {
    let policy = "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data: blob:; media-src data: blob:; connect-src 'none'; frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'"
    let meta = "<meta http-equiv=\"Content-Security-Policy\" content=\"\(policy)\">"
    if let headRange = html.range(of: "<head", options: [.caseInsensitive]),
       let close = html[headRange.lowerBound...].firstIndex(of: ">") {
        var document = html
        document.insert(contentsOf: meta, at: document.index(after: close))
        return document
    }
    return "<!doctype html><html><head>\(meta)<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"></head><body>\(html)</body></html>"
}

private extension JSONValue {
    var foundationValue: Any {
        switch self {
        case .string(let value): return value
        case .int(let value): return value
        case .double(let value): return value
        case .bool(let value): return value
        case .object(let value): return value.mapValues(\.foundationValue)
        case .array(let value): return value.map(\.foundationValue)
        case .null: return NSNull()
        }
    }
}

private final class MCPAppBridgeCoordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    weak var webView: WKWebView?
    var toolInput: JSONValue
    var toolResult: JSONValue
    private var initialized = false

    init(toolInput: JSONValue, toolResult: JSONValue) {
        self.toolInput = toolInput
        self.toolResult = toolResult
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let request = message.body as? [String: Any],
              let method = request["method"] as? String else { return }
        let id = request["id"]
        switch method {
        case "ui/initialize":
            guard let id else { return }
            send([
                "jsonrpc": "2.0",
                "id": id,
                "result": [
                    "protocolVersion": "2026-01-26",
                    "hostCapabilities": [
                        "openLinks": [:],
                        "sandbox": [
                            "permissions": [:],
                            "csp": ["connectDomains": [], "resourceDomains": []],
                        ],
                    ],
                    "hostInfo": ["name": "Fruitcake", "version": "1"],
                    "hostContext": [
                        "theme": "dark",
                        "platform": "desktop",
                        "displayMode": "inline",
                        "locale": Locale.current.identifier,
                        "timeZone": TimeZone.current.identifier,
                    ],
                ],
            ])
        case "ui/notifications/initialized":
            deliverInitialStateIfNeeded()
        case "ping":
            if let id { send(["jsonrpc": "2.0", "id": id, "result": [:]]) }
        case "ui/open-link":
            handleOpenLink(request: request, id: id)
        case "ui/notifications/size-changed", "notifications/message":
            break
        default:
            if let id {
                send([
                    "jsonrpc": "2.0",
                    "id": id,
                    "error": ["code": -32601, "message": "Method is not available in this host"],
                ])
            }
        }
    }

    func sendTeardown() {
        send(["jsonrpc": "2.0", "id": "fruitcake-teardown", "method": "ui/resource-teardown"])
    }

    private func deliverInitialStateIfNeeded() {
        guard !initialized else { return }
        initialized = true
        send([
            "jsonrpc": "2.0",
            "method": "ui/notifications/tool-input",
            "params": ["arguments": toolInput.foundationValue],
        ])
        let result = toolResult.foundationValue
        send([
            "jsonrpc": "2.0",
            "method": "ui/notifications/tool-result",
            "params": result,
        ])
    }

    private func handleOpenLink(request: [String: Any], id: Any?) {
        let params = request["params"] as? [String: Any]
        let rawURL = params?["url"] as? String
        guard let rawURL, let url = URL(string: rawURL),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            if let id {
                send(["jsonrpc": "2.0", "id": id, "error": ["code": -32602, "message": "Only HTTP(S) links are allowed"]])
            }
            return
        }
#if os(macOS)
        NSWorkspace.shared.open(url)
#else
        UIApplication.shared.open(url)
#endif
        if let id { send(["jsonrpc": "2.0", "id": id, "result": [:]]) }
    }

    private func send(_ message: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(message),
              let data = try? JSONSerialization.data(withJSONObject: message),
              let json = String(data: data, encoding: .utf8) else { return }
        let script = "window.__fruitcakeDelivering=true;try{window.dispatchEvent(new MessageEvent('message',{data:\(json)}));}finally{window.__fruitcakeDelivering=false;}"
        webView?.evaluateJavaScript(script)
    }

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
#if os(macOS)
        NSWorkspace.shared.open(url)
#else
        UIApplication.shared.open(url)
#endif
        decisionHandler(.cancel)
    }
}

private let mcpAppBridgeScript = """
window.addEventListener('message', function(event) {
  if (window.__fruitcakeDelivering) return;
  try { window.webkit.messageHandlers.mcpApp.postMessage(event.data); } catch (_) {}
});
"""

#if os(macOS)
private struct MCPAppWebView: NSViewRepresentable {
    let html: String
    let toolInput: JSONValue
    let toolResult: JSONValue

    func makeCoordinator() -> MCPAppBridgeCoordinator {
        MCPAppBridgeCoordinator(toolInput: toolInput, toolResult: toolResult)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.addUserScript(WKUserScript(
            source: mcpAppBridgeScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        configuration.userContentController.add(context.coordinator, name: "mcpApp")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        context.coordinator.webView = webView
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.loadHTMLString(html, baseURL: nil)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.toolInput = toolInput
        context.coordinator.toolResult = toolResult
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: MCPAppBridgeCoordinator) {
        coordinator.sendTeardown()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "mcpApp")
        webView.stopLoading()
    }
}
#else
private struct MCPAppWebView: UIViewRepresentable {
    let html: String
    let toolInput: JSONValue
    let toolResult: JSONValue

    func makeCoordinator() -> MCPAppBridgeCoordinator {
        MCPAppBridgeCoordinator(toolInput: toolInput, toolResult: toolResult)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.addUserScript(WKUserScript(
            source: mcpAppBridgeScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        configuration.userContentController.add(context.coordinator, name: "mcpApp")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        context.coordinator.webView = webView
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.loadHTMLString(html, baseURL: nil)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.toolInput = toolInput
        context.coordinator.toolResult = toolResult
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: MCPAppBridgeCoordinator) {
        coordinator.sendTeardown()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "mcpApp")
        webView.stopLoading()
    }
}
#endif

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
