import SwiftUI

/// Панель диагностики «почему не работает»: права, модель, фичи, текущее поле, каналы
/// контекста и причина последнего исхода подсказки. Только чтение, живо обновляется.
struct DiagnosticsView: View {
    @ObservedObject var center: DiagnosticsCenter

    private var r: DiagnosticsRuntime { center.runtime }
    private var c: DiagnosticsContext { center.context }

    var body: some View {
        Form {
            Section(L.tr("diagnostics.section.readiness")) {
                // Имена системных разрешений - технические, не переводятся (совпадают с macOS).
                boolRow("Accessibility", r.accessibility)
                boolRow("Input Monitoring", r.inputMonitoring)
                boolRow(L.tr("diagnostics.screenRecording"), r.screenRecording)
                boolRow(L.tr("diagnostics.monitorRunning"), r.monitorRunning)
                boolRow(L.tr("diagnostics.masterEnabled"), r.masterEnabled)
                row(L.tr("diagnostics.model"), r.modelPresent ? r.modelFile : L.tr("diagnostics.model.notDownloaded", r.modelFile))
            }

            Section(L.tr("diagnostics.section.features")) {
                boolRow(L.tr("diagnostics.features.autocompleteContext"), r.masterEnabled)
                boolRow(L.tr("diagnostics.features.layoutAuto"), r.layout)
                boolRow(L.tr("diagnostics.features.manualLayout"), r.manualLayout)
                boolRow(L.tr("diagnostics.features.autocorrect"), r.autocorrect)
                boolRow(L.tr("diagnostics.features.electron"), r.electron)
                boolRow(L.tr("diagnostics.features.contextOcr"), r.screenContext)
                boolRow(L.tr("diagnostics.features.contextClipboard"), r.clipboard)
                boolRow(L.tr("diagnostics.features.contextMemory"), r.memory)
            }

            Section(L.tr("diagnostics.section.field")) {
                row(L.tr("diagnostics.field.app"), c.app)
                // c.profile - стабильный id из DiagnosticsCenter (D-11), локализуем здесь.
                row(L.tr("diagnostics.field.profile"), L.tr(c.profile))
                row(L.tr("diagnostics.field.tier"), c.secure ? L.tr("diagnostics.field.tierSecure", c.tier) : c.tier)
                row(L.tr("diagnostics.field.caret"), c.caret, mono: true)
            }

            Section {
                row(L.tr("diagnostics.channels.ocr"), channel(enabled: r.screenContext, preview: c.ocrPreview), mono: true)
                row(L.tr("diagnostics.channels.clipboard"), channel(enabled: r.clipboard, preview: c.clipboardPreview), mono: true)
                row(L.tr("diagnostics.channels.memory"), channel(enabled: r.memory, preview: c.memoryPreview), mono: true)
            } header: {
                Text(L.tr("diagnostics.channels.header"))
            } footer: {
                Text(L.tr("diagnostics.channels.footer"))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                row(L.tr("diagnostics.suggestion.lastOutcome"), center.lastOutcome)
                row(L.tr("diagnostics.suggestion.updated"), center.updatedAt.map(Self.time) ?? "-")
            } header: {
                Text(L.tr("diagnostics.suggestion.header"))
            } footer: {
                Text(L.tr("diagnostics.suggestion.footer"))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                row(L.tr("diagnostics.latency.p50First"), latencyMs(center.latencyMetrics.p50FirstMs))
                row(L.tr("diagnostics.latency.p95First"), latencyMs(center.latencyMetrics.p95FirstMs))
                row(L.tr("diagnostics.latency.p50Total"), latencyMs(center.latencyMetrics.p50TotalMs))
                row(L.tr("diagnostics.latency.p95Total"), latencyMs(center.latencyMetrics.p95TotalMs))
            } header: {
                Text(L.tr("diagnostics.latency.header"))
            } footer: {
                Text(L.tr("diagnostics.latency.footer"))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                row(L.tr("diagnostics.axRead.p50"), latencyMs(center.latencyMetrics.p50AXReadMs))
                row(L.tr("diagnostics.axRead.p95"), latencyMs(center.latencyMetrics.p95AXReadMs))
            } header: {
                Text(L.tr("diagnostics.axRead.header"))
            } footer: {
                Text(L.tr("diagnostics.axRead.footer"))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                if center.refusalCounts.isEmpty {
                    row(L.tr("diagnostics.refusals.label"), L.tr("diagnostics.refusals.noData"))
                } else {
                    // reason - технический ключ метрики (policy-отказ), не user-facing строка.
                    ForEach(center.refusalCounts.sorted { $0.value > $1.value }, id: \.key) { reason, count in
                        row(reason, "\(count)")
                    }
                }
            } header: {
                Text(L.tr("diagnostics.refusals.header"))
            } footer: {
                // Запись policy-отказов авто-пути (secure-поле, исключённое приложение, мало
                // набрано) - на каждое нажатие клавиши, hot-path. Сознательно не пишем их в
                // suggestion_event (решение аудита фазы 1, полный учёт - в Phase 6); живую
                // причину показывает строка «Последний исход» выше.
                Text(L.tr("diagnostics.refusals.footer"))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                // MEM-06 D-06: счётчик secret-drop (только число, сырой текст к метрике не доходит).
                row(L.tr("diagnostics.secretDropped.label"), L.tr("diagnostics.secretDropped.count", center.secretDropped))
            } header: {
                Text(L.tr("diagnostics.secretDropped.header"))
            } footer: {
                Text(L.tr("diagnostics.secretDropped.footer"))
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

    private func latencyMs(_ ms: Int) -> String { ms == 0 ? "-" : L.tr("diagnostics.ms", ms) }

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
            Text(on ? L.tr("diagnostics.bool.yes") : L.tr("diagnostics.bool.no")).foregroundStyle(.secondary)
        }
    }

    private func channel(enabled: Bool, preview: String?) -> String {
        guard enabled else { return L.tr("diagnostics.channels.off") }
        return preview ?? L.tr("diagnostics.channels.noData")
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
