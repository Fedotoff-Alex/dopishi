import AppKit
import DopishiCore
import DopishiLLM
import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    /// App-локальная строка для пикера моделей (во View не утекают типы DopishiCore).
    struct ModelRow: Identifiable {
        let id: String
        let name: String
        let detail: String
        let downloaded: Bool
        let selected: Bool
        let downloading: Bool
        /// Можно удалить с диска: скачана, не выбрана и не качается (UX-04).
        var deletable: Bool { downloaded && !selected && !downloading }
    }

    /// Строка приложения для списка исключений / пикера (id = bundleId).
    struct AppRow: Identifiable, Equatable {
        let id: String
        let name: String
    }

    @Published var config: Settings
    @Published var downloadingId: String?
    @Published var downloadProgress: Double = 0
    @Published var statusText: String = ""
    /// Размер базы памяти для Privacy Center (обновляется refreshPrivacyStats()).
    @Published var memoryDbSizeText: String = "база не создана"
    private let store: SettingsStore
    private let ramGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824.0
    var onChange: ((Settings) -> Void)?
    /// Колбэк кнопки «Очистить память» (AppDelegate -> memoryProvider.clear()).
    var onClearMemory: (() -> Void)?
    /// Колбэк кнопки «Экспортировать память» (AppDelegate -> NSSavePanel + exportJSON).
    var onExportMemory: (() -> Void)?
    /// Провайдер размера базы памяти (AppDelegate -> memoryProvider.dbSizeBytes()).
    var memoryDbSizeProvider: (() -> Int64?)?
    /// Бенчмарк текущей модели (AppDelegate -> SuggestionController.benchCurrentModel, UX-04).
    var onBenchModel: (() async -> BenchTrace?)?
    /// Текущая загрузка (UX-04): держим для cancel(); resumeData сохраняется на диск.
    private var downloader: ModelDownloader?
    @Published var benchRunning = false

    init(store: SettingsStore) {
        self.store = store
        self.config = store.load()
    }

    func persist() {
        store.save(config)
        onChange?(config)
    }

    func clearMemory() {
        onClearMemory?()
        refreshPrivacyStats()
    }

    func exportMemory() { onExportMemory?() }

    /// Пересчитать показатели Privacy Center (размер базы). Зовётся при открытии окна.
    func refreshPrivacyStats() {
        guard let bytes = memoryDbSizeProvider?() else {
            memoryDbSizeText = "база не создана"
            return
        }
        let mb = Double(bytes) / 1_048_576.0
        memoryDbSizeText = mb < 0.1
            ? String(format: "%.0f КБ", Double(bytes) / 1024.0)
            : String(format: "%.1f МБ", mb)
    }

    // MARK: - «Не учиться в этом приложении» (Privacy Center, UX-02)

    /// Приложения, в которых память не записывается, с человекочитаемыми именами.
    var memoryExcludedAppRows: [AppRow] {
        config.memoryExcludedBundleIds.map { AppRow(id: $0, name: appName(for: $0)) }
    }

    /// Запущенные приложения, ещё не в memory-исключениях (для пикера Privacy Center).
    var pickableMemoryApps: [AppRow] {
        let already = Set(config.memoryExcludedBundleIds)
        return pickableApps.filter { !already.contains($0.id) }
    }

    func addMemoryExclusion(bundleId: String) {
        guard !config.memoryExcludedBundleIds.contains(bundleId) else { return }
        config.memoryExcludedBundleIds.append(bundleId)
        persist()
    }

    func removeMemoryExclusion(bundleId: String) {
        config.memoryExcludedBundleIds.removeAll { $0 == bundleId }
        persist()
    }

    var modelRows: [ModelRow] {
        ModelCatalog.presets.map { p in
            let heavy = ModelCatalog.fitsComfortably(p, ramGB: ramGB) ? "" : " · тяжело для ОЗУ"
            // Фактический размер на диске точнее каталожного approx (UX-04).
            let sizeText: String
            if let real = Self.diskSizeGB(fileName: p.fileName) {
                sizeText = String(format: "%.1f ГБ на диске", real)
            } else {
                sizeText = String(format: "%.1f ГБ", p.approxSizeGB)
            }
            return ModelRow(
                id: p.id,
                name: p.displayName,
                detail: "\(p.tier) · " + sizeText + heavy,
                downloaded: ModelLocator.isPresent(fileName: p.fileName),
                selected: config.selectedModelFile == p.fileName,
                downloading: downloadingId == p.id
            )
        }
    }

    /// Суммарная занятость диска скачанными моделями (для футера секции).
    var modelsTotalText: String {
        let total = ModelCatalog.presets.compactMap { Self.diskSizeGB(fileName: $0.fileName) }.reduce(0, +)
        guard total > 0 else { return "" }
        return String(format: "Всего на диске: %.1f ГБ", total)
    }

    private static func diskSizeGB(fileName: String) -> Double? {
        let path = ModelLocator.url(forFile: fileName).path
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let bytes = attrs[.size] as? NSNumber else { return nil }
        return bytes.doubleValue / 1_073_741_824.0
    }

    /// Удалить скачанную НЕвыбранную модель с диска (UX-04). Выбранную не трогаем.
    func deleteModel(modelId: String) {
        guard let p = ModelCatalog.preset(id: modelId),
              config.selectedModelFile != p.fileName,
              downloadingId != p.id else { return }
        do {
            try FileManager.default.removeItem(at: ModelLocator.url(forFile: p.fileName))
            statusText = "Удалена: \(p.displayName)."
        } catch {
            statusText = "Не удалось удалить \(p.displayName)."
        }
        objectWillChange.send()
    }

    /// Выбрать модель по id: если скачана - запомнить; иначе скачать и затем запомнить.
    /// Загрузка проходит GGUF-валидацию и sha256-сверку с HF (UX-04); прерванная ранее
    /// загрузка продолжается с места отмены (resumeData).
    func choose(modelId: String) {
        guard let p = ModelCatalog.preset(id: modelId) else { return }
        if ModelLocator.isPresent(fileName: p.fileName) {
            config.selectedModelFile = p.fileName
            persist()
            statusText = "Активна: \(p.displayName)."
            return
        }
        downloadingId = p.id
        downloadProgress = 0
        statusText = "Загрузка \(p.displayName)…"
        let d = ModelDownloader()
        downloader = d
        Task {
            do {
                _ = try await d.download(p) { prog in
                    Task { @MainActor in self.downloadProgress = prog }
                }
                self.downloadingId = nil
                self.downloader = nil
                self.config.selectedModelFile = p.fileName
                self.persist()
                self.statusText = "Скачано и проверено, активна: \(p.displayName)."
            } catch let e as ModelDownloader.DownloadError {
                self.downloadingId = nil
                self.downloader = nil
                if case .checksumMismatch = e {
                    self.statusText = "Контрольная сумма не совпала - файл удалён, попробуйте снова."
                } else {
                    self.statusText = "Ошибка загрузки: \(e)"
                }
            } catch let e as URLError where e.code == .cancelled {
                self.downloadingId = nil
                self.downloader = nil
                self.statusText = "Загрузка приостановлена - «Скачать» продолжит с того же места."
            } catch {
                self.downloadingId = nil
                self.downloader = nil
                self.statusText = "Ошибка загрузки: \(error.localizedDescription)"
            }
        }
    }

    /// Отменить текущую загрузку (UX-04). resumeData сохраняется - продолжение с места.
    func cancelDownload() {
        downloader?.cancel()
    }

    /// Бенчмарк текущей модели (UX-04): скорость генерации + первый токен, в statusText.
    func benchCurrentModel() {
        guard !benchRunning, let bench = onBenchModel else { return }
        benchRunning = true
        statusText = "Бенчмарк \(config.selectedModelFile)… (модель грузится, ~10-30 сек)"
        Task {
            let trace = await bench()
            self.benchRunning = false
            guard let trace else {
                self.statusText = "Бенчмарк не удался (модель не скачана?)."
                return
            }
            let first = trace.firstTokenMs.map { String(format: "%.0f", $0) } ?? "-"
            self.statusText = String(format: "Скорость: %.0f токенов/с · первый токен %@ мс · всего %.0f мс",
                                     trace.tokensPerSec, first, trace.totalMs)
        }
    }

    /// Рекомендация по RAM (UX-04): самый тяжёлый пресет, комфортный для этого Mac.
    var ramRecommendationText: String {
        let fitting = ModelCatalog.presets.filter { ModelCatalog.fitsComfortably($0, ramGB: ramGB) }
        guard let best = fitting.max(by: { $0.approxSizeGB < $1.approxSizeGB }) else {
            return String(format: "У вас %.0f ГБ ОЗУ - комфортных моделей в каталоге нет.", ramGB)
        }
        return String(format: "У вас %.0f ГБ ОЗУ - комфортно до «%@» (~%.1f ГБ).",
                      ramGB, best.displayName, best.approxSizeGB)
    }

    /// Исключённые приложения с человекочитаемыми именами.
    var excludedAppRows: [AppRow] {
        config.excludedBundleIds.map { AppRow(id: $0, name: appName(for: $0)) }
    }

    /// Запущенные обычные приложения, ещё не в списке исключений (для пикера).
    var pickableApps: [AppRow] {
        let own = Bundle.main.bundleIdentifier
        let excluded = Set(config.excludedBundleIds)
        let rows = NSWorkspace.shared.runningApplications.compactMap { app -> AppRow? in
            guard app.activationPolicy == .regular,
                  let bid = app.bundleIdentifier,
                  bid != own, !excluded.contains(bid) else { return nil }
            return AppRow(id: bid, name: app.localizedName ?? bid)
        }
        // дедуп по bundleId + сортировка по имени
        var seen = Set<String>()
        return rows.filter { seen.insert($0.id).inserted }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func addExclusion(bundleId: String) {
        guard !config.excludedBundleIds.contains(bundleId) else { return }
        config.excludedBundleIds.append(bundleId)
        persist()
    }

    func removeExclusion(bundleId: String) {
        config.excludedBundleIds.removeAll { $0 == bundleId }
        persist()
    }

    /// Личный словарь: добавить слово (без дублей по нормализации, пустое игнорим).
    func addDictionaryWord(_ raw: String) {
        let word = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return }
        let norm = CustomDictionary.normalize(word)
        guard !config.customDictionary.contains(where: { CustomDictionary.normalize($0) == norm }) else { return }
        config.customDictionary.append(word)
        persist()
    }

    func removeDictionaryWord(_ word: String) {
        config.customDictionary.removeAll { $0 == word }
        persist()
    }

    private func appName(for bundleId: String) -> String {
        if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleId }),
           let name = app.localizedName {
            return name
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId),
           let bundle = Bundle(url: url),
           let name = (bundle.infoDictionary?["CFBundleDisplayName"]
                        ?? bundle.infoDictionary?["CFBundleName"]) as? String {
            return name
        }
        return bundleId
    }

    /// Автозапуск при входе в систему (источник истины - система, не наши Settings).
    var launchAtLogin: Bool {
        get { LaunchAtLogin.isEnabled }
        set {
            LaunchAtLogin.set(newValue)
            objectWillChange.send()
        }
    }
}
