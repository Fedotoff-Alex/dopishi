import Foundation

/// Категория приложения - основа матрицы профилей поведения (как у Cotypist).
public enum AppCategory: String, Equatable, Sendable {
    case terminal     // shell - молчим (конфликт с shell-автодополнением)
    case codeEditor   // редактор кода - молчим по умолчанию (конфликт с IntelliSense/Copilot)
    case browser      // браузер - автокомплит разрешён
    case native       // обычное приложение/текстовое поле - разрешён
    case unknown      // неизвестно - разрешён (не ломаем прежнее поведение)
}

/// Классификация приложения по bundleId и дефолтная политика автокомплита для категории.
/// Цель - не сыпать подсказки там, где они вредны (терминал, редактор кода), как делает
/// Cotypist (code-editor disabled by default, terminal silent). Ручной тап раскладки идёт
/// мимо этого гейта и продолжает работать везде.
public enum AppProfile {
    public static func category(for bundleId: String?) -> AppCategory {
        guard let id = bundleId?.lowercased() else { return .unknown }
        if isTerminal(id) { return .terminal }
        if isCodeEditor(id) { return .codeEditor }
        if browserIds.contains(id) { return .browser }
        if nativeIds.contains(id) { return .native }
        return .unknown
    }

    /// Разрешён ли автокомплит по умолчанию для категории.
    public static func allowsAutocomplete(_ category: AppCategory) -> Bool {
        switch category {
        case .terminal, .codeEditor: return false
        case .browser, .native, .unknown: return true
        }
    }

    static func isTerminal(_ id: String) -> Bool {
        terminalIds.contains(id)
    }
    static func isCodeEditor(_ id: String) -> Bool {
        codeEditorIds.contains(id) || id.hasPrefix("com.jetbrains.")
    }

    static let terminalIds: Set<String> = [
        "com.apple.terminal",
        "com.googlecode.iterm2",
        "dev.warp.warp-stable",
        "com.mitchellh.ghostty",
        "net.kovidgoyal.kitty",
        "io.alacritty",
        "co.zeit.hyper",
        "com.github.wez.wezterm",
    ]
    static let codeEditorIds: Set<String> = [
        "com.microsoft.vscode",
        "com.microsoft.vscodeinsiders",
        "com.visualstudio.code.oss",
        "com.vscodium",
        "com.apple.dt.xcode",
        "com.sublimetext.4",
        "com.sublimetext.3",
        "dev.zed.zed",
        "com.todesktop.230313mzl4w4u92", // Cursor
        "com.panic.nova",
        "com.barebones.bbedit",
    ]
    static let browserIds: Set<String> = [
        "com.apple.safari",
        "com.google.chrome",
        "com.brave.browser",
        "com.microsoft.edgemac",
        "org.mozilla.firefox",
        "company.thebrowser.browser", // Arc
        "ai.perplexity.comet",        // Comet
    ]
    static let nativeIds: Set<String> = [
        "com.apple.textedit",
        "com.apple.notes",
        "com.apple.mail",
        "com.apple.messages",
        "md.obsidian",
        "notion.id",
    ]
}
