import SwiftUI
import DopishiCore
import DopishiLLM

/// Состояние мастера первого запуска (Phase 4, UX-01). Поллит права раз в секунду,
/// пока окно открыто - права выдаются в System Settings, вне приложения.
@MainActor
final class OnboardingViewModel: ObservableObject {
    enum Step: Int, CaseIterable {
        case welcome, accessibility, inputMonitoring, model, test, ready
    }

    @Published var step: Step = .welcome
    @Published private(set) var permissions = PermissionsManager.current()
    @Published private(set) var modelPresent = false

    let settingsVM: SettingsViewModel
    private let monitorRunning: () -> Bool
    private let retryMonitor: () -> Void
    var onFinished: (() -> Void)?

    init(settingsVM: SettingsViewModel,
         monitorRunning: @escaping () -> Bool,
         retryMonitor: @escaping () -> Void) {
        self.settingsVM = settingsVM
        self.monitorRunning = monitorRunning
        self.retryMonitor = retryMonitor
        refresh()
    }

    func refresh() {
        permissions = PermissionsManager.current()
        // ГЕЙТ ШАГА (D-03): преселект только на шаге модели - не пишет selectedModelFile
        // в init/на ранних шагах (refresh зовётся из init и pollTick раз в секунду).
        if step == .model { preselectRecommendedIfNeeded() }
        modelPresent = ModelLocator.isPresent(fileName: settingsVM.config.selectedModelFile)
        if permissions.allGranted { retryMonitor() }
    }

    /// Преселект рекомендованной модели как дефолт - ТОЛЬКО до первого ручного выбора (D-03/D-04, SC3).
    /// НЕ ставит manuallySelected (это автоматика-предложение, не явный выбор) и НЕ качает (автозагрузка вне scope).
    func preselectRecommendedIfNeeded() {
        guard !settingsVM.config.manuallySelected else { return }   // SC3: ручной выбор не перетирается
        let locale = Locale.preferredLanguages.first ?? "en"
        let rec = ModelCatalog.recommended(forLocale: locale, ramGB: settingsVM.ramGB)
        guard settingsVM.config.selectedModelFile != rec.fileName else { return }
        settingsVM.config.selectedModelFile = rec.fileName
        settingsVM.persist()
    }

    var isMonitorRunning: Bool { monitorRunning() }

    /// Верификация текущего шага: «Далее» активна только когда шаг выполнен.
    var stepVerified: Bool {
        switch step {
        case .welcome: return true
        case .accessibility: return permissions.accessibility
        case .inputMonitoring: return permissions.inputMonitoring
        case .model: return modelPresent && settingsVM.downloadingId == nil
        case .test: return true
        case .ready: return true
        }
    }

    func next() {
        guard let n = Step(rawValue: step.rawValue + 1) else {
            onFinished?()
            return
        }
        step = n
        refresh()
    }

    func back() {
        guard let p = Step(rawValue: step.rawValue - 1) else { return }
        step = p
    }
}

