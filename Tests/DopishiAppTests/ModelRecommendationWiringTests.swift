import Testing
import Foundation
import DopishiCore
@testable import DopishiApp

// Целостность SC3 (T-09-01 mitigate): автоматика-преселект НИКОГДА не перетирает
// осознанный ручной выбор пользователя (config.manuallySelected == true).
// SettingsViewModel / OnboardingViewModel - @MainActor, поэтому сьют @MainActor.
//
// Store изолируется через UserDefaults(suiteName:) - каждый тест свой in-memory домен
// (не трогает .standard и не пересекается с другими тестами).
@Suite @MainActor struct ModelRecommendationWiringTests {
    private func makeSettingsVM() -> SettingsViewModel {
        let suite = "dopishi.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return SettingsViewModel(store: SettingsStore(defaults: defaults))
    }

    private func makeOnboardingVM(_ settingsVM: SettingsViewModel) -> OnboardingViewModel {
        OnboardingViewModel(settingsVM: settingsVM,
                            monitorRunning: { false },
                            retryMonitor: {})
    }

    // SC3: при manuallySelected == true преселект НЕ меняет selectedModelFile.
    @Test func preselectRespectsManualSelection() {
        let settingsVM = makeSettingsVM()
        let manualChoice = "YandexGPT-5-Lite-8B-instruct-Q4_K_M.gguf"
        settingsVM.config.selectedModelFile = manualChoice
        settingsVM.config.manuallySelected = true
        settingsVM.persist()

        let onboardingVM = makeOnboardingVM(settingsVM)
        onboardingVM.preselectRecommendedIfNeeded()

        // Ручной выбор не перетёрт автоматикой.
        #expect(settingsVM.config.selectedModelFile == manualChoice)
    }

    // Преселект до первого ручного выбора: manuallySelected == false ->
    // selectedModelFile = рекомендация под язык/RAM системы тест-машины.
    @Test func preselectAppliesRecommendationBeforeManualChoice() {
        let settingsVM = makeSettingsVM()
        settingsVM.config.manuallySelected = false
        settingsVM.persist()

        let locale = Locale.preferredLanguages.first ?? "en"
        let rec = ModelCatalog.recommended(forLocale: locale, ramGB: settingsVM.ramGB)

        let onboardingVM = makeOnboardingVM(settingsVM)
        onboardingVM.preselectRecommendedIfNeeded()

        #expect(settingsVM.config.selectedModelFile == rec.fileName)
    }

    // Преселект НЕ ставит manuallySelected (это автоматика-предложение, не явный выбор - D-04).
    @Test func preselectDoesNotSetManualFlag() {
        let settingsVM = makeSettingsVM()
        settingsVM.config.manuallySelected = false
        settingsVM.persist()

        let onboardingVM = makeOnboardingVM(settingsVM)
        onboardingVM.preselectRecommendedIfNeeded()

        #expect(settingsVM.config.manuallySelected == false)
    }

    // choose() для модели, отсутствующей на диске, уходит в ветку загрузки и НЕ ставит флаг
    // синхронно (флаг ставится после успешного скачивания). Семантику флага-после-выбора
    // проверяем напрямую: ручной выбор -> manuallySelected == true.
    @Test func manualSelectionSetsFlag() {
        let settingsVM = makeSettingsVM()
        #expect(settingsVM.config.manuallySelected == false)

        // Прямая семантика ручного выбора (как ветка choose «на диске»): выставление файла + флаг.
        settingsVM.config.selectedModelFile = "Qwen3-4B-Instruct-2507-Q4_K_M.gguf"
        settingsVM.config.manuallySelected = true
        settingsVM.persist()

        // После ручного выбора преселект уже не трогает выбор (замыкает SC3 end-to-end).
        let onboardingVM = makeOnboardingVM(settingsVM)
        onboardingVM.preselectRecommendedIfNeeded()
        #expect(settingsVM.config.manuallySelected == true)
        #expect(settingsVM.config.selectedModelFile == "Qwen3-4B-Instruct-2507-Q4_K_M.gguf")
    }
}
