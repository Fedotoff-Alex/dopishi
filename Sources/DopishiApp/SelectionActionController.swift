import AppKit
import DopishiCore

/// Действия над выделенным текстом (UX-03): хоткей подсказки при наличии выделения открывает
/// меню (исправить/переписать/...), результат показывается в превью-панели у каретки,
/// Tab - заменить выделение, Esc - отмена. Откат замены - штатный Cmd+Z приложения
/// (замена идёт обычной вставкой через буфер обмена).
@MainActor
final class SelectionActionController {
    /// Трансформация текста локальной моделью (инжектится из SuggestionController - движок там).
    var transform: ((String, SelectionAction) async -> String?)?
    /// Включение/выключение перехвата Tab/Esc (probe.setSuggestionActive).
    var onActiveChanged: ((Bool) -> Void)?

    /// Панель превью видима - Tab/Esc маршрутизируются сюда, а не в подсказки.
    private(set) var isActive = false

    private let panel: NSPanel
    private let resultLabel: NSTextField
    private let hintLabel: NSTextField

    private var originalSelection: String?
    private var pendingResult: String?
    private var generationTask: Task<Void, Never>?

    init() {
        resultLabel = NSTextField(wrappingLabelWithString: "")
        resultLabel.font = .systemFont(ofSize: 13)
        resultLabel.textColor = .labelColor
        resultLabel.preferredMaxLayoutWidth = 440

        hintLabel = NSTextField(labelWithString: "Tab - заменить · Esc - отмена")
        hintLabel.font = .systemFont(ofSize: 10)
        hintLabel.textColor = .tertiaryLabelColor

        let stack = NSStackView(views: [resultLabel, hintLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 8, right: 12)

        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 8
        effect.layer?.masksToBounds = true
        effect.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            stack.topAnchor.constraint(equalTo: effect.topAnchor),
            stack.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])

        // Неактивирующая панель: клики/показ не уводят фокус из целевого приложения -
        // иначе вставка по Tab улетела бы в нас, а не в документ (паттерн GhostOverlay).
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 60),
                        styleMask: [.nonactivatingPanel, .borderless],
                        backing: .buffered, defer: false)
        panel.contentView = effect
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true   // взаимодействие только Tab/Esc через CGEventTap
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
    }

    /// Точка входа: хоткей подсказки при непустом выделении. Показывает меню действий
    /// у каретки/выделения; выбор запускает генерацию и превью.
    func present(ctx: EditingContext) {
        guard let selection = ctx.selectedText, !selection.isEmpty else { return }
        dismiss()   // прежнее превью, если было

        let menu = NSMenu()
        for action in SelectionAction.allCases {
            let item = NSMenuItem(title: action.menuTitle, action: #selector(menuPicked(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = MenuPayload(action: action, selection: selection, ctx: ctx)
            menu.addItem(item)
        }
        let at = anchorPoint(for: ctx)
        menu.popUp(positioning: nil, at: at, in: nil)
    }

    private final class MenuPayload: NSObject {
        let action: SelectionAction
        let selection: String
        let ctx: EditingContext
        init(action: SelectionAction, selection: String, ctx: EditingContext) {
            self.action = action
            self.selection = selection
            self.ctx = ctx
        }
    }

    @objc private func menuPicked(_ item: NSMenuItem) {
        guard let payload = item.representedObject as? MenuPayload else { return }
        originalSelection = payload.selection
        pendingResult = nil
        show(text: "Генерирую (\(payload.action.menuTitle.lowercased()))…", ctx: payload.ctx, pending: true)
        let action = payload.action
        let selection = payload.selection
        generationTask?.cancel()
        generationTask = Task { [weak self] in
            let result = await self?.transform?(selection, action)
            guard let self, !Task.isCancelled else { return }
            guard self.isActive else { return }   // юзер успел отменить Esc-ом
            if let result, !result.isEmpty, result != selection {
                self.pendingResult = result
                self.show(text: result, ctx: payload.ctx, pending: false)
            } else {
                self.show(text: "Не получилось - попробуй ещё раз", ctx: payload.ctx, pending: true)
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(2))
                    if self?.pendingResult == nil { self?.dismiss() }
                }
            }
        }
    }

    /// Tab: заменить выделение результатом. Перед заменой - AX re-verify: выделение в поле
    /// всё ещё ровно то, для которого генерировали (защита от stale selection).
    func acceptReplace() {
        guard let result = pendingResult, let original = originalSelection else { dismiss(); return }
        let fresh = AccessibilityReader.read().selectedText
        guard fresh == original else {
            show(text: "Выделение изменилось - замена отменена", ctx: nil, pending: true)
            pendingResult = nil
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(2))
                self?.dismiss()
            }
            return
        }
        Injector.replaceSelection(with: result)
        dismiss()
    }

    /// Esc или потеря фокуса: убрать превью, отменить генерацию.
    func dismiss() {
        generationTask?.cancel()
        generationTask = nil
        originalSelection = nil
        pendingResult = nil
        if panel.isVisible { panel.orderOut(nil) }
        if isActive {
            isActive = false
            onActiveChanged?(false)
        }
    }

    // MARK: - панель

    private func show(text: String, ctx: EditingContext?, pending: Bool) {
        resultLabel.stringValue = text
        resultLabel.textColor = pending ? .secondaryLabelColor : .labelColor
        hintLabel.isHidden = pending
        panel.contentView?.layoutSubtreeIfNeeded()
        let size = panel.contentView?.fittingSize ?? NSSize(width: 240, height: 60)
        panel.setContentSize(size)
        if let ctx { position(under: anchorPoint(for: ctx), size: size) }
        if !panel.isVisible { panel.orderFrontRegardless() }
        if !isActive {
            isActive = true
            onActiveChanged?(true)
        }
    }

    /// Точка привязки меню/панели: каретка (cocoa-координаты) или курсор мыши как фолбэк.
    private func anchorPoint(for ctx: EditingContext) -> NSPoint {
        if let rect = ctx.caretScreenRect {
            let cocoa = DisplayCoordinateConverter.cocoaRect(fromAXRect: rect)
            return NSPoint(x: cocoa.minX, y: cocoa.minY - 4)
        }
        return NSEvent.mouseLocation
    }

    private func position(under point: NSPoint, size: NSSize) {
        var origin = NSPoint(x: point.x, y: point.y - size.height - 6)
        if let screen = NSScreen.screens.first(where: { NSPointInRect(point, $0.frame) }) ?? NSScreen.main {
            let f = screen.visibleFrame
            origin.x = min(max(origin.x, f.minX + 8), f.maxX - size.width - 8)
            origin.y = max(origin.y, f.minY + 8)
        }
        panel.setFrameOrigin(origin)
    }
}
