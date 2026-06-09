import AppKit

// Рисует иконку Dopishi (буква Д на фиолетово-синем градиенте, скруглённый квадрат) в PNG.
// Использование: swift scripts/generate-icon.swift <output.png>
let size = 1024.0
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let rect = NSRect(x: 0, y: 0, width: size, height: size)
let path = NSBezierPath(roundedRect: rect, xRadius: size * 0.22, yRadius: size * 0.22)
path.addClip()
let gradient = NSGradient(
    starting: NSColor(calibratedRed: 0.36, green: 0.42, blue: 0.95, alpha: 1),
    ending: NSColor(calibratedRed: 0.55, green: 0.30, blue: 0.90, alpha: 1))!
gradient.draw(in: rect, angle: -90)
let para = NSMutableParagraphStyle()
para.alignment = .center
let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: size * 0.56, weight: .bold),
    .foregroundColor: NSColor.white,
    .paragraphStyle: para
]
let letter = "Д" as NSString
let textSize = letter.size(withAttributes: attrs)
let textRect = NSRect(x: 0, y: (size - textSize.height) / 2.0, width: size, height: textSize.height)
letter.draw(in: textRect, withAttributes: attrs)
image.unlockFocus()
guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("не удалось сделать PNG")
}
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/dopishi-1024.png"
try! png.write(to: URL(fileURLWithPath: out))
print("icon written: \(out)")
