import Foundation

public struct Settings: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var debounceMs: Int
    public var minChars: Int
    public var selectedModelFile: String
    public var layoutSwitchEnabled: Bool
    public var autocorrectEnabled: Bool
    public var manualLayoutSwitchEnabled: Bool
    public var excludedBundleIds: [String]
    public var disableSystemAutocorrect: Bool
    public var electronSupport: Bool
    /// OCR-контекст экрана (читаем окно вокруг поля). Чувствительно - opt-in, off by default,
    /// требует Screen Recording. Управляет захватом в WindowOCRProvider.
    public var screenContextEnabled: Bool
    /// Контекст буфера обмена (последний скопированный текст). Чувствительно - opt-in, off by
    /// default. Читается на смену фокуса в ContextProbe, гейтится !secure + allowedApp + свежесть.
    public var clipboardContextEnabled: Bool
    /// Локальная память контекста (SQLite): помнит, что писалось в окне, и подмешивает в промпт.
    /// Чувствительно - opt-in, off by default. Гейтится !secure + allowedApp + секрет-дроп + TTL.
    public var memoryEnabled: Bool
    /// Максимум слов в подсказке-дополнении (длина дополнения). Прокидывается в движок как
    /// runtime-override maxWords (без пересоздания/перезагрузки модели).
    public var maxCompletionWords: Int
    /// Пользовательские указания по стилю/задаче. Подмешиваются в СТАТИЧЕСКУЮ голову промпта
    /// (KV-safe), пусто -> ничего не добавляется.
    public var writingInstructions: String
    /// Личный словарь: слова, которые НЕ считать опечаткой и НЕ предлагать исправлять
    /// (имена/проекты/термины/сленг) - как игнор-словарь PuntoSwitcher.
    public var customDictionary: [String]
    /// Пользовательские сниппеты (UX-05): одна строка = "имя: текст". ":имя" + Tab раскрывает.
    /// Встроенные динамические :date/:time работают всегда; пользовательские важнее встроенных.
    public var snippetsRaw: String
    /// Телеметрия событий подсказок (suggestion_event). С Phase 4 - default-ON (решение вехи):
    /// хранятся только метаданные (исход/латентность/приложение), без текста; контроль -
    /// тумблер в Privacy Center. При выключении eventStore не создаётся.
    public var suggestionTelemetryEnabled: Bool
    /// Мастер первого запуска пройден (Phase 4, UX-01). false -> показать мастер на старте.
    public var onboardingCompleted: Bool
    /// TTL локальной памяти в днях (Phase 4, UX-02). Default 7 - решение вехи
    /// (раньше константа 14 в MemoryStore.defaultTTL).
    public var memoryTTLDays: Int
    /// «Не учиться в этом приложении» (Privacy Center): память НЕ записывается из этих
    /// приложений, но подсказки в них работают (в отличие от excludedBundleIds - полного выкл).
    public var memoryExcludedBundleIds: [String]

    public init(enabled: Bool = true, debounceMs: Int = 150, minChars: Int = 8,
                selectedModelFile: String = ModelCatalog.defaultFileName,
                layoutSwitchEnabled: Bool = false,
                autocorrectEnabled: Bool = false,
                manualLayoutSwitchEnabled: Bool = false,
                excludedBundleIds: [String] = [],
                disableSystemAutocorrect: Bool = false,
                electronSupport: Bool = false,
                screenContextEnabled: Bool = false,
                clipboardContextEnabled: Bool = false,
                memoryEnabled: Bool = false,
                maxCompletionWords: Int = 6,
                writingInstructions: String = "",
                customDictionary: [String] = [],
                snippetsRaw: String = "",
                suggestionTelemetryEnabled: Bool = true,
                onboardingCompleted: Bool = false,
                memoryTTLDays: Int = 7,
                memoryExcludedBundleIds: [String] = []) {
        self.enabled = enabled
        self.debounceMs = debounceMs
        self.minChars = minChars
        self.selectedModelFile = selectedModelFile
        self.layoutSwitchEnabled = layoutSwitchEnabled
        self.autocorrectEnabled = autocorrectEnabled
        self.manualLayoutSwitchEnabled = manualLayoutSwitchEnabled
        self.excludedBundleIds = excludedBundleIds
        self.disableSystemAutocorrect = disableSystemAutocorrect
        self.electronSupport = electronSupport
        self.screenContextEnabled = screenContextEnabled
        self.clipboardContextEnabled = clipboardContextEnabled
        self.memoryEnabled = memoryEnabled
        self.maxCompletionWords = maxCompletionWords
        self.writingInstructions = writingInstructions
        self.customDictionary = customDictionary
        self.snippetsRaw = snippetsRaw
        self.suggestionTelemetryEnabled = suggestionTelemetryEnabled
        self.onboardingCompleted = onboardingCompleted
        self.memoryTTLDays = memoryTTLDays
        self.memoryExcludedBundleIds = memoryExcludedBundleIds
    }

    public static let `default` = Settings()

    public func clamped() -> Settings {
        Settings(
            enabled: enabled,
            debounceMs: min(max(debounceMs, 60), 1500),
            minChars: min(max(minChars, 1), 20),
            selectedModelFile: selectedModelFile,
            layoutSwitchEnabled: layoutSwitchEnabled,
            autocorrectEnabled: autocorrectEnabled,
            manualLayoutSwitchEnabled: manualLayoutSwitchEnabled,
            excludedBundleIds: excludedBundleIds,
            disableSystemAutocorrect: disableSystemAutocorrect,
            electronSupport: electronSupport,
            screenContextEnabled: screenContextEnabled,
            clipboardContextEnabled: clipboardContextEnabled,
            memoryEnabled: memoryEnabled,
            maxCompletionWords: min(max(maxCompletionWords, 1), 12),
            writingInstructions: String(writingInstructions.prefix(500)),
            customDictionary: Array(
                customDictionary
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .reduce(into: [String]()) { acc, w in
                        if !acc.contains(where: { CustomDictionary.normalize($0) == CustomDictionary.normalize(w) }) {
                            acc.append(w)
                        }
                    }
                    .prefix(1000)
            ),
            snippetsRaw: String(snippetsRaw.prefix(8000)),
            suggestionTelemetryEnabled: suggestionTelemetryEnabled,
            onboardingCompleted: onboardingCompleted,
            memoryTTLDays: min(max(memoryTTLDays, 1), 90),
            memoryExcludedBundleIds: memoryExcludedBundleIds
        )
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, debounceMs, minChars, selectedModelFile
        case layoutSwitchEnabled, autocorrectEnabled, manualLayoutSwitchEnabled, excludedBundleIds
        case disableSystemAutocorrect
        case electronSupport
        case screenContextEnabled
        case clipboardContextEnabled
        case memoryEnabled
        case maxCompletionWords
        case writingInstructions
        case customDictionary
        case snippetsRaw
        case suggestionTelemetryEnabled
        case onboardingCompleted
        case memoryTTLDays
        case memoryExcludedBundleIds
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        self.debounceMs = try c.decodeIfPresent(Int.self, forKey: .debounceMs) ?? 150
        self.minChars = try c.decodeIfPresent(Int.self, forKey: .minChars) ?? 8
        self.selectedModelFile = try c.decodeIfPresent(String.self, forKey: .selectedModelFile) ?? ModelCatalog.defaultFileName
        self.layoutSwitchEnabled = try c.decodeIfPresent(Bool.self, forKey: .layoutSwitchEnabled) ?? false
        self.autocorrectEnabled = try c.decodeIfPresent(Bool.self, forKey: .autocorrectEnabled) ?? false
        self.manualLayoutSwitchEnabled = try c.decodeIfPresent(Bool.self, forKey: .manualLayoutSwitchEnabled) ?? false
        self.excludedBundleIds = try c.decodeIfPresent([String].self, forKey: .excludedBundleIds) ?? []
        self.disableSystemAutocorrect = try c.decodeIfPresent(Bool.self, forKey: .disableSystemAutocorrect) ?? false
        self.electronSupport = try c.decodeIfPresent(Bool.self, forKey: .electronSupport) ?? false
        self.screenContextEnabled = try c.decodeIfPresent(Bool.self, forKey: .screenContextEnabled) ?? false
        self.clipboardContextEnabled = try c.decodeIfPresent(Bool.self, forKey: .clipboardContextEnabled) ?? false
        self.memoryEnabled = try c.decodeIfPresent(Bool.self, forKey: .memoryEnabled) ?? false
        self.maxCompletionWords = try c.decodeIfPresent(Int.self, forKey: .maxCompletionWords) ?? 6
        self.writingInstructions = try c.decodeIfPresent(String.self, forKey: .writingInstructions) ?? ""
        self.customDictionary = try c.decodeIfPresent([String].self, forKey: .customDictionary) ?? []
        self.snippetsRaw = try c.decodeIfPresent(String.self, forKey: .snippetsRaw) ?? ""
        // Phase 4: телеметрия default-ON (старый persisted JSON без ключа получает true).
        self.suggestionTelemetryEnabled = try c.decodeIfPresent(Bool.self, forKey: .suggestionTelemetryEnabled) ?? true
        self.onboardingCompleted = try c.decodeIfPresent(Bool.self, forKey: .onboardingCompleted) ?? false
        self.memoryTTLDays = try c.decodeIfPresent(Int.self, forKey: .memoryTTLDays) ?? 7
        self.memoryExcludedBundleIds = try c.decodeIfPresent([String].self, forKey: .memoryExcludedBundleIds) ?? []
    }
}
