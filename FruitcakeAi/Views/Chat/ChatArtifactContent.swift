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
    var onOpenMCPApp: ((ChatArtifactEnvelope) -> Void)? = nil

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

            if artifact.type == "core.mcp_app" {
                HStack(spacing: 10) {
                    Button {
                        onOpenMCPApp?(artifact)
                    } label: {
                        Label("Open Dashboard", systemImage: "rectangle.topthird.inset.filled")
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(accent)
                    .disabled(onOpenMCPApp == nil)

                    Spacer(minLength: 0)
                    Text("Saved in this conversation")
                        .font(Theme.mono(9.5))
                        .foregroundStyle(Theme.textFaint)
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 11)
            } else if let content = artifact.content,
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
        if artifact.type == "core.mcp_app" { return "app.badge" }
        return artifact.type == "core.svg" ? "scribble.variable" : "chevron.left.forwardslash.chevron.right"
    }

    private var typeLabel: String {
        if artifact.type == "core.mcp_app" { return "MCP APP" }
        return artifact.type == "core.svg" ? "SVG" : "STATIC HTML"
    }
}

private enum MCPAppDisplayMode {
    case drawer
    case window

    var hostValue: String {
        self == .window ? "fullscreen" : "inline"
    }
}

struct MCPAppDashboardDrawer: View {
    @Environment(AuthManager.self) private var authManager
    let artifact: ChatArtifactEnvelope
    let accent: Color
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "app.badge")
                    .foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text(artifact.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text("Interactive app")
                        .font(Theme.mono(9.5))
                        .foregroundStyle(Theme.textFaint)
                }
                Spacer(minLength: 12)
                #if os(macOS)
                Button {
                    MCPAppWindowPresenter.open(
                        artifact: artifact,
                        accent: accent,
                        authManager: authManager
                    )
                } label: {
                    Label("Open Window", systemImage: "macwindow.on.rectangle")
                }
                .buttonStyle(.plain)
                .font(Theme.mono(10.5))
                .foregroundStyle(accent)
                #endif
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.textDim)
                        .frame(width: 26, height: 26)
                        .background(Theme.field, in: Circle())
                }
                .buttonStyle(.plain)
                .help("Close app panel")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)

            Rectangle().fill(Theme.stroke).frame(height: 1)

            MCPAppArtifactView(
                artifact: artifact,
                accent: accent,
                displayMode: .drawer
            )
        }
        .background(Theme.composer)
        .overlay(alignment: .bottom) {
            Rectangle().fill(accent.opacity(0.35)).frame(height: 1)
        }
        .clipped()
    }
}

private struct MCPAppArtifactView: View {
    @Environment(AuthManager.self) private var authManager
    let artifact: ChatArtifactEnvelope
    let accent: Color
    let displayMode: MCPAppDisplayMode

    @State private var resource: MCPAppResourceResponse?
    @State private var errorMessage: String?
    @State private var preferredHeight: CGFloat = 360

