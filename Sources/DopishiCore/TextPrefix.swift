import Foundation

public enum TextPrefix {
    /// AXSelectedTextRange.location is a UTF-16 offset, not a Swift Character offset.
    /// If the offset lands inside an invalid boundary, keep the nearest valid prefix.
    public static func byUTF16Offset(_ text: String, offset: Int) -> String {
        guard offset >= 0 else { return text }
        let utf16 = text.utf16
        guard offset <= utf16.count else { return text }

        var currentOffset = offset
        while currentOffset >= 0 {
            let utf16Index = utf16.index(utf16.startIndex, offsetBy: currentOffset)
            if let stringIndex = String.Index(utf16Index, within: text) {
                return String(text[..<stringIndex])
            }
            currentOffset -= 1
        }
        return ""
    }
}
