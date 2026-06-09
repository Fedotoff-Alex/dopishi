import AppKit

/// Безрамочное прозрачное окно с серым "призрачным" текстом, позиционируемое у каретки.
@MainActor
final class GhostOverlay {
    private let window: NSPanel
    private let label: NSTextField

    init() {
        label = NSTextField(labelWithString: "")
        label.textColor = NSColor.secondaryLabelColor
        label.drawsBackground = false
        label.isBezeled = false
        label.isEditable = false
        label.font = .systemFont(ofSize: 13)

        window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 10, height: 18),
                         styleMask: [.nonactivatingPanel, .borderless],
                         backing: .buffered, defer: false)
        window.contentView = label
        window.level = .statusBar
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
    }

    /// Показать `text` у каретки. `caret` - rect каретки в координатах Cocoa (bottom-left).
    /// Окно по X справа от каретки (с зазором). По Y якорим НИЗ окна к низу каретки - текст
    /// ложится на строку каретки и НЕ зависит от размера подсказки (прежняя формула с
    /// size.height уезжала вверх при смене размера шрифта подсказки).
    func show(text: String, cocoaCaretRect caret: CGRect, font: NSFont, isCorrection: Bool = false) {
        // Не рисуем ведущие пробелы подсказки: логически они разделитель (вставка по Tab), но
        // на экране дают видимый "пробел перед текстом". Тримим любой пробельный (NBSP/таб тоже).
        let display = String(text.drop(while: { $0.isWhitespace }))
        // Исправление опечатки рисуем зелёным (сигнал «это замена слова»), дописывание - серым.
        label.textColor = isCorrection ? .systemGreen : .secondaryLabelColor
        // Перелейаут окна (sizeToFit/setContentSize) - только при смене текста/шрифта. Стрим
        // даёт обновления часто; без диффа окно дёргалось на каждый токен (мерцание).
        if label.stringValue != display || label.font != font {
            label.font = font
            label.stringValue = display
            label.sizeToFit()
            window.setContentSize(label.frame.size)
        }
        // Вертикаль для однострочной панели подсказки:
        // центрируем строку шрифта на ЦЕНТРЕ каретки (midY), а не сажаем низ окна на низ
        // каретки. Прежняя привязка низа к caret.minY уводила ghost на строку выше (текст
        // всплывает в верх cell NSTextField). Центрирование по midY кладёт baseline на строку.
        // lineHeight = ceil(pointSize*1.25) - та же константа, что у Cotabby.
        let lineHeight = ceil(font.pointSize * 1.25)
        let contentH = window.frame.height
        let originY = caret.midY - contentH + lineHeight / 2
        // X вплотную к правому краю каретки (без зазора, иначе читается как лишний пробел).
        window.setFrameOrigin(NSPoint(x: caret.maxX, y: originY))
        if !window.isVisible { window.orderFrontRegardless() }
    }

    func hide() { window.orderOut(nil) }
    var isVisible: Bool { window.isVisible }
}
