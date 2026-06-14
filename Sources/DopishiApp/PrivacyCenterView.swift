import SwiftUI

/// Privacy Center (Phase 4, UX-02): контроль над тем, что Допиши хранит и где.
/// Пауза, «не учиться в этом приложении», TTL памяти, очистка/экспорт, размер базы,
/// статус хранилища, тумблер локальной статистики.
struct PrivacyCenterView: View {
    @ObservedObject var vm: SettingsViewModel

    private static let ttlChoices = [1, 3, 7, 14, 30, 90]

    var body: some View {
        Form {
            Section {
                Toggle("Приостановить Допиши", isOn: Binding(
                    get: { !vm.config.enabled },
                    set: { vm.config.enabled = !$0 }
                ))
            } header: {
                Text("Пауза")
            } footer: {
                Text("Полная пауза: подсказки, исправления и запись памяти выключены, пока не включите обратно.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Toggle("Память (помнить написанное в окне)", isOn: $vm.config.memoryEnabled)
                Picker("Хранить записи", selection: $vm.config.memoryTTLDays) {
                    ForEach(Self.ttlChoices, id: \.self) { d in
                        Text(Self.ttlLabel(d)).tag(d)
                    }
                }
                HStack {
                    Button("Очистить память…") { vm.clearMemory() }
                    Button("Экспортировать…") { vm.exportMemory() }
                        .disabled(!vm.config.memoryEnabled)
                }
            } header: {
                Text("Память")
            } footer: {
                Text("Память локальная (SQLite на вашем Mac), ничего не уходит в сеть. Очистка удаляет и записи памяти, и статистику подсказок. Экспорт сохраняет записи в JSON-файл.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                ForEach(vm.memoryExcludedAppRows) { row in
                    HStack {
                        Text(row.name)
                        Spacer()
                        Button {
                            vm.removeMemoryExclusion(bundleId: row.id)
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Menu("Добавить приложение…") {
                    ForEach(vm.pickableMemoryApps) { app in
                        Button(app.name) { vm.addMemoryExclusion(bundleId: app.id) }
                    }
                }
            } header: {
                Text("Не учиться в приложениях")
            } footer: {
                Text("Подсказки в этих приложениях работают, но написанное в них НЕ записывается в память (мессенджер с личным, рабочая почта и т.п.).")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Toggle("Локальная статистика подсказок", isOn: $vm.config.suggestionTelemetryEnabled)
            } header: {
                Text("Статистика")
            } footer: {
                Text("Только метаданные: исход (показана/принята/отклонена), задержка, приложение, модель. Текст НЕ сохраняется. Питает метрики диагностики и адаптивную подстройку порогов. Хранится 7 дней.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Размер базы", value: vm.memoryDbSizeText)
                LabeledContent("Хранение", value: "обычный файл SQLite (не зашифрован)")
            } header: {
                Text("Хранилище")
            } footer: {
                Text("~/Library/Application Support/Dopishi/memory.sqlite - доступ только у вашего пользователя (права 0600). Шифрования на уровне файла нет; диск с FileVault шифрует его целиком.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 560)
        .onAppear { vm.refreshPrivacyStats() }
        .onChange(of: vm.config) { _, _ in
            vm.persist()
        }
    }

    private static func ttlLabel(_ days: Int) -> String {
        switch days {
        case 1: return "1 день"
        case 3, 7, 14, 30, 90: return days < 5 ? "\(days) дня" : "\(days) дней"
        default: return "\(days) дн."
        }
    }
}
