import Foundation

/// Проверка целостности скачанного gguf ДО того, как принять его как рабочую модель.
/// Ловит частичные загрузки и подменённые ответы (HTML-страница ошибки / прокси-заглушка):
/// у валидного gguf первые 4 байта - магия "GGUF", и он не бывает меньше ~1 МБ (реально сотни МБ).
public enum ModelFileValidator {
    public enum ValidationError: Error, Equatable {
        case tooSmall(Int64)   // байт меньше минимума - почти наверняка не модель (HTML/обрыв)
        case notGGUF           // нет магии GGUF в начале файла
    }

    /// Минимальный правдоподобный размер gguf. Меньше = ошибка (страница ошибки/частичный файл).
    public static let minBytes: Int64 = 1_000_000

    /// Магия gguf: ASCII "GGUF".
    static let magic = Data([0x47, 0x47, 0x55, 0x46])

    public static func validate(fileAt url: URL, minBytes: Int64 = ModelFileValidator.minBytes) throws {
        let size = fileSize(url)
        guard size >= minBytes else { throw ValidationError.tooSmall(size) }
        guard hasGGUFMagic(url) else { throw ValidationError.notGGUF }
    }

    static func fileSize(_ url: URL) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
    }

    static func hasGGUFMagic(_ url: URL) -> Bool {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? fh.close() }
        let head = (try? fh.read(upToCount: magic.count)) ?? Data()
        return head == magic
    }
}
