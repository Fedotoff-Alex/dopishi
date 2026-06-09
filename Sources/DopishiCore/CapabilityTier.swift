import Foundation

public enum DopishiCore {
    public static let version = "0.1.0"
}

public enum CapabilityTier: String, Sendable, Equatable {
    case full       // есть текст и экранный rect каретки
    case textOnly   // есть текст, нет rect каретки
    case none       // нет пригодного текста
}

public enum Capability {
    public static func classify(hasText: Bool, hasCaretRect: Bool) -> CapabilityTier {
        guard hasText else { return .none }
        return hasCaretRect ? .full : .textOnly
    }
}
