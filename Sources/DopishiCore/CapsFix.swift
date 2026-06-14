import Foundation

/// Исправление «забытого CapsLock» (Punto-стиль): набрано "пРИВЕТ" (Shift на первой букве
/// при включённом капсе) - чиним на "Привет". Слово ЦЕЛИКОМ в верхнем регистре не трогаем:
/// это аббревиатуры (СССР, GGUF) или намеренный капс.
public enum CapsFix {
    /// Исправленное слово или nil, если паттерн не совпал.
    /// Паттерн: первая буква строчная, все остальные БУКВЫ - прописные (не-буквы игнорируются),
    /// и хотя бы одна прописная есть. Минимум 3 символа (короткие - слишком шумно).
    public static func fix(_ word: String) -> String? {
        guard word.count >= 3 else { return nil }
        let chars = Array(word)
        guard let first = chars.first, first.isLowercase else { return nil }
        let rest = chars.dropFirst()
        let restLetters = rest.filter { $0.isLetter }
        guard !restLetters.isEmpty, restLetters.allSatisfy({ $0.isUppercase }) else { return nil }
        return first.uppercased() + String(rest).lowercased()
    }
}
