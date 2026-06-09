import AppKit

@MainActor
final class DebugHUD {
    private let window: NSWindow
    private let label: NSTextField

    init() {
        label = NSTextField(labelWithString: "HUD...")
        label.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        label.textColor = .white
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 150))
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.78).cgColor
        label.frame = content.bounds.insetBy(dx: 10, dy: 10)
        label.autoresizingMask = [.width, .height]
        content.addSubview(label)

        window = NSPanel(contentRect: content.frame,
                         styleMask: [.nonactivatingPanel, .borderless],
                         backing: .buffered, defer: false)
        window.contentView = content
        window.level = .statusBar
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.setFrameTopLeftPoint(NSPoint(x: 40, y: (NSScreen.main?.frame.height ?? 800) - 60))
    }

    func show() { window.orderFrontRegardless() }
    func hide() { window.orderOut(nil) }
    var isVisible: Bool { window.isVisible }

    func update(_ text: String) {
        label.stringValue = text
    }
}
