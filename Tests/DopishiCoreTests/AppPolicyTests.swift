import Testing
@testable import DopishiCore

@Suite struct AppPolicyTests {
    @Test func nilBundleAllowed() {
        #expect(AppPolicy.isAllowed(bundleId: nil, excluded: ["com.x"]))
    }
    @Test func excludedBlocked() {
        #expect(!AppPolicy.isAllowed(bundleId: "com.x", excluded: ["com.x"]))
    }
    @Test func notExcludedAllowed() {
        #expect(AppPolicy.isAllowed(bundleId: "com.y", excluded: ["com.x"]))
    }
    @Test func emptyExclusionsAllowAll() {
        #expect(AppPolicy.isAllowed(bundleId: "com.x", excluded: []))
    }

    // Spotlight исключён встроенно (мгновенный поиск: инъекция оставляет артефакты, контекста
    // для свитча нет) - не действуем там, даже если в пользовательском списке его нет.
    @Test func spotlightBuiltInExcluded() {
        #expect(!AppPolicy.isAllowed(bundleId: "com.apple.Spotlight", excluded: []))
        // и для записи в память тоже заблокирован
        #expect(!AppPolicy.allowsMemoryWrite(isSecure: false, bundleId: "com.apple.Spotlight", excluded: []))
    }

    // WR-04: гейт записи в персистентную память (контракт MemoryProvider.record).
    @Test func memoryWriteBlockedForSecureField() {
        #expect(!AppPolicy.allowsMemoryWrite(isSecure: true, bundleId: "com.y", excluded: []))
    }
    @Test func memoryWriteBlockedForExcludedApp() {
        #expect(!AppPolicy.allowsMemoryWrite(isSecure: false, bundleId: "com.x", excluded: ["com.x"]))
    }
    @Test func memoryWriteAllowedForNormalField() {
        #expect(AppPolicy.allowsMemoryWrite(isSecure: false, bundleId: "com.y", excluded: ["com.x"]))
    }

    // UX-02 (Privacy Center): «не учиться в этом приложении» - память не пишется,
    // но приложение НЕ исключено полностью (подсказки работают).
    @Test func memoryWriteBlockedForLearningExcludedApp() {
        #expect(!AppPolicy.allowsMemoryWrite(isSecure: false, bundleId: "com.x",
                                             excluded: [], learningExcluded: ["com.x"]))
        #expect(AppPolicy.isAllowed(bundleId: "com.x", excluded: []))
    }
    @Test func memoryWriteAllowedWhenLearningExclusionsDontMatch() {
        #expect(AppPolicy.allowsMemoryWrite(isSecure: false, bundleId: "com.y",
                                            excluded: [], learningExcluded: ["com.x"]))
    }
    @Test func memoryWriteNilBundleIgnoresLearningExclusions() {
        #expect(AppPolicy.allowsMemoryWrite(isSecure: false, bundleId: nil,
                                            excluded: [], learningExcluded: ["com.x"]))
    }
}
