import Vision
import CoreGraphics
import DopishiCore

struct OCRLine {
    let text: String
    let confidence: VNConfidence
    let boundingBoxPx: CGRect   // пиксели изображения, origin top-left (как скриншот)
}

/// Vision OCR окна на ru+en. Тяжёлый (нейросеть, сотни мс) - вызывать ТОЛЬКО из фонового
/// (detached) контекста, никогда не на main и не в горячем пути ввода.
enum WindowOCR {
    /// CGImage -> строки (ru+en) с пиксельными top-left bbox. СИНХРОННЫЙ (зовётся из detached Task,
    /// уже вне main; так избегаем @Sendable-захвата несендабельного CGImage в очередь).
    static func recognizeSync(in image: CGImage) -> [OCRLine] {
        let request = VNRecognizeTextRequest()
        request.revision = VNRecognizeTextRequestRevision3   // ru/en c macOS 13, фиксируем явно
        request.recognitionLevel = .accurate                 // .fast не тянет кириллицу надёжно
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["ru-RU", "en-US"]
        request.minimumTextHeight = 0

        let w = image.width, h = image.height
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do { try handler.perform([request]) } catch { return [] }

        var lines: [OCRLine] = []
        for obs in request.results ?? [] {
            guard let cand = obs.topCandidates(1).first, cand.confidence >= 0.3 else { continue }
            let px = VNImageRectForNormalizedRect(obs.boundingBox, w, h)
            // boundingBox: origin lower-left -> переворот в top-left под систему скриншота.
            let topLeft = CGRect(x: px.origin.x, y: CGFloat(h) - px.origin.y - px.height,
                                 width: px.width, height: px.height)
            lines.append(OCRLine(text: cand.string, confidence: cand.confidence, boundingBoxPx: topLeft))
        }
        return lines
    }

    /// Собрать windowText: приоритет строкам ВЫШЕ и рядом с кареткой (контекст обычно над полем),
    /// до maxChars; вернуть в визуальном порядке сверху-вниз. caretPx - каретка в пикселях
    /// изображения (top-left). nil -> берём верх окна. fieldTail - текст поля до каретки: строки,
    /// которые это эхо собственного набора, выбрасываем (анти-эхо: свой же вывод обратно не подаём).
    static func assemble(_ lines: [OCRLine], caretPx: CGPoint?, fieldTail: String = "",
                         maxChars: Int = 600) -> String {
        let fieldNorm = normalizeForEcho(fieldTail)
        // Фильтр + санитайз построчно. sanitizeOCR не только роняет целиком-мусорные строки, но и
        // чистит токен-шум ВНУТРИ строки (числа, gLVWrt, repeated-glyph). Отдаём ОЧИЩЕННЫЙ текст -
        // берём РЕЗУЛЬТАТ sanitizeOCR (а не оригинал строки), иначе шум-токены просочатся
        // в промпт. sanitizeOCR внутри зовёт sanitize -> инъекция нейтрализована построчно.
        let usable: [OCRLine] = lines.compactMap { l in
            let t = l.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard t.count >= 2, l.confidence >= 0.4 else { return nil }   // фильтр низко-confidence
            let n = normalizeForEcho(t)
            // Эхо: строка - кусок собственного текста поля (OCR прочитал то, что юзер сам набрал).
            if n.count >= 4, !fieldNorm.isEmpty, fieldNorm.contains(n) { return nil }
            let cleaned = PromptContextSanitizer.sanitizeOCR(t)
            guard !cleaned.isEmpty else { return nil }
            return OCRLine(text: cleaned, confidence: l.confidence, boundingBoxPx: l.boundingBoxPx)
        }
        let ranked: [OCRLine]
        if let caret = caretPx {
            ranked = usable.sorted { score($0, caret: caret) < score($1, caret: caret) }
        } else {
            ranked = usable.sorted { $0.boundingBoxPx.minY < $1.boundingBoxPx.minY }
        }
        var taken: [OCRLine] = []
        var count = 0
        for l in ranked {
            if count + l.text.count + 1 > maxChars { break }   // текст уже очищен/обрезан
            taken.append(l); count += l.text.count + 1
        }
        return taken.sorted { $0.boundingBoxPx.minY < $1.boundingBoxPx.minY }
            .map { $0.text }
            .joined(separator: " ")
    }

    private static func score(_ l: OCRLine, caret: CGPoint) -> CGFloat {
        let r = l.boundingBoxPx
        let cx = max(r.minX, min(caret.x, r.maxX))
        let cy = max(r.minY, min(caret.y, r.maxY))
        let dx = caret.x - cx, dy = caret.y - cy
        var d = dx * dx + dy * dy
        if r.minY > caret.y { d *= 3 }   // строка НИЖЕ каретки - менее ценна (контекст обычно сверху)
        return d
    }

    /// Нормализация для сравнения эха: нижний регистр без пробелов (устойчиво к мелким различиям).
    private static func normalizeForEcho(_ s: String) -> String {
        s.lowercased().filter { !$0.isWhitespace }
    }
}
