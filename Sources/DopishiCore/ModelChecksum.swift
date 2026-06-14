import Foundation
import CryptoKit

/// SHA256-верификация скачанных моделей (UX-04). Эталонный хэш берётся из HuggingFace
/// API (lfs.oid в дереве репозитория) - хэши не хардкодятся в каталоге и не протухают
/// при обновлении файлов в репо.
public enum ModelChecksum {
    /// SHA256 файла потоково (чанки 4 МБ - не грузим 5-ГБ модель в память). Hex lowercase.
    public static func sha256Hex(of url: URL) throws -> String {
        let fh = try FileHandle(forReadingFrom: url)
        defer { try? fh.close() }
        var hasher = SHA256()
        while true {
            guard let chunk = try fh.read(upToCount: 4 * 1024 * 1024), !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Достать эталонный sha256 файла из JSON-ответа HF tree API
    /// (GET /api/models/{repo}/tree/main): [{path, lfs: {oid}}], lfs.oid = sha256.
    /// nil - файла нет в дереве / не LFS / JSON не разобрался (верификацию пропускаем).
    public static func expectedSHA256(treeJSON: Data, remoteFileName: String) -> String? {
        guard let entries = try? JSONDecoder().decode([TreeEntry].self, from: treeJSON) else { return nil }
        return entries.first { $0.path == remoteFileName }?.lfs?.oid.lowercased()
    }

    private struct TreeEntry: Decodable {
        let path: String
        let lfs: LFS?
        struct LFS: Decodable { let oid: String }
    }
}
