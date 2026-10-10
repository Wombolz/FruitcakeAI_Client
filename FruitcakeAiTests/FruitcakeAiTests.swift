//
//  FruitcakeAiTests.swift
//  FruitcakeAiTests
//
//  Created by jwomble on 2/28/26.
//

import Foundation
import Testing
@testable import FruitcakeAi

struct FruitcakeAiTests {

    @Test @MainActor func decodesMCPAppToolResponseResourceURI() throws {
        let payload = Data(
            #"{"server":"stocks","resource_uri":"ui://stocks/dashboard.html","tool":"stocks_get_watchlist","result":{"structuredContent":{"symbols":[]}}}"#.utf8
        )
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let response = try decoder.decode(MCPAppToolCallResponse.self, from: payload)

        #expect(response.resourceURI == "ui://stocks/dashboard.html")
        #expect(response.tool == "stocks_get_watchlist")
    }

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }

}
