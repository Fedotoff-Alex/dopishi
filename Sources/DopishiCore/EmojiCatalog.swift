import Foundation

/// Каталог эмодзи по короткому имени (shortcode). Триггер - набор ":name" в тексте; по точному
/// имени или префиксу предлагаем эмодзи (как :smile: в Slack/GitHub). Курированный набор частых.
public enum EmojiCatalog {
    /// shortcode (нижний регистр, без двоеточий) -> emoji.
    static let map: [String: String] = [
        "smile": "😄", "smiley": "😀", "grin": "😁", "joy": "😂", "lol": "😂", "rofl": "🤣",
        "sweat_smile": "😅", "wink": "😉", "blush": "😊", "happy": "😊", "heart_eyes": "😍",
        "kissing_heart": "😘", "thinking": "🤔", "neutral": "😐", "unamused": "😒", "cry": "😢",
        "sad": "😢", "sob": "😭", "angry": "😠", "rage": "😡", "sunglasses": "😎", "cool": "😎",
        "fearful": "😨", "scream": "😱", "sleeping": "😴", "mask": "😷", "nerd": "🤓",
        "smirk": "😏", "shrug": "🤷", "facepalm": "🤦", "hug": "🤗",
        "heart": "❤️", "love": "❤️", "broken_heart": "💔", "sparkling_heart": "💖",
        "blue_heart": "💙", "green_heart": "💚", "yellow_heart": "💛", "purple_heart": "💜",
        "thumbsup": "👍", "thumbup": "👍", "thumbsdown": "👎", "ok_hand": "👌", "ok": "👌",
        "wave": "👋", "hi": "👋", "bye": "👋", "clap": "👏", "pray": "🙏", "thanks": "🙏",
        "muscle": "💪", "point_up": "☝️", "raised_hands": "🙌", "fingers_crossed": "🤞",
        "fist": "✊", "victory": "✌️", "handshake": "🤝",
        "fire": "🔥", "star": "⭐", "sparkles": "✨", "boom": "💥", "tada": "🎉",
        "party": "🥳", "gift": "🎁", "balloon": "🎈", "rocket": "🚀", "hundred": "💯",
        "check": "✅", "yes": "✅", "cross": "❌", "no": "❌", "warning": "⚠️",
        "question": "❓", "exclamation": "❗", "bulb": "💡", "idea": "💡", "eyes": "👀",
        "zzz": "💤", "poop": "💩", "ghost": "👻", "robot": "🤖", "skull": "💀",
        "sun": "☀️", "cloud": "☁️", "rain": "🌧️", "snowflake": "❄️", "moon": "🌙",
        "coffee": "☕", "tea": "🍵", "beer": "🍺", "wine": "🍷", "pizza": "🍕", "cake": "🍰",
        "apple": "🍎", "dog": "🐶", "cat": "🐱", "money": "💰", "clock": "🕐", "calendar": "📅",
        "phone": "📱", "mail": "📧", "pin": "📌", "link": "🔗", "lock": "🔒", "key": "🔑"
    ]

    /// По имени (текст после ":") вернуть эмодзи: точное совпадение в приоритете, иначе по
    /// префиксу (детерминированно: кратчайшее имя, затем лексикографически). nil если нет.
    /// Требуем имя >=2 символов, чтобы ":a" не триггерило.
    public static func match(name: String) -> String? {
        let n = name.lowercased()
        guard n.count >= 2 else { return nil }
        if let exact = map[n] { return exact }
        guard let best = map.keys.filter({ $0.hasPrefix(n) })
            .min(by: { ($0.count, $0) < ($1.count, $1) }) else { return nil }
        return map[best]
    }
}
