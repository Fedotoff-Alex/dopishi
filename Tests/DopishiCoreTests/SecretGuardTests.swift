import Testing
@testable import DopishiCore

// Поведенческая спецификация SecretGuard (swift-testing).
// Эвристики перенесены 1:1 из ClipboardContentDistiller (D-05): низкий false-positive - инвариант.
@Suite struct SecretGuardTests {
    @Test func looksSecretDetectsKeysAndTokens() {
        #expect(SecretGuard.looksSecret("sk-proj-ABCD1234EFGH5678IJKL"))
        #expect(SecretGuard.looksSecret("github_pat_11ABCDEFGH0iJkLmNoPq"))
        #expect(SecretGuard.looksSecret("ghp_aBcD1234eFgH5678iJkLmnop"))
        #expect(SecretGuard.looksSecret("AKIAIOSFODNN7EXAMPLE"))
        #expect(SecretGuard.looksSecret("-----BEGIN PRIVATE KEY-----"))
        #expect(SecretGuard.looksSecret("a1b2c3d4e5f6a7b8c9d0e1f2a3b4"))   // длинный hex
    }

    @Test func looksSecretIgnoresNormalText() {
        #expect(!SecretGuard.looksSecret("Привет, как дела сегодня?"))
        #expect(!SecretGuard.looksSecret("the deployment pipeline is running slow"))
        #expect(!SecretGuard.looksSecret("https://example.com/very/long/path/page?q=12345"))
        #expect(!SecretGuard.looksSecret("user@example.com"))
        #expect(!SecretGuard.looksSecret("task-force meeting at noon"))   // sk- не на границе токена
        #expect(!SecretGuard.looksSecret("version 1.2.3-beta.456"))
    }

    // Контракт делегации: ClipboardContentDistiller.looksSecret == SecretGuard.looksSecret на всех кейсах.
    @Test func distillerDelegatesToSecretGuard() {
        let cases = [
            "sk-proj-ABCD1234EFGH5678IJKL",
            "github_pat_11ABCDEFGH0iJkLmNoPq",
            "AKIAIOSFODNN7EXAMPLE",
            "-----BEGIN PRIVATE KEY-----",
            "a1b2c3d4e5f6a7b8c9d0e1f2a3b4",
            "Привет, как дела сегодня?",
            "https://example.com/very/long/path/page?q=12345",
            "user@example.com",
            "task-force meeting at noon",
            "version 1.2.3-beta.456",
        ]
        for c in cases {
            #expect(ClipboardContentDistiller.looksSecret(c) == SecretGuard.looksSecret(c))
        }
    }
}
