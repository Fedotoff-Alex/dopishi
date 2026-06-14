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

    private static func translate(_ s: String, using table: [Character: Character]) -> String {
        String(s.map { ch in
            guard let lower = ch.lowercased().first, let mapped = table[lower] else { return ch }
            return ch.isUppercase ? Character(mapped.uppercased()) : mapped
        })
    }
}
