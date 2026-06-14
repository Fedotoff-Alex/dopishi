import Testing
import Foundation
@testable import DopishiCore

/// UX-04: sha256-верификация моделей.
@Suite struct ModelChecksumTests {
    /// Известный вектор: SHA256("abc") = ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad.
    @Test func sha256KnownVector() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("dopishi-sha-test-\(UUID().uuidString)")
        try Data("abc".utf8).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let hex = try ModelChecksum.sha256Hex(of: tmp)
        #expect(hex == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test func expectedSHA256ParsesHFTree() {
        let json = """
        [
          {"type":"file","path":"README.md","oid":"aaa"},
          {"type":"file","path":"model-Q4_K_M.gguf","oid":"bbb",
           "lfs":{"oid":"DEADBEEF00","size":123,"pointerSize":134}}
        ]
        """
        let sha = ModelChecksum.expectedSHA256(treeJSON: Data(json.utf8),
                                               remoteFileName: "model-Q4_K_M.gguf")
        #expect(sha == "deadbeef00")   // lowercase-нормализация
    }

    @Test func expectedSHA256NilWhenMissingOrMalformed() {
        let json = #"[{"type":"file","path":"other.gguf","lfs":{"oid":"xxx"}}]"#
        #expect(ModelChecksum.expectedSHA256(treeJSON: Data(json.utf8),
                                             remoteFileName: "model.gguf") == nil)
        #expect(ModelChecksum.expectedSHA256(treeJSON: Data("не json".utf8),
                                             remoteFileName: "model.gguf") == nil)
        // файл без lfs-секции (не LFS) - nil, верификация пропускается
        let noLfs = #"[{"type":"file","path":"model.gguf","oid":"plain"}]"#
        #expect(ModelChecksum.expectedSHA256(treeJSON: Data(noLfs.utf8),
                                             remoteFileName: "model.gguf") == nil)
    }
}
