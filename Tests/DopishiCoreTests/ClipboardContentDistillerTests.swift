import Testing
@testable import DopishiCore

// Поведенческая спецификация ClipboardContentDistiller + конвейера prepare (swift-testing).
@Suite struct ClipboardContentDistillerTests {
    @Test func shortClipboardReturnedAsIs() {
        #expect(ClipboardContentDistiller.distill(
            clipboard: "line one\nline two\nline three",
            prefixText: "completely unrelated text") == "line one\nline two\nline three")
    }

    @Test func emptyPrefixReturnsClipboardAsIs() {
        let clip = "line one content\nline two content\nline three content\nline four content"
        #expect(ClipboardContentDistiller.distill(clipboard: clip, prefixText: "") == clip)
    }

    @Test func longClipboardKeepsOnlyMatchingLines() {
        let clip = "import Foundation\nimport UIKit\nfunc deploy() {\n    print(\"starting deploy\")\n}"
        #expect(ClipboardContentDistiller.distill(clipboard: clip, prefixText: "the deploy is running")
                == "func deploy() {\n    print(\"starting deploy\")")
    }

    @Test func longClipboardNoOverlapReturnsHead() {
        let clip = "alpha bravo charlie\ndelta echo foxtrot\ngolf hotel india\njuliet kilo lima"
        #expect(ClipboardContentDistiller.distill(clipboard: clip, prefixText: "completely different words")
                == String(clip.prefix(300)))
    }

    @Test func caseInsensitiveMatching() {
        let clip = "The DEPLOYMENT pipeline\nSome unrelated header\nAnother random line\nCheck deployment status"
        #expect(ClipboardContentDistiller.distill(clipboard: clip, prefixText: "our deployment is slow")
                == "The DEPLOYMENT pipeline\nCheck deployment status")
    }

    // --- prepare (полный конвейер: sanitize -> guard -> distill -> clip) ---
    @Test func prepareSanitizesAndKeepsShort() {
        // санитайз меняет "-" на пробел (границы слов), 1 строка <=3 -> дистилл as-is
        #expect(ClipboardContentDistiller.prepare(rawRelevant: "raw-output value", prefix: "raw value")
                == "raw output value")
    }

    @Test func prepareDropsSymbolOnly() {
        #expect(ClipboardContentDistiller.prepare(rawRelevant: "--- >>> ===", prefix: "anything") == nil)
    }

    @Test func prepareClipsLong() {
        let long = String(repeating: "alpha ", count: 300)   // ~1800 символов, одна строка
        let r = ClipboardContentDistiller.prepare(rawRelevant: long, prefix: "alpha")
        #expect((r?.count ?? 0) <= 1200)
        #expect(r?.hasSuffix("...") == true)
    }

    // --- детект секретов (приватность) ---
    @Test func looksSecretDetectsKeysAndTokens() {
        #expect(ClipboardContentDistiller.looksSecret("sk-proj-ABCD1234EFGH5678IJKL"))
        #expect(ClipboardContentDistiller.looksSecret("github_pat_11ABCDEFGH0iJkLmNoPq"))
        #expect(ClipboardContentDistiller.looksSecret("ghp_aBcD1234eFgH5678iJkLmnop"))
        #expect(ClipboardContentDistiller.looksSecret("AKIAIOSFODNN7EXAMPLE"))
        #expect(ClipboardContentDistiller.looksSecret("-----BEGIN PRIVATE KEY-----"))
        #expect(ClipboardContentDistiller.looksSecret("a1b2c3d4e5f6a7b8c9d0e1f2a3b4"))   // длинный hex
    }

    @Test func looksSecretIgnoresNormalText() {
        #expect(!ClipboardContentDistiller.looksSecret("Привет, как дела сегодня?"))
        #expect(!ClipboardContentDistiller.looksSecret("the deployment pipeline is running slow"))
        #expect(!ClipboardContentDistiller.looksSecret("https://example.com/very/long/path/page?q=12345"))
        #expect(!ClipboardContentDistiller.looksSecret("user@example.com"))
        #expect(!ClipboardContentDistiller.looksSecret("task-force meeting at noon"))   // sk- не на границе
        #expect(!ClipboardContentDistiller.looksSecret("version 1.2.3-beta.456"))
    }

    @Test func prepareDropsSecret() {
        #expect(ClipboardContentDistiller.prepare(rawRelevant: "sk-proj-ABCD1234EFGH5678IJKLmnop",
                                                  prefix: "my key is") == nil)
    }

    @Test func preparedSkipsSanitizeStep() {
        // prepared работает с уже санитайзнутым текстом (тот же результат, что prepare).
        let raw = "raw-output value"
        let viaSanitize = PromptContextSanitizer.sanitize(raw)
        #expect(ClipboardContentDistiller.prepared(sanitized: viaSanitize, prefix: "raw value")
                == ClipboardContentDistiller.prepare(rawRelevant: raw, prefix: "raw value"))
    }
}
