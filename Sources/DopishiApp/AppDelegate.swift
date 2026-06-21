import AppKit
import DopishiCore
import DopishiLLM
import DopishiMemory
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var refreshTimer: Timer?
    private var probe: ContextProbe?
    private let hud = DebugHUD()
    private let suggestions = SuggestionController()
    private let selectionActions = SelectionActionController()
    private let wordProcessor = WordCompletionProcessor()
    private let adaptivePolicy = AdaptivePolicyCenter()
    private let settingsStore = SettingsStore()
    private lazy var settingsVM = SettingsViewModel(store: settingsStore)
    private var settingsWindow: NSWindow?
    private let diagnostics = DiagnosticsCenter()
    private var diagnosticsWindow: NSWindow?
    private var privacyWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var monitorRunning = false
    private var lastSystemAutocorrectDisabled: Bool?
    /// Последнее применённое к UI состояние - чтобы не перестраивать меню/иконку каждые 2с,
    /// когда ничего не изменилось (источник всплесков CPU в простое).
    private var lastRuntime: DiagnosticsRuntime?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        refresh()
        // Права меняются вне приложения (в System Settings) - опрашиваем периодически.
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.refresh() }
        }

        settingsVM.onChange = { [weak self] s in
            self?.suggestions.applySettings(s)
            // Мастер-тумблер "выкл" гасит и автозамену раскладки, и автоисправление - иначе
            // выключенное приложение продолжает подменять слова (ловушка доверия).
            self?.wordProcessor.layoutEnabled = s.enabled && s.layoutSwitchEnabled
            self?.wordProcessor.autocorrectEnabled = s.enabled && s.autocorrectEnabled
            self?.wordProcessor.manualLayoutEnabled = s.enabled && s.manualLayoutSwitchEnabled
            self?.probe?.excludedBundleIds = Set(s.excludedBundleIds)
            self?.probe?.enhancedUIEnabled = s.electronSupport
            self?.applySystemAutocorrect(s.disableSystemAutocorrect)
            self?.applyScreenContext(s.screenContextEnabled, requestPermission: true)
            self?.probe?.clipboardEnabled = s.enabled && s.clipboardContextEnabled
            self?.probe?.setMemoryEnabled(s.enabled && s.memoryEnabled)
            // Privacy Center (Phase 4): TTL и «не учиться в этом приложении» - на лету.
            self?.probe?.memoryProvider.ttlDays = s.memoryTTLDays
            self?.probe?.memoryProvider.learningExcluded = Set(s.memoryExcludedBundleIds)
            self?.applyTelemetry(s.suggestionTelemetryEnabled)
        }
        let initialSettings = settingsStore.load()
        suggestions.applySettings(initialSettings)
        if initialSettings.enabled { suggestions.warmUp() }   // прогрев модели в фоне на старте
        wordProcessor.layoutEnabled = initialSettings.enabled && initialSettings.layoutSwitchEnabled
        wordProcessor.autocorrectEnabled = initialSettings.enabled && initialSettings.autocorrectEnabled
        wordProcessor.manualLayoutEnabled = initialSettings.enabled && initialSettings.manualLayoutSwitchEnabled
        applySystemAutocorrect(initialSettings.disableSystemAutocorrect)

        let probe = ContextProbe()
        probe.onContext = { [weak self] ctx in
            self?.hud.update(Self.render(ctx))
            self?.diagnostics.setContext(ctx)
            self?.suggestions.contextUpdated(ctx)
        }
        probe.onAXReadMs = { [weak self] ms in self?.diagnostics.recordAXReadMs(ms) }
        probe.onSuggest = { [weak self] in
            self?.suggestions.requestSuggestion()
        }
        probe.onAccept = { [weak self] in
            guard let self else { return }
            // Превью действия над выделением активно - Tab заменяет выделение, не подсказку.
            if self.selectionActions.isActive { self.selectionActions.acceptReplace() }
            else { self.suggestions.accept() }
        }
        probe.onAcceptAll = { [weak self] in
            guard let self else { return }
            if self.selectionActions.isActive { self.selectionActions.acceptReplace() }
            else { self.suggestions.acceptAll() }
        }
        probe.onContinueAfterAccept = { [weak self] ctx in
            self?.hud.update(Self.render(ctx))
            self?.suggestions.continueAfterAccept(ctx)
        }
        probe.onDismiss = { [weak self] in
            guard let self else { return }
            if self.selectionActions.isActive { self.selectionActions.dismiss() }
            else { self.suggestions.dismiss() }
        }
        probe.onUndo = { [weak self] in self?.wordProcessor.undoLast() }
        probe.onWordCompleted = { [weak self] text in self?.wordProcessor.wordCompleted(precedingText: text) ?? false }
        probe.onLayoutSwitch = { [weak self] text, selected in
            self?.wordProcessor.manualLayoutSwitch(precedingText: text, selectedText: selected)
        }
        probe.excludedBundleIds = Set(initialSettings.excludedBundleIds)
        probe.enhancedUIEnabled = initialSettings.electronSupport
        probe.clipboardEnabled = initialSettings.enabled && initialSettings.clipboardContextEnabled
        probe.setMemoryEnabled(initialSettings.enabled && initialSettings.memoryEnabled)
        probe.memoryProvider.ttlDays = initialSettings.memoryTTLDays
        probe.memoryProvider.learningExcluded = Set(initialSettings.memoryExcludedBundleIds)
        // MEM-06 D-06 (замыкает Plan 03): проводим DiagnosticsCenter в MemoryProvider, чтобы
        // secret-дроп на App-входе записи памяти инкрементировал счётчик secretDropped (только
        // число, сырой текст к метрике не доходит). setDiagnostics объявлен в MemoryProvider (Plan 03).
        probe.memoryProvider.setDiagnostics(diagnostics)
        settingsVM.onClearMemory = { [weak self] in
            self?.probe?.memoryProvider.clear()
            self?.adaptivePolicy.invalidate()   // статистика стёрта - кэш политики тоже
            let store = self?.suggestions.eventStore
            Task { await store?.clearAll() }
        }
        // MEM-02: adaptive policy per-app. Контроллер спрашивает параметры синхронно,
        // центр держит кэш статистики и освежает его фоном.
        suggestions.adaptiveParamsProvider = { [weak self] appId, global in
            self?.adaptivePolicy.params(for: appId, global: global) ?? global
        }
        settingsVM.onExportMemory = { [weak self] in self?.exportMemory() }
        settingsVM.memoryDbSizeProvider = { [weak self] in self?.probe?.memoryProvider.dbSizeBytes() }
        // UX-04: бенчмарк текущей модели - через контроллер (движок приватен там).
        settingsVM.onBenchModel = { [weak self] in await self?.suggestions.benchCurrentModel() }
        suggestions.onActiveChanged = { [weak self] active in self?.probe?.setSuggestionActive(active) }
        // Действия над выделением (UX-03): хоткей с выделением -> меню -> превью -> Tab/Esc.
        suggestions.onSelectionActions = { [weak self] ctx in self?.selectionActions.present(ctx: ctx) }
        selectionActions.transform = { [weak self] text, action in
            await self?.suggestions.transformSelection(text, action: action)
        }
        selectionActions.onActiveChanged = { [weak self] active in self?.probe?.setSuggestionActive(active) }
        suggestions.onOutcome = { [weak self] outcome in self?.diagnostics.setOutcome(outcome) }
        suggestions.onAcceptedSuggestion = { [weak self, weak probe] text, _ in
            guard let probe, probe.memoryProvider.enabled, let key = probe.lastMemThreadKey else { return }
            probe.memoryProvider.record(threadKey: key, kind: .accepted, text: text)
            self?.suggestions.predictorLearn(text)   // PERF-03: предиктор учится сразу
        }
        // PERF-03: начальная загрузка предиктора из памяти (пусто при выключенной памяти).
        suggestions.predictorBulkLearn(probe.memoryProvider.predictorTexts())
        monitorRunning = probe.start()
        if !monitorRunning {
            NSLog("ContextProbe: не стартовал (нет Input Monitoring?)")
        }
        self.probe = probe
        // Гейт телеметрии: SuggestionEventStore существует ТОЛЬКО при включённой телеметрии
        // (с Phase 4 default-ON, контроль в Privacy Center). storeQueue лениво создаёт
        // memory.sqlite - без гейта база материализовалась бы при выключенной телеметрии.
        applyTelemetry(initialSettings.suggestionTelemetryEnabled)
        // Призрак прячем при смене активного приложения: если фокус ушёл в другое окно без
        // нажатия клавиши, подсказка в прежнем поле осиротеет и «зависнет». Гасим overlay на
        // resign-key/space-change. Закрывает случай «остался висеть призрак».
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.suggestions.hideOnFocusLoss()
                self?.selectionActions.dismiss()   // превью выделения тоже не должно осиротеть
            }   // queue:.main -> мы на главном
        }
        // Стартовое состояние OCR-контекста (без запроса прав - только при включении тумблера).
        applyScreenContext(initialSettings.screenContextEnabled, requestPermission: false)
        if ProcessInfo.processInfo.environment["DOPISHI_DEBUG_HUD"] == "1" {
            hud.show()
        }
        // Мастер первого запуска (Phase 4, UX-01): пока не пройден - показываем на старте.
        if !initialSettings.onboardingCompleted {
            openOnboarding()
        }
    }

    /// Включить/выключить запись событий подсказок на лету (Privacy Center).
    /// Включение создаёт SuggestionEventStore (и memory.sqlite, если её ещё нет);
    /// выключение отцепляет store - новые события не пишутся, диагностика без метрик.
    private func applyTelemetry(_ enabled: Bool) {
        let on = enabled || ProcessInfo.processInfo.environment["DOPISHI_TELEMETRY"] == "1"
        if on {
            guard suggestions.eventStore == nil, let probe,
                  let queue = probe.memoryProvider.storeQueue else { return }
            let eventStore = SuggestionEventStore(dbQueue: queue)
            suggestions.eventStore = eventStore
            diagnostics.setEventStore(eventStore)
            adaptivePolicy.eventStore = eventStore
            // prune старых событий в фоне на старте/включении (TTL 7 дней)
            Task.detached(priority: .utility) { _ = await eventStore.prune() }
        } else if suggestions.eventStore != nil {
            suggestions.eventStore = nil
            diagnostics.setEventStore(nil)
            adaptivePolicy.eventStore = nil   // didSet чистит кэш - policy вернулась к global
        }
    }

    /// Экспорт памяти в JSON-файл (Privacy Center): NSSavePanel + фоновая выгрузка.
    private func exportMemory() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "dopishi-memory.json"
        panel.allowedContentTypes = [.json]
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let provider = probe?.memoryProvider else { return }
        Task { @MainActor in
            let data = await provider.exportJSON()
            do {
                guard let data else { throw CocoaError(.fileWriteUnknown) }
                try data.write(to: url)
            } catch {
                let alert = NSAlert()
                alert.messageText = L.tr("memory.export.error.title")
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
    }

    /// Применяет гашение системного автоисправления только при изменении флага
    /// (чтобы не перезаписывать глобальную настройку на каждое сохранение).
    private func applySystemAutocorrect(_ disabled: Bool) {
        guard lastSystemAutocorrectDisabled != disabled else { return }
        lastSystemAutocorrectDisabled = disabled
        SystemTextCorrection.apply(disabled: disabled)
    }

    /// OCR-контекст экрана: включает провайдер и (при включении тумблера) запрашивает права
    /// Screen Recording. На старте requestPermission=false - не пугаем диалогом без действия.
    private func applyScreenContext(_ enabled: Bool, requestPermission: Bool) {
        guard let probe else { return }
        let was = probe.ocrProvider.enabled
        probe.ocrProvider.enabled = enabled
        if enabled {
            if requestPermission, !was { ScreenCapturePermission.ensure() }
            probe.ocrProvider.warmUp()
        } else {
            probe.ocrProvider.invalidate()
        }
    }

    private func refresh() {
        let state = PermissionsManager.current()
        // если права есть, а монитор не стартовал ранее - пробуем снова
        if state.allGranted, !monitorRunning, let probe { monitorRunning = probe.start() }
        let settings = settingsStore.load()
        let modelPresent = ModelLocator.isPresent(fileName: settings.selectedModelFile)
        let status = AppRuntimeStatus(permissions: state, monitorRunning: monitorRunning,
                                      enabled: settings.enabled, modelPresent: modelPresent)
        let runtime = DiagnosticsRuntime(
            accessibility: state.accessibility,
            inputMonitoring: state.inputMonitoring,
            screenRecording: ScreenCapturePermission.has(),
            monitorRunning: monitorRunning,
            masterEnabled: settings.enabled,
            modelFile: settings.selectedModelFile,
            modelPresent: modelPresent,
            layout: settings.enabled && settings.layoutSwitchEnabled,
            manualLayout: settings.enabled && settings.manualLayoutSwitchEnabled,
            autocorrect: settings.enabled && settings.autocorrectEnabled,
            electron: settings.electronSupport,
            clipboard: settings.enabled && settings.clipboardContextEnabled,
            memory: settings.enabled && settings.memoryEnabled,
            screenContext: settings.screenContextEnabled)
        // Дедуп: ничего не изменилось -> не трогаем UI. Раньше полный rebuild меню + NSImage +
        // публикация в диагностику шли каждые 2с вхолостую (всплески CPU в простое). Дешёвые
        // опросы (права/модель) выше остаются - они нужны, чтобы ЗАМЕТИТЬ изменение.
        guard runtime != lastRuntime else { return }
        lastRuntime = runtime
        diagnostics.setRuntime(runtime)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: StatusPresentation.symbolName(for: state),
                                   accessibilityDescription: "Допиши")
        }
        rebuildMenu(state: state, status: status)
    }

    private func rebuildMenu(state: PermissionState, status: AppRuntimeStatus) {
        let menu = NSMenu()
        // Core отдаёт стабильный id статуса (D-11); при недостающих правах достраиваем список.
        let statusId = RuntimeStatusPresentation.menuTitle(for: status)
        let statusTitle = statusId == "status.needPermissions"
            ? L.tr(statusId, status.permissions.missingPermissions.joined(separator: ", "))
            : L.tr(statusId)
        menu.addItem(NSMenuItem(title: statusTitle, action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        if RuntimeStatusPresentation.needsModelDownload(status) {
            menu.addItem(NSMenuItem(title: L.tr("menu.downloadModel"), action: #selector(openSettings), keyEquivalent: ""))
            menu.addItem(.separator())
        }

        if !state.accessibility {
            let item = NSMenuItem(title: L.tr("menu.grantAccessibility"), action: #selector(grantAccessibility), keyEquivalent: "")
            menu.addItem(item)
        }
        if !state.inputMonitoring {
            let item = NSMenuItem(title: L.tr("menu.grantInputMonitoring"), action: #selector(grantInputMonitoring), keyEquivalent: "")
            menu.addItem(item)
        }
        if !state.allGranted {
            menu.addItem(.separator())
        }

        let diagItem = NSMenuItem(title: L.tr("menu.diagnostics"), action: #selector(openDiagnostics), keyEquivalent: "d")
        menu.addItem(diagItem)
        let hudItem = NSMenuItem(title: L.tr("menu.toggleHud"), action: #selector(toggleHUD), keyEquivalent: "")
        menu.addItem(hudItem)
        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: L.tr("menu.settings"), action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(settingsItem)
        let privacyItem = NSMenuItem(title: L.tr("menu.privacy"), action: #selector(openPrivacyCenter), keyEquivalent: "")
        menu.addItem(privacyItem)
        let onboardingItem = NSMenuItem(title: L.tr("menu.setupWizard"), action: #selector(openOnboardingFromMenu), keyEquivalent: "")
        menu.addItem(onboardingItem)
        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: L.tr("menu.quit"), action: #selector(quit), keyEquivalent: "q"))

        for item in menu.items where item.action != nil { item.target = self }
        statusItem.menu = menu
    }

    @objc private func grantAccessibility() {
        PermissionsManager.requestAccessibility()
        PermissionsManager.openAccessibilitySettings()
    }

    @objc private func grantInputMonitoring() {
        PermissionsManager.requestInputMonitoring()
        PermissionsManager.openInputMonitoringSettings()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    static func render(_ ctx: EditingContext) -> String {
        let rect = ctx.caretScreenRect.map { "(\(Int($0.minX)),\(Int($0.minY))) \(Int($0.width))x\(Int($0.height))" } ?? "-"
        // debug-HUD: реальный хвост текста до каретки (это отладочный инструмент, не скриншот).
        let tail = ctx.precedingText.isEmpty ? "-" : String(ctx.precedingText.suffix(60))
        let sel = (ctx.selectedText?.isEmpty == false) ? "  sel:\(ctx.selectedText!.suffix(30))" : ""
        // OCR-контекст экрана: видно, читается ли окружение (или off/пусто).
        let ocr = ctx.ocr.map { $0.windowText.isEmpty ? "(пусто)" : String($0.windowText.prefix(70)) } ?? "(off/nil)"
        return """
        app:    \(ctx.appBundleId ?? "-")
        tier:   \(ctx.capability.rawValue)\(ctx.isSecure ? "  [SECURE]" : "")
        caret:  \(rect)\(sel)
        text:   \(tail)
        ocr:    \(ocr)
        """
    }

    @objc private func toggleHUD() {
        if hud.isVisible { hud.hide() } else { hud.show() }
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let hosting = NSHostingController(rootView: SettingsView(vm: settingsVM))
            let win = NSWindow(contentViewController: hosting)
            win.title = L.tr("window.settings")
            win.styleMask = [.titled, .closable]
            win.isReleasedWhenClosed = false
            settingsWindow = win
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func openPrivacyCenter() {
        if privacyWindow == nil {
            let hosting = NSHostingController(rootView: PrivacyCenterView(vm: settingsVM))
            let win = NSWindow(contentViewController: hosting)
            win.title = L.tr("window.privacy")
            win.styleMask = [.titled, .closable]
            win.isReleasedWhenClosed = false
            privacyWindow = win
        }
        settingsVM.refreshPrivacyStats()
        NSApp.activate(ignoringOtherApps: true)
        privacyWindow?.center()
        privacyWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func openOnboardingFromMenu() {
        openOnboarding()
    }

    /// Окно мастера первого запуска (Phase 4, UX-01). Завершение помечает
    /// onboardingCompleted и закрывает окно.
    private func openOnboarding() {
        if onboardingWindow == nil {
            let vm = OnboardingViewModel(
                settingsVM: settingsVM,
                monitorRunning: { [weak self] in self?.monitorRunning ?? false },
                retryMonitor: { [weak self] in
                    guard let self, let probe = self.probe, !self.monitorRunning else { return }
                    self.monitorRunning = probe.start()
                })
            vm.onFinished = { [weak self] in
                guard let self else { return }
                self.settingsVM.config.onboardingCompleted = true
                self.settingsVM.persist()
                self.onboardingWindow?.close()
            }
            let hosting = NSHostingController(rootView: OnboardingView(vm: vm))
            let win = NSWindow(contentViewController: hosting)
            win.title = L.tr("window.onboarding")
            win.styleMask = [.titled, .closable]
            win.isReleasedWhenClosed = false
            onboardingWindow = win
        }
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow?.center()
        onboardingWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func openDiagnostics() {
        if diagnosticsWindow == nil {
            let hosting = NSHostingController(rootView: DiagnosticsView(center: diagnostics))
            let win = NSWindow(contentViewController: hosting)
            win.title = L.tr("window.diagnostics")
            win.styleMask = [.titled, .closable]
            win.isReleasedWhenClosed = false
            diagnosticsWindow = win
        }
        // Свежий снимок прав/модели сразу при открытии (не ждём 2-секундный таймер).
        refresh()
        Task { @MainActor in await diagnostics.refreshLatencyMetrics() }
        NSApp.activate(ignoringOtherApps: true)
        diagnosticsWindow?.center()
        diagnosticsWindow?.makeKeyAndOrderFront(nil)
    }
}
