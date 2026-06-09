import Foundation

/// Per-model стоп-токены поверх базового "\n". Разные семейства закрывают ход своими
/// control-токенами; без них модель в .plain может не остановиться корректно. Аудит выявил
/// разрыв: в проде стоп всегда был ["\n"], и Gemma не получала <end_of_turn>, Qwen - <|im_end|>.
/// Единый источник истины для прод-движка И бенча (раньше логика жила только в DopishiBench).
public enum ModelStopTokens {
    public static func tokens(for fileName: String) -> [String] {
        let m = fileName.lowercased()
        var s = ["\n"]
        // ChatML-семейства (Qwen, Ministral-Tekken, SmolLM) закрывают ход <|im_end|>.
        if m.contains("qwen") || m.contains("ministral") || m.contains("smollm") {
            s += ["<|im_end|>", "<|endoftext|>"]
        }
        // Gemma-3 turn-format закрывается <end_of_turn>.
        if m.contains("gemma-3") || m.contains("gemma_3") {
            s += ["<end_of_turn>"]
        }
        // SmolLM3 - hybrid-thinking: на всякий случай рубим <think>, если просочится в raw.
        if m.contains("smollm") {
            s += ["<think>"]
        }
        return s
    }
}
