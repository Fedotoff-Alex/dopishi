import Foundation

public enum WordAccept {
    /// Первый "кусок" подсказки для пословной вставки по Tab:
    /// ведущие пробелы + одно слово + один пробел-разделитель после него (если есть).
    public static func firstChunk(of s: String) -> String {
        let chars = Array(s)
        var i = 0
        while i < chars.count, chars[i] == " " { i += 1 }   // ведущие пробелы
        while i < chars.count, chars[i] != " " { i += 1 }   // само слово
        if i < chars.count, chars[i] == " " { i += 1 }       // один разделитель после слова
        return String(chars[0..<i])
    }
}
