import Foundation
import DopishiCore

/// Качает gguf пресета в каталог моделей через URLSessionDownloadDelegate.
/// onProgress (0...1) вызывается на служебной очереди сессии - UI оборачивать в MainActor на стороне вызывающего.
/// Один экземпляр = одна загрузка.
///
/// @unchecked Sendable обоснование: изменяемые поля (onProgress/continuation/destination)
/// пишутся в download() ДО resume(); resume() пересекает границу очереди (барьер памяти),
/// поэтому запись happens-before любого делегатного колбэка, а delegateQueue: nil даёт
/// сериализованную очередь - колбэки не конкурируют друг с другом. Гонки нет.
public final class ModelDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    public enum DownloadError: Error { case badResponse(Int), missingDestination, insufficientSpace(needed: Int64, available: Int64) }

    private var onProgress: (@Sendable (Double) -> Void)?
    private var continuation: CheckedContinuation<URL, Error>?
    private var destination: URL?

    public override init() { super.init() }

    public func download(_ preset: ModelPreset,
                         onProgress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let dir = ModelLocator.defaultModelsDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Self.ensureFreeSpace(for: preset, at: dir)   // не начинаем загрузку, если места не хватит
        // Состояние выставляем ДО resume(): делегат не вызовется раньше.
        self.destination = ModelLocator.url(forFile: preset.fileName)
        self.onProgress = onProgress
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        return try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            session.downloadTask(with: preset.downloadURL).resume()
        }
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
                           didFinishDownloadingTo location: URL) {
        // Файл из location валиден ТОЛЬКО синхронно внутри этого колбэка - переносим сразу.
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
            // «моделью» (иначе ошибка всплыла бы позже при инициализации LLM). location валиден
            // только синхронно здесь, поэтому проверяем и переносим сразу.
            try ModelFileValidator.validate(fileAt: location)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            onProgress?(1.0)
            continuation?.resume(returning: destination)
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
        // Ошибка сети/транспорта (didFinishDownloadingTo не вызовется). При успехе error == nil.
        guard let error else { return }
        continuation?.resume(throwing: error)
        continuation = nil
        session.finishTasksAndInvalidate()
    }
}
