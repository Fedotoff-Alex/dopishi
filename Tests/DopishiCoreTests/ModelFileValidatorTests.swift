import Testing
import Foundation
@testable import DopishiCore

@Suite struct ModelFileValidatorTests {
    private func write(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dopishi-mfv-\(UUID().uuidString).bin")
        try data.write(to: url)
        return url
    }

    @Test func validGGUFPasses() throws {
        var d = ModelFileValidator.magic
        d.append(Data(repeating: 0, count: 2_000_000))   // > minBytes
        let url = try write(d); defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: Never.self) { try ModelFileValidator.validate(fileAt: url) }
    }

    @Test func htmlRejectedAsNotGGUF() throws {
        var d = Data("<!DOCTYPE html><html>error</html>".utf8)
        d.append(Data(repeating: 0x20, count: 2_000_000))   // большой, но без GGUF-магии
        let url = try write(d); defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: ModelFileValidator.ValidationError.notGGUF) {
            try ModelFileValidator.validate(fileAt: url)
        }
    }

    @Test func tooSmallRejected() throws {
        let url = try write(ModelFileValidator.magic + Data([0, 0, 0, 0]))   // магия есть, но крошечный
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: ModelFileValidator.ValidationError.tooSmall(8)) {
            try ModelFileValidator.validate(fileAt: url)
        }
    }

    @Test func magicCheckedIndependentlyOfSize() throws {
        let good = try write(ModelFileValidator.magic + Data([1]))
        let bad = try write(Data("HTML".utf8) + Data([1]))
        defer {
            try? FileManager.default.removeItem(at: good)
            try? FileManager.default.removeItem(at: bad)
        }
        #expect(throws: Never.self) { try ModelFileValidator.validate(fileAt: good, minBytes: 4) }
        #expect(throws: ModelFileValidator.ValidationError.notGGUF) {
            try ModelFileValidator.validate(fileAt: bad, minBytes: 4)
        }
    }

    @Test func missingFileRejected() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dopishi-nope-\(UUID().uuidString)")
        #expect(throws: ModelFileValidator.ValidationError.tooSmall(0)) {
            try ModelFileValidator.validate(fileAt: url)
        }
    }
}
