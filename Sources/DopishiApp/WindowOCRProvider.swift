import AppKit
import CoreGraphics
import DopishiCore

/// Оркестратор OCR-контекста: гейты (тумблер/secure/excluded/права), throttle+кэш по окну,
/// фоновый (detached) захват+OCR. Держит latest - последний ГОТОВЫЙ снимок для EditingContext.
/// Генерация подсказки НИКОГДА не ждёт OCR - берёт latest или nil.
@MainActor
final class WindowOCRProvider {
    var enabled = false
    private(set) var latest: OCRContext?

    private var cache: [CGWindowID: OCRContext] = [:]
    private var inFlight: Set<CGWindowID> = []
    private var lastCaptureAt: [CGWindowID: Date] = [:]
    /// Окно, актуальное СЕЙЧАС. Detached OCR-таск завершается асинхронно; если за это время
    /// фокус ушёл, его результат НЕ должен стать latest (иначе старое окно протечёт в новый промпт).
    private var currentWindowId: CGWindowID?
    private let minInterval: TimeInterval = 4.0
    private let ocrMax = 600
    private let maxWidth = 1600

    /// Прогрев ScreenCaptureKit (первый захват иначе тормозит).
    func warmUp() {
        guard enabled else { return }
        Task.detached(priority: .utility) { await WindowCapture.warmUp() }
    }

    /// Очистить готовый снимок (на смену окна/приложения/secure) - чтобы не подмешать чужое окно.
    /// Сбрасываем и currentWindowId: in-flight таск старого окна не применит результат.
    func invalidate() { latest = nil; currentWindowId = nil }

    /// Вызывать на СМЕНЕ окна/фокуса (НЕ на каждый keystroke). Мгновенно отдаёт кэш в latest,
    /// при необходимости запускает фоновый захват+OCR.
    /// DOPISHI_OCR_DEBUG=1 - сквозной лог по узлам (видно, на каком шаге рвётся).
    nonisolated static let debug = ProcessInfo.processInfo.environment["DOPISHI_OCR_DEBUG"] == "1"
    nonisolated static func log(_ s: @autoclosure () -> String) { if debug { NSLog("DopishiOCR: %@", s()) } }

    func onFocusedWindowChanged(windowId: CGWindowID?, windowFrame: CGRect?,
                                caretScreenRect: CGRect?, isSecure: Bool, allowedApp: Bool,
                                fieldText: String = "") {
        // НЕ гейтим на ScreenCapturePermission.has() (CGPreflight ненадёжен - даёт false при
        // наличии гранта). Пытаемся захватить; реальную ошибку прав поймаем от ScreenCaptureKit.
        guard enabled, !isSecure, allowedApp, let windowId else {
            Self.log("gate off: enabled=\(enabled) secure=\(isSecure) allowed=\(allowedApp) "
                     + "windowId=\(windowId.map(String.init) ?? "nil")")
            latest = nil
            currentWindowId = nil
            return
        }
        currentWindowId = windowId
        latest = cache[windowId]   // мгновенно - готовый снимок, если есть
        let elapsed = lastCaptureAt[windowId].map { Date().timeIntervalSince($0) } ?? .infinity
        guard elapsed > minInterval, !inFlight.contains(windowId) else { return }
        inFlight.insert(windowId)
        lastCaptureAt[windowId] = Date()

        let maxW = maxWidth
        let budget = ocrMax
        let field = fieldText
        Task.detached(priority: .utility) { [weak self] in
            do {
                let cg = try await WindowCapture.capture(windowID: windowId, maxWidth: maxW)
                // Кроп региона у поля: полоса над кареткой (переписка/документ), а не всё окно с
                // хромом. Нет геометрии каретки или кроп не вышел -> OCR всего окна (как было).
                let (ocrImage, caretPx): (CGImage, CGPoint?) = {
                    let base = Self.caretPx(caretScreenRect: caretScreenRect, windowFrame: windowFrame,
                                            imageWidth: cg.width, imageHeight: cg.height)
                    guard let caret = caretScreenRect, let win = windowFrame,
                          let plan = OCRCropGeometry.plan(caretScreenRect: caret, windowFrame: win,
                                                          imageWidth: cg.width, imageHeight: cg.height),
                          let cropped = cg.cropping(to: plan.cropRectPx) else { return (cg, base) }
                    return (cropped, plan.caretInCropPx)
                }()
                let lines = WindowOCR.recognizeSync(in: ocrImage)
                // assemble сам чистит OCR-шум и нейтрализует инъекцию построчно (sanitizeOCR) +
                // держит бюджет, так что отдельный sanitize здесь больше не нужен.
                let text = WindowOCR.assemble(lines, caretPx: caretPx, fieldTail: field, maxChars: budget)
                // winPt vs capture - чтобы видеть расхождение AX-frame и SCK-contentRect (см. допущение
                // в OCRCropGeometry).
                let winPt = windowFrame.map { "\(Int($0.width))x\(Int($0.height))" } ?? "nil"
                Self.log("win=\(windowId) winPt=\(winPt) capture=\(cg.width)x\(cg.height) "
                         + "ocr=\(ocrImage.width)x\(ocrImage.height) lines=\(lines.count) "
                         + "caretPx=\(caretPx.map { "\(Int($0.x)),\(Int($0.y))" } ?? "nil") "
                         + "textLen=\(text.count) text='\(text.prefix(60))'")
                let ctx = text.isEmpty ? nil : OCRContext(windowText: text, capturedAt: Date(), windowId: windowId)
                await self?.finish(windowId, context: ctx)
            } catch {
                Self.log("win=\(windowId) capture FAILED: \(error)")   // noPermission vs windowNotFound
                await self?.finish(windowId, context: nil)
            }
        }
    }

    private func finish(_ id: CGWindowID, context: OCRContext?) {
        inFlight.remove(id)
        if let context {
            cache[id] = context
            // latest обновляем ТОЛЬКО если окно всё ещё актуально - иначе фокус ушёл, пока шёл
            // detached OCR, и применять старый результат нельзя (утечка старого окна в новый промпт).
            guard id == currentWindowId else { return }
            latest = context
        }
    }

    /// Каретка (экранные top-left коорд.) -> пиксель в захваченном (даунскейл) изображении окна.
    /// Отдельные scaleX/scaleY (как в OCRCropGeometry.plan) - изображение может иметь аспект,
    /// чуть отличный от окна (truncation cfg.height, расхождение SCK contentRect и AX-frame).
    nonisolated private static func caretPx(caretScreenRect: CGRect?, windowFrame: CGRect?,
                                            imageWidth: Int, imageHeight: Int) -> CGPoint? {
        guard let caret = caretScreenRect, let win = windowFrame,
              win.width > 0, win.height > 0 else { return nil }
        let scaleX = CGFloat(imageWidth) / win.width
        let scaleY = CGFloat(imageHeight) / win.height
        return CGPoint(x: (caret.midX - win.minX) * scaleX, y: (caret.midY - win.minY) * scaleY)
    }
}
