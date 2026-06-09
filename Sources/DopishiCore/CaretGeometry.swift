import Foundation
import CoreGraphics

/// Перевод координат каретки из системы Accessibility (origin сверху-слева, y вниз)
/// в систему AppKit (origin снизу-слева главного экрана, y вверх).
public enum CaretGeometry {
    /// Левый-нижний угол для окна-оверлея, выровненный по низу каретки.
    public static func cocoaOrigin(axScreenRect rect: CGRect, primaryScreenHeight: CGFloat) -> CGPoint {
        CGPoint(x: rect.minX, y: primaryScreenHeight - rect.maxY)
    }
}
