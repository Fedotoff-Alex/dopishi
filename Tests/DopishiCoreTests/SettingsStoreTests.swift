import Testing
import Foundation
@testable import DopishiCore

@Suite(.serialized) struct SettingsStoreTests {
    private func freshDefaults() -> UserDefaults {
        let name = "dopishi.tests.settings"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @Test func loadsDefaultWhenEmpty() {
        let store = SettingsStore(defaults: freshDefaults())
        #expect(store.load() == Settings.default)
    }
    @Test func savesAndLoads() {
        let d = freshDefaults()
        SettingsStore(defaults: d).save(Settings(enabled: false, debounceMs: 500, minChars: 4))
        let loaded = SettingsStore(defaults: d).load()
        #expect(loaded == Settings(enabled: false, debounceMs: 500, minChars: 4))
    }
    @Test func loadClampsStoredValues() {
        let d = freshDefaults()
        let store = SettingsStore(defaults: d)
        store.save(Settings(enabled: true, debounceMs: 99999, minChars: 0))
        #expect(store.load().debounceMs == 1500)
        #expect(store.load().minChars == 1)
    }
    @Test func migratesOldDefaultDebounce() {
        let d = freshDefaults()
        SettingsStore(defaults: d).save(Settings(debounceMs: 350))
        #expect(SettingsStore(defaults: d).load().debounceMs == 120)
    }
}
