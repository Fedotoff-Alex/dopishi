import Foundation
import DopishiCore

/// Качает gguf пресета в каталог моделей через URLSessionDownloadDelegate.
/// onProgress (0...1) вызывается на служебной очереди сессии - UI оборачивать в MainActor на стороне вызывающего.
/// Один экземпляр = одна загрузка.
///
/// UX-04: cancel() сохраняет resumeData рядом с целью (<file>.resume) - следующий download()
/// того же пресета продолжает с того же места (HF поддерживает Range). После скачивания файл
/// проходит GGUF-валидацию и sha256-сверку с lfs.oid из HF tree API (если API доступен).
///
/// @unchecked Sendable обоснование: изменяемые поля (onProgress/continuation/destination/task)
/// пишутся в download() ДО resume(); resume() пересекает границу очереди (барьер памяти),
/// поэтому запись happens-before любого делегатного колбэка, а delegateQueue: nil даёт
/// сериализованную очередь - колбэки не конкурируют друг с другом. cancel() трогает только
/// task (выставлен до resume) и пишет .resume-файл из колбэка cancel - гонки нет.
public final class ModelDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    public enum DownloadError: Error {
        case badResponse(Int)
        case missingDestination
        case insufficientSpace(needed: Int64, available: Int64)
        /// sha256 скачанного не совпал с эталоном HF (битый/подменённый файл удалён).
        case checksumMismatch(expected: String, actual: String)
    }

    private var onProgress: (@Sendable (Double) -> Void)?
    private var continuation: CheckedContinuation<URL, Error>?
    private var destination: URL?
    private var task: URLSessionDownloadTask?

    public override init() { super.init() }

    public func download(_ preset: ModelPreset,
                         onProgress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let dir = ModelLocator.defaultModelsDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Self.ensureFreeSpace(for: preset, at: dir)   // не начинаем загрузку, если места не хватит
        let dest = ModelLocator.url(forFile: preset.fileName)
        // Состояние выставляем ДО resume(): делегат не вызовется раньше.
        self.destination = dest
        self.onProgress = onProgress
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        // Эталонный sha256 - ДО загрузки (после неё сети может уже не быть). nil = HF API
        // недоступен/файл не LFS - верификацию пропускаем (загрузку не валим из-за метаданных).
        let expectedSHA = await Self.fetchExpectedSHA256(preset)
        let staged: URL = try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            let resumeFile = Self.resumeDataURL(for: dest)
            let t: URLSessionDownloadTask
            if let data = try? Data(contentsOf: resumeFile) {
                try? FileManager.default.removeItem(at: resumeFile)
                t = session.downloadTask(withResumeData: data)   // продолжаем с места отмены
            } else {
                t = session.downloadTask(with: preset.downloadURL)
            }
            self.task = t
            t.resume()
        }
        // sha256 - вне делегата (хэш 5 ГБ занимает секунды; location-файл уже у нас в staging).
        // Detached: не занимаем cooperative pool блокирующим чтением диска.
        if let expectedSHA {
            let actual = try await Task.detached(priority: .userInitiated) {
                try ModelChecksum.sha256Hex(of: staged)
            }.value
            guard actual == expectedSHA else {
                try? FileManager.default.removeItem(at: staged)
                throw DownloadError.checksumMismatch(expected: expectedSHA, actual: actual)
            }
        }
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: staged, to: dest)
        return dest
    }

    /// Отменить текущую загрузку с сохранением resumeData (<file>.resume): следующий
    /// download() того же пресета продолжит с этого места. Вызывающий получает
    /// URLError(.cancelled) из download().
    public func cancel() {
        let dest = destination
        task?.cancel { data in
            guard let data, let dest else { return }
            try? data.write(to: Self.resumeDataURL(for: dest))
        }
    }

    /// Файл resumeData рядом с целью загрузки.
    static func resumeDataURL(for destination: URL) -> URL {
        URL(fileURLWithPath: destination.path + ".resume")
    }

    /// Промежуточный файл до sha256-проверки (та же папка - move атомарный).
    static func stagingURL(for destination: URL) -> URL {
        URL(fileURLWithPath: destination.path + ".staging")
    }

    /// Эталонный sha256 из HF tree API (lfs.oid). nil - API недоступен / не LFS.
    static func fetchExpectedSHA256(_ preset: ModelPreset) async -> String? {
        guard let url = URL(string: "https://huggingface.co/api/models/\(preset.repo)/tree/main")
        else { return nil }
        guard let (data, resp) = try? await URLSession.shared.data(from: url),
              let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode)
        else { return nil }
        return ModelChecksum.expectedSHA256(treeJSON: data, remoteFileName: preset.remoteFileName)
    }

    // MARK: URLSessionDownloadDelegate (вызовы сериализованы служебной очередью сессии)

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                           didWriteData bytesWritten: Int64,
                           totalBytesWritten: Int64,
                           totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress?(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                           didResumeAtOffset fileOffset: Int64, expectedTotalBytes: Int64) {
        guard expectedTotalBytes > 0 else { return }
        onProgress?(Double(fileOffset) / Double(expectedTotalBytes))
    }

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                           didFinishDownloadingTo location: URL) {
        // Файл из location валиден ТОЛЬКО синхронно внутри этого колбэка - переносим сразу
        // в staging (sha256-проверка идёт уже в download(), вне делегата).
        defer { continuation = nil; session.finishTasksAndInvalidate() }
        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            continuation?.resume(throwing: DownloadError.badResponse(http.statusCode)); return
        }
        guard let destination else {
            // Инвариант: destination ставится в download() до resume(). Резолвим, чтобы не подвесить вызывающего навсегда.
            continuation?.resume(throwing: DownloadError.missingDestination); return
        }
        do {
            // Целостность ДО перемещения: GGUF-магия + размер. Битый HTML/частичный файл не станет
            // «моделью» (иначе ошибка всплыла бы позже при инициализации LLM).
            try ModelFileValidator.validate(fileAt: location)
            let staging = Self.stagingURL(for: destination)
            try? FileManager.default.removeItem(at: staging)
            try FileManager.default.moveItem(at: location, to: staging)
            onProgress?(1.0)
            continuation?.resume(returning: staging)
        } catch {
            continuation?.resume(throwing: error)
        }
    }

    /// Свободного места нужно ~120% от размера модели. Если узнать не удалось - не блокируем.
    private static func ensureFreeSpace(for preset: ModelPreset, at dir: URL) throws {
        let needed = Int(preset.approxSizeGB * 1.2 * 1_073_741_824)
        guard let vals = try? dir.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let available = vals.volumeAvailableCapacityForImportantUsage else { return }
        if available < needed {
            throw DownloadError.insufficientSpace(needed: Int64(needed), available: Int64(available))
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask,
                           didCompleteWithError error: Error?) {
        // Ошибка сети/транспорта или отмена (didFinishDownloadingTo не вызовется).
        // При cancel(byProducingResumeData:) сюда приходит URLError(.cancelled) - resumeData
        // уже сохранена колбэком cancel(). При успехе error == nil.
        guard let error else { return }
        continuation?.resume(throwing: error)
        continuation = nil
        session.finishTasksAndInvalidate()
    }
}
