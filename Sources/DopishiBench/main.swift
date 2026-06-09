import Foundation
import DopishiCore
import DopishiLLM

// A/B харнесс: гоняет РЕАЛЬНЫЙ пайплайн движка (benchRun) по матрице моделей × режимов промпта
// на наборе тест-префиксов. Мерит prefill/firstToken/firstVisible/total/tok-s/avgLogprob +
// причину reject + сырьё. Не входит в продакшн-сборку приложения.
//
// Запуск:
//   swift run -c release DopishiBench
// Env:
//   DOPISHI_BENCH_MODELS="file1.gguf,file2.gguf"   (по умолчанию - все наличные кандидаты)
//   DOPISHI_BENCH_MODES="fewShot,plainTrimmed,plainRaw,minimalInline"  (по умолчанию fewShot)
//   DOPISHI_BENCH_CTX="1024"  (по умолчанию 2048)

struct TestCase { let label: String; let prefix: String }

let cases: [TestCase] = [
    .init(label: "ru_after_space", prefix: "Спасибо большое за "),
    .init(label: "ru_mid_word",    prefix: "Подскажите пожалуйста как мне поступ"),
    .init(label: "ru_prose",       prefix: "В выходные мы решили"),
    .init(label: "ru_no_assist",   prefix: "Как думаешь, стоит ли"),
    .init(label: "ru_email",       prefix: "Добрый день! Пишу вам по поводу"),
    .init(label: "ru_newline",     prefix: "Список задач:\n- купить молоко\n- "),
    .init(label: "en_after_space", prefix: "Thank you for your "),
    .init(label: "en_message",     prefix: "Hi, just wanted to let you know that"),
    .init(label: "en_technical",   prefix: "The function returns a list of"),
    .init(label: "en_mid_word",    prefix: "I would like to underst"),
]

// Все кандидаты (локальные имена). Гоняем только реально наличные на диске.
let candidateModels = [
    "gemma-4-E2B-i1-Q4_K_M.gguf",            // текущая база
    "Qwen3-4B-Instruct-2507-Q4_K_M.gguf",    // главный кандидат
    "gemma-3-4b-it-Q4_K_M.gguf",
    "Qwen3-1.7B-Q4_K_M.gguf",
    "SmolLM3-3B-Q4_K_M.gguf",
    "Ministral-3-3B-Instruct-2512-Q4_K_M.gguf",
]

func env(_ k: String) -> String? { ProcessInfo.processInfo.environment[k] }

let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
let modelsDir = appSupport.appendingPathComponent("Dopishi/Models", isDirectory: true)
func present(_ file: String) -> Bool {
    FileManager.default.fileExists(atPath: modelsDir.appendingPathComponent(file).path)
}

let requestedModels = env("DOPISHI_BENCH_MODELS")?.split(separator: ",").map(String.init) ?? candidateModels
let models = requestedModels.filter(present)

let modeNames = env("DOPISHI_BENCH_MODES")?.split(separator: ",").map(String.init) ?? ["fewShot"]
let modes: [PromptBuilder.Mode] = modeNames.compactMap { PromptBuilder.Mode(rawValue: $0) }

let ctx = env("DOPISHI_BENCH_CTX").flatMap { Int($0) } ?? 2048

// Per-model стоп-токены - единый источник с продом (DopishiCore.ModelStopTokens).
func stopTokens(for model: String) -> [String] { ModelStopTokens.tokens(for: model) }

if models.isEmpty {
    print("Нет наличных моделей в \(modelsDir.path). Доступные кандидаты ещё качаются?")
    exit(0)
}
print("Модели: \(models.joined(separator: ", "))")
print("Режимы: \(modes.map { $0.rawValue }.joined(separator: ", ")) | context=\(ctx)\n")

func fmt(_ d: Double?) -> String { d.map { String(format: "%.0f", $0) } ?? "-" }
func pad(_ s: String, _ n: Int) -> String {
    s.count >= n ? String(s.prefix(n)) : s + String(repeating: " ", count: n - s.count)
}

var allTraces: [BenchTrace] = []

for model in models {
    for mode in modes {
        var cfg = EngineConfig.production
        cfg.promptMode = mode
        cfg.contextSize = ctx
        cfg.extraEOSTokens = stopTokens(for: model)
        let engine = SuggestionEngine(fileName: model, config: cfg)

        // Прогрев: грузим модель + KV статического префикса (имитация старта).
        _ = try? await engine.benchRun(prefix: "Привет, как ", label: "warmup")

        print("═══ \(model)  [\(mode.rawValue)] ═══")
        print(pad("prefix", 15) + pad("reject", 9) + pad("suggestion", 30)
              + pad("prefill", 8) + pad("firstVis", 9) + pad("total", 7) + pad("tok/s", 7) + "avgLP")
        var accepted = 0
        var visTimes: [Double] = []
        var totals: [Double] = []
        for tc in cases {
            do {
                let t = try await engine.benchRun(prefix: tc.prefix, label: tc.label)
                allTraces.append(t)
                if t.rejection == .none { accepted += 1 }
                if let v = t.firstVisibleMs { visTimes.append(v) }
                totals.append(t.totalMs)
                let sug = t.suggestion.replacingOccurrences(of: "\n", with: "⏎")
                print(pad(tc.label, 15) + pad(t.rejection.rawValue, 9) + pad(sug, 30)
                      + pad(fmt(t.prefillMs), 8) + pad(fmt(t.firstVisibleMs), 9)
                      + pad(fmt(t.totalMs), 7) + pad(String(format: "%.0f", t.tokensPerSec), 7)
                      + String(format: "%.2f", t.avgLogprob))
            } catch {
                print(pad(tc.label, 15) + "ERROR: \(error)")
            }
        }
        func median(_ a: [Double]) -> Double { a.isEmpty ? 0 : a.sorted()[a.count/2] }
        print(String(format: "  -> принято %d/%d | медиана firstVisible %.0fms | медиана total %.0fms\n",
                     accepted, cases.count, median(visTimes), median(totals)))
    }
}

// JSON-выгрузка всех трасс для последующего анализа.
let outURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("bench-results.json")
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
if let data = try? encoder.encode(allTraces) {
    try? data.write(to: outURL)
    print("JSON: \(outURL.path) (\(allTraces.count) трасс)")
}
print("Бенч завершён.")
