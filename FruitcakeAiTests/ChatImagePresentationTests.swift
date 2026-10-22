import Foundation
import Testing
@testable import FruitcakeAi

@Suite @MainActor struct ChatImagePresentationTests {
    @Test func cardsPreserveAspectAndStayWithinBounds() {
        for (width, height) in [(1024.0, 1024.0), (1536.0, 768.0), (768.0, 1536.0)] {
            let size = ChatImagePresentation.size(width: width, height: height)
            #expect(size.width <= 460 && size.height <= 420)
            #expect(abs(size.width / size.height - width / height) < 0.001)
        }
        #expect(ChatImagePresentation.size(width: 200, height: 100) == CGSize(width: 200, height: 100))
        #expect(ChatImagePresentation.size(width: 0, height: -1) == CGSize(width: 420, height: 420))
        #expect(ChatImagePresentation.size(width: .infinity, height: 10).width == 420)
    }

    @Test func oldPathsAndNewPrivateAssetsDecodeWithoutBreakingHistory() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let old = try decoder.decode(ChatImageArtifact.self, from: Data(#"{"path":"generated_images/old.png","width":1024,"height":768}"#.utf8))
        #expect(old.path == "generated_images/old.png" && old.assetId == nil)
        let privateImage = try decoder.decode(ChatImageArtifact.self, from: Data(#"{"path":"","asset_id":"a","source_server":"comfyui_image_lab"}"#.utf8))
        #expect(privateImage.id == "comfyui_image_lab:a")
        #expect(privateImage.path.isEmpty)
    }

    @Test func previewRequestsStayOnFruitcakeAndCarryOnlyFruitcakeCredentials() throws {
        let reference = ChatImagePreviewReference(messageID: 123, imageIndex: 1)
        let request = try #require(ChatImagePresentation.request(baseURL: URL(string: "http://localhost:8000")!, token: "fruitcake-test", path: "", preview: reference))
        #expect(request.url?.path == "/artifacts/chat-images/123/1")
        #expect(request.url?.query == nil)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fruitcake-test")
        #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
        let legacy = try #require(ChatImagePresentation.request(baseURL: URL(string: "http://localhost:8000")!, token: "t", path: "generated_images/a b.png", preview: nil))
        #expect(legacy.url?.path == "/workspace/images")
        #expect(URLComponents(url: legacy.url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "generated_images/a b.png")
        #expect(ChatImagePresentation.request(baseURL: URL(string: "http://localhost:8000")!, token: "t", path: "", preview: nil) == nil)
    }

    @Test func imageInspectorUsesStableDistinctMessageReferencesAndPreservesThemOnContextResolution() {
        let state = ArtifactInspectorState()
        state.setChatSession(10, active: true)
        func image(_ message: Int) -> ArtifactReference {
            .init(id: "asset-\(message)", path: "", filename: "image", mediaType: "image/png", title: "Image",
                  origin: .chat(sessionID: nil), chatImagePreview: .init(messageID: message, imageIndex: 0))
        }
        state.open(image(1))
        let firstID = state.selectedTab?.id
        #expect(state.selected?.chatImagePreview?.messageID == 1)
        #expect(state.selectedTab?.resource.symbol == "photo")
        state.open(image(1))
        #expect(state.tabs.count == 1 && state.selectedTab?.id == firstID)
        state.open(image(2))
        #expect(state.tabs.count == 2)
        state.setChatSession(11, active: true)
        #expect(state.tabs.isEmpty)
    }
}
