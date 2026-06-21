import Testing
import Foundation
@testable import DopishiMemory
@testable import DopishiCore

// Воронка 1 (D-02/D-04): guard на уровне MemoryStore.record - секрет физически не попадает
// в memory.sqlite. Проверяется ИМЕННО Store-уровень (структурная гарантия для P11/P12/P13),
// а не App-обёртка.
@Suite struct SecretGuardFunnelTests {
    private func store() throws -> MemoryStore { try MemoryStore.inMemory() }
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test func secretDroppedOnMemoryWrite() throws {
        let s = try store()
        try s.record(threadKey: "app:1", kind: .message,
                     text: "ghp_ABCDEFGHIJ1234567890abcdefghij", now: t0)
        #expect(try s.count() == 0)
    }

    @Test func secretDroppedPEM() throws {
        let s = try store()
        try s.record(threadKey: "app:1", kind: .message,
                     text: "-----BEGIN PRIVATE KEY-----\nMIIBVgIBADANBg", now: t0)
        #expect(try s.count() == 0)
    }

    @Test func normalTextRecorded() throws {
        let s = try store()
        try s.record(threadKey: "app:1", kind: .message, text: "обычное сообщение", now: t0)
        #expect(try s.count() == 1)
    }

    @Test func emptyStillIgnored() throws {
        let s = try store()
        try s.record(threadKey: "app:1", kind: .message, text: "   ", now: t0)
        #expect(try s.count() == 0)   // существующий guard пустоты не сломан
    }
}
