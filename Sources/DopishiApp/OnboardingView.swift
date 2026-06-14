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
        modelPresent = ModelLocator.isPresent(fileName: settingsVM.config.selectedModelFile)
        if permissions.allGranted { retryMonitor() }
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
            Text("Допиши").font(.largeTitle.bold())
            Text("Локальный автокомплит для всего Mac: дописывает фразы в любом приложении, исправляет опечатки и раскладку. Модель работает на вашем Mac - текст никуда не отправляется.")
            Text("Мастер проведёт по шагам: два системных разрешения, выбор модели и проверка в тестовом поле.")
                .foregroundStyle(.secondary)
        }
    }

    private var accessibility: some View {
        permissionStep(
            title: "Шаг 1 из 4: Accessibility",
            explanation: "Чтобы видеть текст и позицию каретки в активном поле, Допиши нужно разрешение «Универсальный доступ» (Accessibility).",
            granted: vm.permissions.accessibility,
            grantTitle: "Выдать Accessibility…",
            grant: {
                PermissionsManager.requestAccessibility()
                PermissionsManager.openAccessibilitySettings()
            })
    }

    private var inputMonitoring: some View {
        permissionStep(
            title: "Шаг 2 из 4: Input Monitoring",
            explanation: "Чтобы реагировать на набор и клавишу Tab, нужно разрешение «Мониторинг ввода» (Input Monitoring).",
            granted: vm.permissions.inputMonitoring,
            grantTitle: "Выдать Input Monitoring…",
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
                Text(granted ? "Разрешение выдано" : "Разрешение ещё не выдано")
            }
            if !granted {
                Button(grantTitle, action: grant)
                Text("После переключателя в System Settings вернитесь сюда - статус обновится сам.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var model: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Шаг 3 из 4: модель").font(.title2.bold())
            Text("Подсказки генерирует локальная модель. Выберите и скачайте одну (можно сменить позже в настройках).")
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
                        Button(row.downloaded ? "Выбрать" : "Скачать") { settingsVM.choose(modelId: row.id) }
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
            Text("Шаг 4 из 4: проверка").font(.title2.bold())
            Text("Напишите пару слов - серым появится продолжение. Tab принимает слово, ` (клавиша над Tab) - всю фразу, Esc прячет.")
            TextEditor(text: $testText)
                .font(.system(size: 15))
                .frame(height: 120)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
            Text("Первая подсказка может занять пару секунд - модель прогревается.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var ready: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Готово").font(.title2.bold())
            statusRow(ok: vm.permissions.accessibility, label: "Accessibility")
            statusRow(ok: vm.permissions.inputMonitoring, label: "Input Monitoring")
            statusRow(ok: vm.isMonitorRunning, label: "Слежение за набором запущено")
            statusRow(ok: vm.modelPresent, label: "Модель скачана")
            Text("Допиши живёт в строке меню. Там же - настройки, приватность и диагностика.")
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
                Button("Назад") { vm.back() }
            }
            Spacer()
            Button(vm.step == .ready ? "Завершить" : "Далее") { vm.next() }
                .keyboardShortcut(.defaultAction)
                .disabled(!vm.stepVerified)
        }
    }
}
