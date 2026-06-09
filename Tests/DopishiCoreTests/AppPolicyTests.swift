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
}
