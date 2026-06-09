import AppKit
import DopishiCore
import DopishiLLM
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var refreshTimer: Timer?
    private var probe: ContextProbe?
    private let hud = DebugHUD()
    private let suggestions = SuggestionController()
    private let wordProcessor = WordCompletionProcessor()
    private let settingsStore = SettingsStore()
    private lazy var settingsVM = SettingsViewModel(store: settingsStore)
    private var settingsWindow: NSWindow?
    private var monitorRunning = false
    private var lastSystemAutocorrectDisabled: Bool?

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
            self?.suggestions.contextUpdated(ctx)
        }
        probe.onSuggest = { [weak self] in
            self?.suggestions.requestSuggestion()
        }
        probe.onAccept = { [weak self] in self?.suggestions.accept() }
        probe.onAcceptAll = { [weak self] in self?.suggestions.acceptAll() }
        probe.onContinueAfterAccept = { [weak self] ctx in
            self?.hud.update(Self.render(ctx))
            self?.suggestions.continueAfterAccept(ctx)
        }
        probe.onDismiss = { [weak self] in self?.suggestions.dismiss() }
        probe.onUndo = { [weak self] in self?.wordProcessor.undoLast() }
        probe.onWordCompleted = { [weak self] text in self?.wordProcessor.wordCompleted(precedingText: text) ?? false }
        probe.onLayoutSwitch = { [weak self] text, selected in
            self?.wordProcessor.manualLayoutSwitch(precedingText: text, selectedText: selected)
        }
        probe.excludedBundleIds = Set(initialSettings.excludedBundleIds)
        probe.enhancedUIEnabled = initialSettings.electronSupport
        probe.clipboardEnabled = initialSettings.enabled && initialSettings.clipboardContextEnabled
        probe.setMemoryEnabled(initialSettings.enabled && initialSettings.memoryEnabled)
        settingsVM.onClearMemory = { [weak self] in self?.probe?.memoryProvider.clear() }
        suggestions.onActiveChanged = { [weak self] active in self?.probe?.setSuggestionActive(active) }
        monitorRunning = probe.start()
        if !monitorRunning {
            NSLog("ContextProbe: не стартовал (нет Input Monitoring?)")
        }
        self.probe = probe
        // Призрак прячем при смене активного приложения: если фокус ушёл в другое окно без
        // нажатия клавиши, подсказка в прежнем поле осиротеет и «зависнет». Cotabby так же гасит
        // overlay на resign-key/space-change. Закрывает случай «остался висеть призрак».
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.suggestions.dismiss() }   // queue:.main -> мы на главном
        }
        // Стартовое состояние OCR-контекста (без запроса прав - только при включении тумблера).
        applyScreenContext(initialSettings.screenContextEnabled, requestPermission: false)
        if ProcessInfo.processInfo.environment["DOPISHI_DEBUG_HUD"] == "1" {
            hud.show()
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
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: StatusPresentation.symbolName(for: state),
                                   accessibilityDescription: "Допиши")
        }
        rebuildMenu(state: state, status: status)
    }

    private func rebuildMenu(state: PermissionState, status: AppRuntimeStatus) {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: RuntimeStatusPresentation.menuTitle(for: status), action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        if RuntimeStatusPresentation.needsModelDownload(status) {
            menu.addItem(NSMenuItem(title: "Скачать модель…", action: #selector(openSettings), keyEquivalent: ""))
            menu.addItem(.separator())
        }

        if !state.accessibility {
            let item = NSMenuItem(title: "Выдать Accessibility…", action: #selector(grantAccessibility), keyEquivalent: "")
            menu.addItem(item)
        }
        if !state.inputMonitoring {
            let item = NSMenuItem(title: "Выдать Input Monitoring…", action: #selector(grantInputMonitoring), keyEquivalent: "")
            menu.addItem(item)
        }
        if !state.allGranted {
            menu.addItem(.separator())
        }

        let hudItem = NSMenuItem(title: "Показать/скрыть debug-HUD", action: #selector(toggleHUD), keyEquivalent: "")
        menu.addItem(hudItem)
        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Настройки…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(settingsItem)
        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Выход", action: #selector(quit), keyEquivalent: "q"))

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
            win.title = "Допиши - настройки"
            win.styleMask = [.titled, .closable]
            win.isReleasedWhenClosed = false
            settingsWindow = win
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
