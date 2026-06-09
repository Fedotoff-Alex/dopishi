import Foundation

public struct KeystrokeBuffer: Sendable, Equatable {
    public let text: String
    public let maxLength: Int

    public init(maxLength: Int = 512) {
        self.text = ""
        self.maxLength = maxLength
    }

    private init(text: String, maxLength: Int) {
        self.text = text
        self.maxLength = maxLength
    }

    public func appending(_ s: String) -> KeystrokeBuffer {
        var next = text + s
        if next.count > maxLength {
            next = String(next.suffix(maxLength))
        }
        return KeystrokeBuffer(text: next, maxLength: maxLength)
    }

    public func backspacing() -> KeystrokeBuffer {
        guard !text.isEmpty else { return self }
        return KeystrokeBuffer(text: String(text.dropLast()), maxLength: maxLength)
    }

    public func reset() -> KeystrokeBuffer {
        KeystrokeBuffer(text: "", maxLength: maxLength)
    }
}
