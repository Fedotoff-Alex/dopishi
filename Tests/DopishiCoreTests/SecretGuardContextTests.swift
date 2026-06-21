import Testing
import Foundation
@testable import DopishiCore

// Воронка 2 (D-03/D-04): guard на доп-каналы (mem/ocr/clip) в ContextBuilder.build -
// секрет не подмешивается в промпт. fieldTail НЕ дропается (Open Q1: хвост поля пользователь
// печатает сам осознанно; дроп выключил бы подсказки в поле с токеном - Pitfall 4).
@Suite struct SecretGuardContextTests {
    private func ocr(_ text: String) -> OCRContext {
        OCRContext(windowText: text, capturedAt: Date(timeIntervalSince1970: 0), windowId: 1)
    }

    @Test func secretClipNotInPrompt() {
        let secret = "sk-ABCDEFGHIJKLMNOPQRSTUVWX"
        let b = ContextBundle(fieldTail: "привет", ocr: nil, clipboard: secret, memory: nil)
        let p = ContextBuilder.build(b)
        #expect(!p.contains(secret))
        #expect(!p.contains("Буфер:"))
    }

    @Test func secretMemNotInPrompt() {
        let secret = "ghp_ABCDEFGHIJ1234567890abcdefgh"
        let b = ContextBundle(fieldTail: "привет", ocr: nil, clipboard: nil, memory: secret)
        let p = ContextBuilder.build(b)
        #expect(!p.contains(secret))
        #expect(!p.contains("Память:"))
    }

    @Test func secretOcrNotInPrompt() {
        let secret = "AKIAIOSFODNN7EXAMPLE"
        let b = ContextBundle(fieldTail: "привет", ocr: ocr(secret), clipboard: nil, memory: nil)
        let p = ContextBuilder.build(b)
        #expect(!p.contains(secret))
        #expect(!p.contains("Окно:"))
    }

    // Open Q1: хвост поля с секрет-подобным токеном НЕ дропается - пользователь печатает его сам.
    @Test func fieldTailWithSecretStillIncluded() {
        let b = ContextBundle(fieldTail: "мой ключ sk-ABCDEFGHIJKLMNOPQRSTUVWX",
                              ocr: nil, clipboard: nil, memory: nil)
        let p = ContextBuilder.build(b)
        #expect(p.contains("sk-ABCDEFGHIJKLMNOPQRSTUVWX"))
        #expect(p.contains("мой ключ"))
    }

    // Нет регрессии: обычные каналы по-прежнему в промпте.
    @Test func normalChannelsIncluded() {
        let b = ContextBundle(fieldTail: "привет", ocr: nil,
                              clipboard: "адрес: Павловская 27", memory: "вчера обсуждали смету")
        let p = ContextBuilder.build(b)
        #expect(p.contains("Буфер: адрес: Павловская 27"))
        #expect(p.contains("Память: вчера обсуждали смету"))
    }
}
