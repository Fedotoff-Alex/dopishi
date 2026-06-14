import Foundation

public final class SettingsStore {
    private let defaults: UserDefaults
    private let key = "dopishi.settings.v1"
    private let telemetryMigrationKey = "dopishi.migration.telemetryOn.v1"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> Settings {
        guard let data = defaults.data(forKey: key),
              let s = try? JSONDecoder().decode(Settings.self, from: data) else {
            return .default
        }
        var migrated = s.clamped()
        // Миграция: РОВНО старый дефолт 350мс ощущался как "медленно" (это было главной
        // причиной, а не движок). Понижаем разово до 120. Другие значения - осознанный
        // выбор пользователя, не трогаем.
        if migrated.debounceMs == 350 {
            migrated.debounceMs = 120
            save(migrated)
        }
        // Phase 4: телеметрия становится default-ON (решение вехи). У существующих установок
        // в persisted JSON лежит false от старого дефолта - тумблера в UI не было, это не
        // осознанный выбор. Включаем разово; дальше управляет Privacy Center.
        if !defaults.bool(forKey: telemetryMigrationKey) {
            defaults.set(true, forKey: telemetryMigrationKey)
            if !migrated.suggestionTelemetryEnabled {
                migrated.suggestionTelemetryEnabled = true
                save(migrated)
            }
        }
        return migrated
    }

    public func save(_ settings: Settings) {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: key)
        }
    }
}
