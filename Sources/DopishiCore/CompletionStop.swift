import Foundation

public enum CompletionStop {
    public struct Result: Equatable {
        public let shouldStop: Bool
        public let trimmed: String
    }

    public static func evaluate(_ accumulated: String, maxWords: Int = 12) -> Result {
        if let nl = accumulated.firstIndex(of: "\n") {
            return Result(shouldStop: true, trimmed: String(accumulated[..<nl]))
        }
        let enders: Set<Character> = [".", "!", "?"]
        if let endIdx = accumulated.firstIndex(where: { enders.contains($0) }) {
            let upto = accumulated.index(after: endIdx)
            return Result(shouldStop: true, trimmed: String(accumulated[..<upto]))
        }
        let leading = accumulated.prefix(while: { $0 == " " })
        let words = accumulated.split(separator: " ", omittingEmptySubsequences: true)
        if words.count > maxWords {
            let kept = words.prefix(maxWords).joined(separator: " ")
            return Result(shouldStop: true, trimmed: String(leading) + kept)
        }
        return Result(shouldStop: false, trimmed: accumulated)
    }
}
