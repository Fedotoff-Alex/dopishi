import ScreenCaptureKit
import CoreGraphics

/// Захват изображения ОДНОГО окна через ScreenCaptureKit (macOS 14+, не deprecated).
/// SCShareableContent -> SCWindow по CGWindowID -> SCContentFilter -> SCScreenshotManager.
enum WindowCapture {
    enum CaptureError: Error { case noPermission, windowNotFound }

    /// Захват окна по CGWindowID -> CGImage. Даунскейл до maxWidth для скорости и дешёвого OCR.
    /// НЕ гейтим на CGPreflightScreenCaptureAccess - он ненадёжен (возвращает false при наличии
    /// гранта). Если прав реально нет, бросит сам SCShareableContent/captureImage - ловим выше.
    static func capture(windowID: CGWindowID, maxWidth: Int = 1600) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let win = content.windows.first(where: { $0.windowID == windowID }) else {
            throw CaptureError.windowNotFound
        }
        let filter = SCContentFilter(desktopIndependentWindow: win)

        let cfg = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        let fullW = Int(filter.contentRect.width * scale)
        let fullH = Int(filter.contentRect.height * scale)
        if fullW > maxWidth, fullW > 0 {
            let k = Double(maxWidth) / Double(fullW)
            cfg.width = maxWidth
            cfg.height = max(1, Int(Double(fullH) * k))
        } else {
            cfg.width = max(1, fullW)
            cfg.height = max(1, fullH)
        }
        cfg.showsCursor = false
        cfg.scalesToFit = true

        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
    }

    /// Прогрев SCShareableContent - первый вызов после старта/выдачи прав заметно медленнее.
    static func warmUp() async {
        _ = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
    }
}
