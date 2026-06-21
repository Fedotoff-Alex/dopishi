import PackagePlugin
import Foundation

@main struct XStringsCompile: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        guard let src = target.sourceModule else { return [] }
        let outDir = context.pluginWorkDirectoryURL
        let script = context.package.directoryURL
            .appending(path: "Plugins/XStringsCompile/compile-xcstrings.sh")
        return src.sourceFiles.filter { $0.url.pathExtension == "xcstrings" }.map { file in
            let outs = ["en", "ru"].flatMap { lang in
                [outDir.appending(path: "\(lang).lproj/Localizable.strings"),
                 outDir.appending(path: "\(lang).lproj/Localizable.stringsdict")]
            }
            return .buildCommand(
                displayName: "xcstringstool compile \(file.url.lastPathComponent)",
                executable: URL(fileURLWithPath: "/bin/bash"),
                arguments: [script.path(), outDir.path(), file.url.path()],
                inputFiles: [file.url], outputFiles: outs)
        }
    }
}
