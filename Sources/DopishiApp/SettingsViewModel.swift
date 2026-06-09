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
    private let store: SettingsStore
    private let ramGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824.0
    var onChange: ((Settings) -> Void)?
    /// Колбэк кнопки «Очистить память» (AppDelegate -> memoryProvider.clear()).
    var onClearMemory: (() -> Void)?

    init(store: SettingsStore) {
        self.store = store
        self.config = store.load()
    }

    func persist() {
        store.save(config)
        onChange?(config)
    }

    func clearMemory() { onClearMemory?() }

    var modelRows: [ModelRow] {
        ModelCatalog.presets.map { p in
            let heavy = ModelCatalog.fitsComfortably(p, ramGB: ramGB) ? "" : " · тяжело для ОЗУ"
            return ModelRow(
                id: p.id,
                name: p.displayName,
                detail: "\(p.tier) · " + String(format: "%.1f ГБ", p.approxSizeGB) + heavy,
                downloaded: ModelLocator.isPresent(fileName: p.fileName),
                selected: config.selectedModelFile == p.fileName,
                downloading: downloadingId == p.id
            )
        }
    }

    /// Выбрать модель по id: если скачана - запомнить; иначе скачать и затем запомнить.
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
        Task {
            do {
                _ = try await ModelDownloader().download(p) { prog in
                    Task { @MainActor in self.downloadProgress = prog }
                }
                self.downloadingId = nil
                self.config.selectedModelFile = p.fileName
                self.persist()
                self.statusText = "Скачано, активна: \(p.displayName)."
            } catch {
                self.downloadingId = nil
                self.statusText = "Ошибка загрузки: \(error.localizedDescription)"
            }
        }
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
