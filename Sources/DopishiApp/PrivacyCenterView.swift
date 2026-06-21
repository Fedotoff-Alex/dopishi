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
                Toggle(L.tr("privacy.pause.toggle"), isOn: Binding(
                    get: { !vm.config.enabled },
                    set: { vm.config.enabled = !$0 }
                ))
            } header: {
                Text(L.tr("privacy.pause.header"))
            } footer: {
                Text(L.tr("privacy.pause.footer"))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Toggle(L.tr("privacy.memory.toggle"), isOn: $vm.config.memoryEnabled)
                Picker(L.tr("privacy.memory.keep"), selection: $vm.config.memoryTTLDays) {
                    ForEach(Self.ttlChoices, id: \.self) { d in
                        Text(L.tr("privacy.ttl.days", d)).tag(d)
                    }
                }
                HStack {
                    Button(L.tr("privacy.memory.clear")) { vm.clearMemory() }
                    Button(L.tr("privacy.memory.export")) { vm.exportMemory() }
                        .disabled(!vm.config.memoryEnabled)
                }
            } header: {
                Text(L.tr("privacy.memory.header"))
            } footer: {
                Text(L.tr("privacy.memory.footer"))
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
                Menu(L.tr("privacy.exclusions.addApp")) {
                    ForEach(vm.pickableMemoryApps) { app in
                        Button(app.name) { vm.addMemoryExclusion(bundleId: app.id) }
                    }
                }
            } header: {
                Text(L.tr("privacy.exclusions.header"))
            } footer: {
                Text(L.tr("privacy.exclusions.footer"))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Toggle(L.tr("privacy.stats.toggle"), isOn: $vm.config.suggestionTelemetryEnabled)
            } header: {
                Text(L.tr("privacy.stats.header"))
            } footer: {
                Text(L.tr("privacy.stats.footer"))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                LabeledContent(L.tr("privacy.storage.dbSize"), value: vm.memoryDbSizeText)
                LabeledContent(L.tr("privacy.storage.kind"), value: L.tr("privacy.storage.kindValue"))
            } header: {
                Text(L.tr("privacy.storage.header"))
            } footer: {
                Text(L.tr("privacy.storage.footer"))
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
}
