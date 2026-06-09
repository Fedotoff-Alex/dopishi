import AppKit

/// Перевод AX-координат каретки (top-left, глобальные CG) в AppKit (bottom-left).
/// Логика Cotabby: отражаем по Y относительно ИМЕННО того экрана, на котором каретка
/// (per-display flip через CGDisplayBounds), иначе на нескольких мониторах подсказка уезжает.
enum DisplayCoordinateConverter {
    private struct DisplayInfo {
        let appKitFrame: CGRect   // screen.frame (Cocoa, bottom-left)
        let cgBounds: CGRect      // CGDisplayBounds(id) (CG, top-left)
    }

    private static func displays() -> [DisplayInfo] {
        NSScreen.screens.compactMap { screen in
            guard let n = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            else { return nil }
            return DisplayInfo(appKitFrame: screen.frame,
                               cgBounds: CGDisplayBounds(CGDirectDisplayID(n.uint32Value)))
        }
    }

    /// axRect - top-left глобальные CG-координаты каретки. Возврат - Cocoa bottom-left rect.
    static func cocoaRect(fromAXRect axRect: CGRect) -> CGRect {
        let infos = displays()
        let mid = CGPoint(x: axRect.midX, y: axRect.midY)
        let onScreen = infos.first(where: { $0.cgBounds.contains(mid) })
            ?? infos.max(by: { a, b in
                let ai = axRect.intersection(a.cgBounds), bi = axRect.intersection(b.cgBounds)
                return (ai.width * ai.height) < (bi.width * bi.height)
            })
        if let d = onScreen {
            let localX = axRect.minX - d.cgBounds.minX
            let localY = axRect.minY - d.cgBounds.minY
            return CGRect(x: d.appKitFrame.minX + localX,
                          y: d.appKitFrame.maxY - localY - axRect.height,
                          width: axRect.width, height: axRect.height)
        }
        // Fallback: union всех экранов
        let union = NSScreen.screens.map(\.frame).reduce(CGRect.null) { $0.union($1) }
        return CGRect(x: axRect.minX, y: union.maxY - axRect.minY - axRect.height,
                      width: axRect.width, height: axRect.height)
    }
}
