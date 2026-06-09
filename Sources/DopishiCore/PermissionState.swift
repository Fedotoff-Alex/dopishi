import Foundation

public struct PermissionState: Sendable, Equatable {
    public let accessibility: Bool
    public let inputMonitoring: Bool

    public init(accessibility: Bool, inputMonitoring: Bool) {
        self.accessibility = accessibility
        self.inputMonitoring = inputMonitoring
    }

    public var allGranted: Bool { accessibility && inputMonitoring }
}

public enum StatusPresentation {
    public static func menuTitle(for state: PermissionState) -> String {
        if state.allGranted { return "Допиши: активно" }
        var missing: [String] = []
        if !state.accessibility { missing.append("Accessibility") }
        if !state.inputMonitoring { missing.append("Input Monitoring") }
        return "Допиши: нужны разрешения (" + missing.joined(separator: ", ") + ")"
    }

    public static func symbolName(for state: PermissionState) -> String {
        state.allGranted ? "text.cursor" : "exclamationmark.triangle"
    }
}
