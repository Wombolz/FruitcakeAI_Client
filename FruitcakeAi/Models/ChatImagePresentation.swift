import Foundation

struct ChatImagePreviewReference: Hashable {
    let messageID: Int
    let imageIndex: Int

    var resourceID: String { "chat-image:\(messageID):\(imageIndex)" }
    var endpoint: String { "artifacts/chat-images/\(messageID)/\(imageIndex)" }
}

enum ChatImagePresentation {
    static func size(width: Double?, height: Double?) -> CGSize {
        let w = width ?? 1024
        let h = height ?? 1024
        guard w.isFinite, h.isFinite, w > 0, h > 0 else { return CGSize(width: 420, height: 420) }
        let scale = min(1, 460 / w, 420 / h)
        return CGSize(width: w * scale, height: h * scale)
    }

    static func request(baseURL: URL, token: String, path: String, preview: ChatImagePreviewReference?) -> URLRequest? {
        let endpoint = preview?.endpoint ?? "workspace/images"
        guard preview != nil || !path.isEmpty else { return nil }
        var components = URLComponents(url: baseURL.appendingPathComponent(endpoint), resolvingAgainstBaseURL: false)
        if preview == nil { components?.queryItems = [URLQueryItem(name: "path", value: path)] }
        guard let url = components?.url else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 40
        return request
    }
}
