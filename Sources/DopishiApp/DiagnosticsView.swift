import SwiftUI

/// Панель диагностики «почему не работает»: права, модель, фичи, текущее поле, каналы
/// контекста и причина последнего исхода подсказки. Только чтение, живо обновляется.
struct DiagnosticsView: View {
    @ObservedObject var center: DiagnosticsCenter

    private var r: DiagnosticsRuntime { center.runtime }
    private var c: DiagnosticsContext { center.context }

    var body: some View {
        Form {
            Section("Готовность") {
                boolRow("Accessibility", r.accessibility)
                boolRow("Input Monitoring", r.inputMonitoring)
                boolRow("Запись экрана (для OCR)", r.screenRecording)
                boolRow("Монитор ввода запущен", r.monitorRunning)
                boolRow("Включено мастер-тумблером", r.masterEnabled)
                row("Модель", r.modelPresent ? r.modelFile : "не скачана (\(r.modelFile))")
            }

            Section("Фичи") {
                boolRow("Автодополнение / контекст", r.masterEnabled)
                boolRow("Переключение раскладки (авто)", r.layout)
                boolRow("Ручной свитч (тап Option)", r.manualLayout)
                boolRow("Исправление написания", r.autocorrect)
                boolRow("Поддержка Electron", r.electron)
                boolRow("Контекст: OCR экрана", r.screenContext)
                boolRow("Контекст: буфер обмена", r.clipboard)
                boolRow("Контекст: память окна", r.memory)
            }

            Section("Текущее поле") {
                row("Приложение", c.app)
                row("Профиль", c.profile)
                row("Tier", c.secure ? "\(c.tier)  [SECURE]" : c.tier)
                row("Каретка", c.caret, mono: true)
            }

            Section {
                row("OCR", channel(enabled: r.screenContext, preview: c.ocrPreview), mono: true)
                row("Буфер", channel(enabled: r.clipboard, preview: c.clipboardPreview), mono: true)
                row("Память", channel(enabled: r.memory, preview: c.memoryPreview), mono: true)
            } header: {
                Text("Каналы контекста (что видит модель)")
            } footer: {
                Text("«выкл» - фича отключена; «нет данных» - фича включена, но для текущего поля канал пуст (нет окружения / буфер нерелевантен / память пуста).")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                row("Последний исход", center.lastOutcome)
                row("Обновлено", center.updatedAt.map(Self.time) ?? "-")
            } header: {
                Text("Подсказка")
            } footer: {
                Text("Что произошло с последним запросом подсказки в текущем поле. Если подсказок нет - здесь причина (например, «нет позиции каретки» или «слишком мало набрано»).")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                row("p50 (до первого токена)", latencyMs(center.latencyMetrics.p50FirstMs))
                row("p95 (до первого токена)", latencyMs(center.latencyMetrics.p95FirstMs))
                row("p50 (весь стрим)", latencyMs(center.latencyMetrics.p50TotalMs))
                row("p95 (весь стрим)", latencyMs(center.latencyMetrics.p95TotalMs))
            } header: {
                Text("Latency (последние 7 дней)")
            } footer: {
                Text("Время от запроса до первого токена / до конца стрима. Только показанные подсказки (принятие не даёт отдельного замера).")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                row("p50 (read)", latencyMs(center.latencyMetrics.p50AXReadMs))
                row("p95 (read)", latencyMs(center.latencyMetrics.p95AXReadMs))
            } header: {
                Text("AX read (горячий путь)")
            } footer: {
                Text("Время одного AccessibilityReader.read() на нажатие. Базлайн до оптимизации range-чтения - для сравнения p50/p95.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                if center.refusalCounts.isEmpty {
                    row("Причины отказа", "нет данных")
                } else {
                    ForEach(center.refusalCounts.sorted { $0.value > $1.value }, id: \.key) { reason, count in
                        row(reason, "\(count)")
                    }
                }
            } header: {
                Text("Почему подсказка не показалась (7 дней)")
            } footer: {
                // Запись policy-отказов авто-пути (secure-поле, исключённое приложение, мало
                // набрано) - на каждое нажатие клавиши, hot-path. Сознательно не пишем их в
                // suggestion_event (решение аудита фазы 1, полный учёт - в Phase 6); живую
                // причину показывает строка «Последний исход» выше.
                Text("Только отказы по явному запросу подсказки: нет позиции каретки, пустое поле, устаревший контекст. Отказы автоподсказки (secure-поле, исключённое приложение, мало набрано) сюда не пишутся - текущую причину видно в строке «Последний исход».")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 460, minHeight: 560)
        .onAppear {
            Task { @MainActor in await center.refreshLatencyMetrics() }
        }
    }

    // MARK: - Строки

    private func latencyMs(_ ms: Int) -> String { ms == 0 ? "-" : "\(ms) мс" }

    private func row(_ label: String, _ value: String, mono: Bool = false) -> some View {
        HStack(alignment: .top) {
            Text(label)
            Spacer(minLength: 16)
            Text(value)
                .font(mono ? .system(.body, design: .monospaced) : .body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }

    private func boolRow(_ label: String, _ on: Bool) -> some View {
        HStack {
            Text(label)
            Spacer(minLength: 16)
            Image(systemName: on ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(on ? .green : .secondary)
            Text(on ? "да" : "нет").foregroundStyle(.secondary)
        }
    }

    private func channel(enabled: Bool, preview: String?) -> String {
        guard enabled else { return "выкл" }
        return preview ?? "нет данных"
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private static func time(_ d: Date) -> String {
        timeFormatter.string(from: d)
    }
}
