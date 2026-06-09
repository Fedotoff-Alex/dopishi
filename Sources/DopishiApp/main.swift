import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// Фоновый агент: без иконки в Dock, без главного окна
app.setActivationPolicy(.accessory)
app.run()
