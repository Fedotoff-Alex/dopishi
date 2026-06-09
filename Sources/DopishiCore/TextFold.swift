import Foundation

/// Свёрнутое представление для сравнения "по сути": только буквы и цифры, нижний регистр.
/// Используется, чтобы ловить дубли/эхо, отличающиеся регистром и пунктуацией.
public enum TextFold {
    public static func folded(_ s: String) -> String {
        String(s.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }
}
