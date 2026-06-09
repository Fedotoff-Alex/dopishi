import Foundation
import CoreGraphics

/// Расчёт размера кегля ghost-подсказки по образцу Cotabby: от высоты каретки,
/// откалиброванной метриками шрифта поля. ascender > 0, descender < 0 (у NSFont).
public enum GhostFontMetrics {
    /// - caretHeight: визуальная высота каретки/строки.
    /// - fieldPointSize/ascender/descender: метрики шрифта поля (если известны).
    /// - fallbackRatio: коэффициент когда метрик шрифта нет (типично ~0.72).
    public static func pointSize(
        caretHeight: CGFloat,
        fieldPointSize: CGFloat? = nil,
        fieldAscender: CGFloat? = nil,
        fieldDescender: CGFloat? = nil,
        fallbackRatio: CGFloat = 0.72,
        minimum: CGFloat = 9,
        maximum: CGFloat = 48
    ) -> CGFloat {
        let ratio: CGFloat
        if let p = fieldPointSize, let a = fieldAscender, let d = fieldDescender, p > 0 {
            let glyphBox = a - d            // полная высота глиф-бокса (d отрицателен)
            ratio = glyphBox > 0 ? p / glyphBox : fallbackRatio
        } else {
            ratio = fallbackRatio
        }
        return min(maximum, max(minimum, caretHeight * ratio))
    }
}
