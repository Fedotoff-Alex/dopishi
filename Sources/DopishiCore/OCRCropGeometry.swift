import Foundation
import CoreGraphics

/// План кропа OCR-региона: прямоугольник в пикселях захваченного (даунскейл) изображения окна
/// + позиция каретки внутри этого кропа (для ранжирования в WindowOCR.assemble).
public struct OCRCropPlan: Equatable, Sendable {
    public let cropRectPx: CGRect      // пиксели изображения, origin top-left
    public let caretInCropPx: CGPoint  // каретка относительно origin кропа

    public init(cropRectPx: CGRect, caretInCropPx: CGPoint) {
        self.cropRectPx = cropRectPx
        self.caretInCropPx = caretInCropPx
    }
}

/// Геометрия кропа OCR-региона: высокая полоса контекста над кареткой.
///
/// Идея (главное): захватываем НЕ тесную рамку вокруг поля, а высокую полосу, дно которой у верха
/// каретки, и которая тянется ВВЕРХ на `bandHeightPt` в контент (переписку/документ над полем).
/// Это и даёт OCR увидеть предыдущие сообщения/абзацы, а не только текущее поле. Верхний хром
/// (тулбар/титул) геометрически НЕ вырезается - он отсекается позже
/// текстом (echo-drop + sanitizeOCR). Полоса лишь не даёт уехать далеко вверх к хрому в высоком окне.
///
/// Все входные прямоугольники - экранные координаты top-left (как у нас caret/window уже идут,
/// AppKit<->CG флип НЕ нужен).
///
/// ДОПУЩЕНИЕ (load-bearing): размер `windowFrame` (AX kAXSize, точки) равен размеру захвата
/// (SCK contentRect, точки), и пиксель изображения (0,0) = верх-лево окна. Для обычных окон
/// совпадает. Может расходиться на fullscreen/tiled/смещённых окнах -
/// тогда scaleX/scaleY и origin поедут. При DOPISHI_OCR_DEBUG провайдер логирует winPt vs capture,
/// чтобы расхождение было видно. Полный фикс (брать contentRect из WindowCapture) - на будущее.
public enum OCRCropGeometry {
    /// - Parameters:
    ///   - caretScreenRect: каретка, экранные top-left точки.
    ///   - windowFrame: рамка окна, экранные top-left точки.
    ///   - imageWidth/imageHeight: размеры захваченного изображения окна, пиксели.
    ///   - bandHeightPt: высота полосы над кареткой (по умолчанию 800).
    ///   - fallbackWidthPt: номинальная ширина для caret-only ветки (по умолчанию 700).
    ///   - horizontalPaddingPt: добавка по бокам (по умолчанию 160, *2 в ширину).
    /// - Returns: план кропа, либо nil при вырожденных входах.
    public static func plan(caretScreenRect: CGRect, windowFrame: CGRect,
                            imageWidth: Int, imageHeight: Int,
                            bandHeightPt: CGFloat = 800, fallbackWidthPt: CGFloat = 700,
                            horizontalPaddingPt: CGFloat = 160) -> OCRCropPlan? {
        guard windowFrame.width > 0, windowFrame.height > 0,
              imageWidth > 0, imageHeight > 0 else { return nil }

        // Каретка вне рамки окна = stale/битый AX-caret (известная боль Electron/Claude: размер
        // правдоподобный, координаты старые). Без этого гейта клемп всё равно прижмёт полосу к
        // краю окна, а кроп ляжет на регион, который юзер не редактирует. Возвращаем nil ->
        // провайдер откатывается на OCR всего окна (прежнее мягкое поведение). Slack 4pt на край.
        let caretMid = CGPoint(x: caretScreenRect.midX, y: caretScreenRect.midY)
        guard windowFrame.insetBy(dx: -4, dy: -4).contains(caretMid) else { return nil }

        let scaleX = CGFloat(imageWidth) / windowFrame.width
        let scaleY = CGFloat(imageHeight) / windowFrame.height

        let targetH = min(bandHeightPt, windowFrame.height)
        let targetW = min(fallbackWidthPt + horizontalPaddingPt * 2, windowFrame.width)

        // X центрируем по каретке; Y - дно полосы у верха каретки, полоса тянется вверх.
        let proposedX = caretScreenRect.midX - targetW / 2
        let proposedY = caretScreenRect.minY - targetH

        // Клемп в рамку окна. targetW/H <= размеров окна, так что max..min корректен.
        let clampedX = min(max(proposedX, windowFrame.minX), windowFrame.maxX - targetW)
        let clampedY = min(max(proposedY, windowFrame.minY), windowFrame.maxY - targetH)

        // Экранные точки -> локальные точки окна -> пиксели изображения.
        let cropPx = CGRect(x: (clampedX - windowFrame.minX) * scaleX,
                            y: (clampedY - windowFrame.minY) * scaleY,
                            width: targetW * scaleX,
                            height: targetH * scaleY).integral

        let bounded = cropPx.intersection(CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))
        guard !bounded.isNull, bounded.width >= 1, bounded.height >= 1 else { return nil }

        let caretFull = CGPoint(x: (caretScreenRect.midX - windowFrame.minX) * scaleX,
                                y: (caretScreenRect.midY - windowFrame.minY) * scaleY)
        let caretInCrop = CGPoint(x: caretFull.x - bounded.minX, y: caretFull.y - bounded.minY)
        return OCRCropPlan(cropRectPx: bounded, caretInCropPx: caretInCrop)
    }
}
