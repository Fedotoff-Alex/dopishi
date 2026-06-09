import Foundation

public enum ModelLocator {
    public static let modelsSubdir = "Dopishi/Models"

    public static func modelsDirectory(baseDirectory: URL) -> URL {
        baseDirectory.appendingPathComponent(modelsSubdir, isDirectory: true)
    }

    public static func defaultModelsDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return modelsDirectory(baseDirectory: appSupport)
    }

    /// URL конкретного gguf в каталоге моделей.
    public static func url(forFile fileName: String) -> URL {
        defaultModelsDirectory().appendingPathComponent(fileName, isDirectory: false)
    }

    public static func isPresent(fileName: String) -> Bool {
        FileManager.default.fileExists(atPath: url(forFile: fileName).path)
    }
}