    var body: some View {
        Group {
            if let resource {
                VStack(spacing: 0) {
                    MCPAppWebView(
                        html: restrictedMCPAppDocument(resource.html),
                        toolInput: artifact.payload?["tool_input"] ?? .object([:]),
                        toolResult: artifact.payload?["tool_result"] ?? .object([:]),
                        server: artifact.provenance?.server ?? "",
                        resourceURI: artifact.presentation.uiResource ?? "",
                        displayMode: displayMode,
                        authManager: authManager,
                        onPreferredHeight: { height in
                            preferredHeight = min(720, max(260, height))
                        }
                    )
                    .frame(
                        minHeight: displayMode == .window ? 480 : 260,
                        idealHeight: displayMode == .window ? 700 : preferredHeight,
                        maxHeight: displayMode == .window ? .infinity : preferredHeight
                    )
                }
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

#if os(macOS)
@MainActor
private enum MCPAppWindowPresenter {
    private static var controllers: [NSWindowController] = []

    static func open(
        artifact: ChatArtifactEnvelope,
        accent: Color,
        authManager: AuthManager
    ) {
        let content = MCPAppArtifactView(
            artifact: artifact,
            accent: accent,
            displayMode: .window
        )
        .environment(authManager)
        .frame(minWidth: 820, minHeight: 560)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_180, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = artifact.title
        window.minSize = NSSize(width: 720, height: 480)
        window.contentViewController = NSHostingController(rootView: content)
        window.center()
        let controller = NSWindowController(window: window)
        controllers.append(controller)
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }
}
#endif

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

    nonisolated static func fromFoundation(_ value: Any) -> JSONValue? {
        switch value {
        case let value as String: return .string(value)
        case let value as Bool: return .bool(value)
        case let value as Int: return .int(value)
        case let value as NSNumber: return .double(value.doubleValue)
        case let value as [String: Any]:
            var object: [String: JSONValue] = [:]
            for (key, child) in value {
                guard let converted = fromFoundation(child) else { return nil }
                object[key] = converted
            }
            return .object(object)
        case let value as [Any]:
            let converted = value.compactMap(fromFoundation)
            return converted.count == value.count ? .array(converted) : nil
        case is NSNull: return .null
        default: return nil
        }
    }
}

private final class MCPAppBridgeCoordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    weak var webView: WKWebView?
    var toolInput: JSONValue
    var toolResult: JSONValue
    let server: String
    let resourceURI: String
    let displayMode: MCPAppDisplayMode
    let authManager: AuthManager
    let onPreferredHeight: (CGFloat) -> Void
    private var initialized = false

    init(
        toolInput: JSONValue,
        toolResult: JSONValue,
        server: String,
        resourceURI: String,
        displayMode: MCPAppDisplayMode,
        authManager: AuthManager,
        onPreferredHeight: @escaping (CGFloat) -> Void
    ) {
        self.toolInput = toolInput
        self.toolResult = toolResult
        self.server = server
        self.resourceURI = resourceURI
        self.displayMode = displayMode
        self.authManager = authManager
        self.onPreferredHeight = onPreferredHeight
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
                        "serverTools": [:],
                        "sandbox": [
                            "permissions": [:],
                            "csp": ["connectDomains": [], "resourceDomains": []],
                        ],
                    ],
                    "hostInfo": ["name": "Fruitcake", "version": "1"],
                    "hostContext": [
                        "theme": "dark",
                        "platform": "desktop",
                        "displayMode": displayMode.hostValue,
                        // The host owns drawer/window transitions. Do not advertise
                        // app-controlled mode switching until the bridge implements it.
                        "availableDisplayModes": [displayMode.hostValue],
                        "containerDimensions": displayMode == .drawer
                            ? ["maxHeight": 720, "maxWidth": 1_200]
                            : [:],
                        "locale": Locale.preferredLanguages.first ?? "en",
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
        case "tools/call":
            handleToolCall(request: request, id: id)
        case "ui/notifications/size-changed":
            handleSizeChanged(request: request)
        case "notifications/message":
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

    private func handleToolCall(request: [String: Any], id: Any?) {
        guard let id,
              let params = request["params"] as? [String: Any],
              let name = params["name"] as? String,
              !name.isEmpty,
              let rawArguments = params["arguments"] as? [String: Any],
              let arguments = JSONValue.fromFoundation(rawArguments) else {
            if let id {
                send(["jsonrpc": "2.0", "id": id, "error": ["code": -32602, "message": "Invalid tool call"]])
            }
            return
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let client = APIClient(authManager: authManager)
                var response = try await client.callMCPAppTool(
                    server: server,
                    resourceURI: resourceURI,
                    tool: name,
                    arguments: arguments
                )
                if response.state == "waiting_approval", let approval = response.approval {
                    let approved = await requestMutationApproval(approval)
                    response = try await client.resolveMCPAppToolApproval(
                        approvalID: approval.id,
                        approved: approved
                    )
                    if response.state == "denied" {
                        send([
                            "jsonrpc": "2.0",
                            "id": id,
                            "error": ["code": -32001, "message": "Action denied by the user"],
                        ])
                        return
                    }
                }
                guard response.state == "completed", let result = response.result else {
                    throw APIError.invalidResponse
                }
                send(["jsonrpc": "2.0", "id": id, "result": result.foundationValue])
            } catch {
                let detail = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                let message = detail.isEmpty
                    ? "Fruitcake could not complete this app tool call."
                    : String(detail.prefix(300))
                send([
                    "jsonrpc": "2.0",
                    "id": id,
                    "error": ["code": -32000, "message": message],
                ])
            }
        }
    }

    @MainActor
    private func requestMutationApproval(_ approval: MCPAppToolApproval) async -> Bool {
        let argumentText = boundedArgumentSummary(approval.arguments)
#if os(macOS)
        let alert = NSAlert()
        alert.alertStyle = approval.destructive ? .critical : .warning
        alert.messageText = approval.title
        alert.informativeText = [approval.reason, argumentText]
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        alert.addButton(withTitle: "Deny")
        alert.addButton(withTitle: "Approve")
        guard let window = webView?.window else {
            return alert.runModal() == .alertSecondButtonReturn
        }
        return await withCheckedContinuation { continuation in
            alert.beginSheetModal(for: window) { response in
                continuation.resume(returning: response == .alertSecondButtonReturn)
            }
        }
#else
        guard let presenter = webView?.window?.rootViewController else { return false }
        return await withCheckedContinuation { continuation in
            let alert = UIAlertController(
                title: approval.title,
                message: [approval.reason, argumentText].filter { !$0.isEmpty }.joined(separator: "\n\n"),
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "Deny", style: .cancel) { _ in
                continuation.resume(returning: false)
            })
            alert.addAction(UIAlertAction(title: "Approve", style: approval.destructive ? .destructive : .default) { _ in
                continuation.resume(returning: true)
            })
            presenter.present(alert, animated: true)
        }
#endif
    }

    private func boundedArgumentSummary(_ arguments: JSONValue) -> String {
        guard JSONSerialization.isValidJSONObject(arguments.foundationValue),
              let data = try? JSONSerialization.data(
                withJSONObject: arguments.foundationValue,
                options: [.prettyPrinted, .sortedKeys]
              ),
              let text = String(data: data, encoding: .utf8),
              text != "{}" else { return "" }
        return "Requested parameters:\n" + String(text.prefix(800))
    }

    private func handleSizeChanged(request: [String: Any]) {
        guard displayMode == .drawer,
              let params = request["params"] as? [String: Any],
              let height = (params["height"] as? NSNumber)?.doubleValue else { return }
        DispatchQueue.main.async { [onPreferredHeight] in
            onPreferredHeight(CGFloat(height))
        }
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
    let server: String
    let resourceURI: String
    let displayMode: MCPAppDisplayMode
    let authManager: AuthManager
    let onPreferredHeight: (CGFloat) -> Void

    func makeCoordinator() -> MCPAppBridgeCoordinator {
        MCPAppBridgeCoordinator(
            toolInput: toolInput,
            toolResult: toolResult,
            server: server,
            resourceURI: resourceURI,
            displayMode: displayMode,
            authManager: authManager,
            onPreferredHeight: onPreferredHeight
        )
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
    let server: String
    let resourceURI: String
    let displayMode: MCPAppDisplayMode
    let authManager: AuthManager
    let onPreferredHeight: (CGFloat) -> Void

    func makeCoordinator() -> MCPAppBridgeCoordinator {
        MCPAppBridgeCoordinator(
            toolInput: toolInput,
            toolResult: toolResult,
            server: server,
            resourceURI: resourceURI,
            displayMode: displayMode,
            authManager: authManager,
            onPreferredHeight: onPreferredHeight
        )
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