/// Мастер первого запуска: объяснение -> Accessibility -> Input Monitoring ->
/// модель -> тестовое поле -> статус готовности.
struct OnboardingView: View {
    @ObservedObject var vm: OnboardingViewModel
    @ObservedObject var settingsVM: SettingsViewModel
    @State private var testText = ""
    /// Права меняются в System Settings, вне приложения - поллим, пока мастер на экране.
    /// onReceive снимает подписку вместе с View (без Timer в VM и проблем deinit/Sendable).
    private let pollTick = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    init(vm: OnboardingViewModel) {
        self.vm = vm
        self.settingsVM = vm.settingsVM
    }

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(24)
            Divider()
            footer.padding(16)
        }
        .frame(width: 520, height: 460)
        .onReceive(pollTick) { _ in vm.refresh() }
    }

    @ViewBuilder private var content: some View {
        switch vm.step {
        case .welcome: welcome
        case .accessibility: accessibility
        case .inputMonitoring: inputMonitoring
        case .model: model
        case .test: test
        case .ready: ready
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L.tr("onboarding.welcome.title")).font(.largeTitle.bold())
            Text(L.tr("onboarding.welcome.body"))
            Text(L.tr("onboarding.welcome.steps"))
                .foregroundStyle(.secondary)
        }
    }

    private var accessibility: some View {
        permissionStep(
            title: L.tr("onboarding.accessibility.title"),
            explanation: L.tr("onboarding.accessibility.explanation"),
            granted: vm.permissions.accessibility,
            grantTitle: L.tr("onboarding.accessibility.grant"),
            grant: {
                PermissionsManager.requestAccessibility()
                PermissionsManager.openAccessibilitySettings()
            })
    }

    private var inputMonitoring: some View {
        permissionStep(
            title: L.tr("onboarding.inputMonitoring.title"),
            explanation: L.tr("onboarding.inputMonitoring.explanation"),
            granted: vm.permissions.inputMonitoring,
            grantTitle: L.tr("onboarding.inputMonitoring.grant"),
            grant: {
                PermissionsManager.requestInputMonitoring()
                PermissionsManager.openInputMonitoringSettings()
            })
    }

    private func permissionStep(title: String, explanation: String, granted: Bool,
                                grantTitle: String, grant: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.title2.bold())
            Text(explanation)
            HStack(spacing: 8) {
                Image(systemName: granted ? "checkmark.circle.fill" : "circle.dashed")
                    .foregroundStyle(granted ? .green : .secondary)
                Text(granted ? L.tr("onboarding.permission.granted") : L.tr("onboarding.permission.notGranted"))
            }
            if !granted {
                Button(grantTitle, action: grant)
                Text(L.tr("onboarding.permission.afterToggle"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var model: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L.tr("onboarding.model.title")).font(.title2.bold())
            Text(L.tr("onboarding.model.body"))
            List(settingsVM.modelRows) { row in
                HStack(spacing: 10) {
                    Image(systemName: row.selected && row.downloaded ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(row.selected && row.downloaded ? Color.accentColor : Color.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.name)
                        Text(row.detail).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if row.downloading {
                        ProgressView(value: settingsVM.downloadProgress).frame(width: 80)
                    } else if !(row.selected && row.downloaded) {
                        Button(row.downloaded ? L.tr("settings.model.select") : L.tr("settings.model.download")) { settingsVM.choose(modelId: row.id) }
                            .disabled(settingsVM.downloadingId != nil)
                    }
                }
            }
            .frame(minHeight: 180)
            if !settingsVM.statusText.isEmpty {
                Text(settingsVM.statusText).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var test: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L.tr("onboarding.test.title")).font(.title2.bold())
            Text(L.tr("onboarding.test.body"))
            TextEditor(text: $testText)
                .font(.system(size: 15))
                .frame(height: 120)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
            Text(L.tr("onboarding.test.warmup"))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var ready: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L.tr("onboarding.ready.title")).font(.title2.bold())
            // Имена системных разрешений - технические, не переводятся (совпадают с macOS).
            statusRow(ok: vm.permissions.accessibility, label: "Accessibility")
            statusRow(ok: vm.permissions.inputMonitoring, label: "Input Monitoring")
            statusRow(ok: vm.isMonitorRunning, label: L.tr("onboarding.ready.monitorRunning"))
            statusRow(ok: vm.modelPresent, label: L.tr("onboarding.ready.modelDownloaded"))
            Text(L.tr("onboarding.ready.body"))
                .foregroundStyle(.secondary)
        }
    }

    private func statusRow(ok: Bool, label: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(ok ? .green : .red)
            Text(label)
        }
    }

    private var footer: some View {
        HStack {
            if vm.step != .welcome {
                Button(L.tr("onboarding.back")) { vm.back() }
            }
            Spacer()
            Button(vm.step == .ready ? L.tr("onboarding.finish") : L.tr("onboarding.next")) { vm.next() }
                .keyboardShortcut(.defaultAction)
                .disabled(!vm.stepVerified)
        }
    }
}
