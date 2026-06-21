import Foundation

public enum KeyboardLayout {
    // Физические клавиши: латиница (QWERTY) -> кириллица (ЙЦУКЕН), нижний регистр.
    private static let enToRu: [Character: Character] = [
        "q":"й","w":"ц","e":"у","r":"к","t":"е","y":"н","u":"г","i":"ш","o":"щ","p":"з","[":"х","]":"ъ",
        "a":"ф","s":"ы","d":"в","f":"а","g":"п","h":"р","j":"о","k":"л","l":"д",";":"ж","'":"э",
        "z":"я","x":"ч","c":"с","v":"м","b":"и","n":"т","m":"ь",",":"б",".":"ю","/":".",
        // Шифтовая пунктуация и ё: shifted-символы не "uppercase" и через isUppercase-ветку
        // не проходят - нужны явные пары. Без них "?"(RU-запятая) и "ghbdtn?" оставались
        // как есть после конверсии (репорт: "запятые и точки остаются").
        "`":"ё","~":"Ё","?":",","<":"Б",">":"Ю","{":"Х","}":"Ъ",":":"Ж","\"":"Э"
    ]
    private static let ruToEn: [Character: Character] = {
        var m: [Character: Character] = [:]
        for (e, r) in enToRu { m[r] = e }
        return m
    }()

    public static func enToRussian(_ s: String) -> String { translate(s, using: enToRu) }
    public static func ruToEnglish(_ s: String) -> String { translate(s, using: ruToEn) }

    /// Конвертация ГРАНИЧНОГО символа (разделитель после слова) при свитче раскладки.
    /// Отдельно от enToRussian/ruToEnglish, потому что граница - это ПУНКТУАЦИЯ, а не буква:
    ///  - "," и "." пользователь набирает теми же клавишами в любой раскладке КАК ПУНКТУАЦИЮ,
    ///    их НЕ трогаем. (enToRussian мапил бы их в буквы ЙЦУКЕН ","->"б", "."->"ю", давая
    ///    "приветб"/"приветю" вместо "привет,"/"привет." - баг, который это и чинит.)
    ///  - Позиции пунктуации ЙЦУКЕН реально отличаются и конвертятся: при свитче в ru
    ///    "/"->"." (точка) и "?"->"," (запятая) - именно на этих клавишах они в ЙЦУКЕН.
    /// Прочие символы (пробел/таб/перенос и т.п.) - как есть.
    public static func boundaryForSwitch(_ b: String, to lang: String) -> String {
        guard b.count == 1, let ch = b.first else { return b }
        if ch == "," || ch == "." { return b }           // пунктуация одинакова - не трогаем
        if lang == "ru" {                                 // позиции пунктуации ЙЦУКЕН
            if ch == "/" { return "." }
            if ch == "?" { return "," }
        }
        return b
    }

    /// Число, набранное в RU-раскладке: разделители "." и "," выходят буквами "ю"/"б"
    /// (они на клавишах ./, в ЙЦУКЕН). "2ю1" - это "2.1", "10б5" - "10,5", "1ю2ю3" - "1.2.3".
    /// Возвращает исправленную строку, если токен - цифры с ВНУТРЕННИМИ разделителями ю/б,
    /// иначе nil. Узко и безопасно: у такого токена нет осмысленной русской трактовки, так что
    /// конвертим безусловно (мимо словарных гейтов авто-свитча). 0 false-positive.
    public static func fixNumericSeparators(_ token: String) -> String? {
        let chars = Array(token)
        guard chars.count >= 3, chars.first!.isNumber, chars.last!.isNumber else { return nil }
        var hasSep = false
        for ch in chars {
            if ch.isNumber { continue }
            if ch == "ю" || ch == "б" { hasSep = true; continue }
            return nil                              // любой иной символ - не наш случай
        }
        guard hasSep else { return nil }
        return String(chars.map { $0 == "ю" ? "." : ($0 == "б" ? "," : $0) })
    }

    private static func translate(_ s: String, using table: [Character: Character]) -> String {
        String(s.map { ch in
            guard let lower = ch.lowercased().first, let mapped = table[lower] else { return ch }
            return ch.isUppercase ? Character(mapped.uppercased()) : mapped
        })
    }
}
