import Testing
import Foundation
@testable import DopishiLLM

@Suite struct ModelLocatorTests {
    @Test func buildsModelPathUnderBase() {
        let url = ModelLocator.modelsDirectory(baseDirectory: URL(fileURLWithPath: "/tmp/base"))
            .appendingPathComponent("X.gguf")
        #expect(url.path == "/tmp/base/Dopishi/Models/X.gguf")
    }
}
