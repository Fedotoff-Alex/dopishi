import SwiftUI

struct SettingsView: View {
    @ObservedObject var vm: SettingsViewModel
    @State private var newDictWord = ""

    var body: some View {
        Form {
            Section {
                Toggle(L.tr("settings.launchAtLogin"), isOn: Binding(
                    get: { vm.launchAtLogin },
                    set: { vm.launchAtLogin = $0 }
                ))
                Toggle(L.tr("settings.electronSupport"), isOn: $vm.config.electronSupport)
            } header: {
                Text(L.tr("settings.system.header"))
            } footer: {
                Text(L.tr("settings.system.footer"))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Toggle(L.tr("settings.context.ocr"), isOn: $vm.config.screenContextEnabled)
                if vm.config.screenContextEnabled {
                    Button(L.tr("settings.context.openScreenRecording")) {
                        ScreenCapturePermission.openSettings()
                    }
                }
                Toggle(L.tr("settings.context.clipboard"), isOn: $vm.config.clipboardContextEnabled)
                Toggle(L.tr("settings.context.memory"), isOn: $vm.config.memoryEnabled)
                if vm.config.memoryEnabled {
                    Button(L.tr("settings.context.clearMemory")) { vm.clearMemory() }
                }
            } header: {
                Text(L.tr("settings.context.header"))
            } footer: {
                Text(L.tr("settings.context.footer"))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section(L.tr("settings.suggestions.header")) {
                Toggle(L.tr("settings.suggestions.show"), isOn: $vm.config.enabled)
                Stepper(L.tr("settings.suggestions.debounce", vm.config.debounceMs),
                        value: $vm.config.debounceMs, in: 60...1500, step: 10)
                Stepper(L.tr("settings.suggestions.minChars", vm.config.minChars),
                        value: $vm.config.minChars, in: 1...20)
                Stepper(L.tr("settings.suggestions.maxWords", vm.config.maxCompletionWords),
                        value: $vm.config.maxCompletionWords, in: 1...12)
            }

            Section {
                ForEach(vm.modelRows) { row in
                    HStack(spacing: 12) {
                        Image(systemName: row.selected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(row.selected ? Color.accentColor : Color.secondary)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.name).fontWeight(row.selected ? .semibold : .regular)
                            Text(row.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if row.downloading {
                            ProgressView(value: vm.downloadProgress).frame(width: 90)
                            Button(L.tr("settings.model.cancel")) { vm.cancelDownload() }
                                .help(L.tr("settings.model.cancelHelp"))
                        } else if row.selected {
                            Text(L.tr("settings.model.inUse")).font(.caption).foregroundStyle(.secondary)
                            Button(L.tr("settings.model.speed")) { vm.benchCurrentModel() }
                                .disabled(vm.benchRunning || !row.downloaded)
                                .help(L.tr("settings.model.speedHelp"))
                        } else {
                            Button(row.downloaded ? L.tr("settings.model.select") : L.tr("settings.model.download")) { vm.choose(modelId: row.id) }
                                .disabled(vm.downloadingId != nil)
                            if row.deletable {
                                Button {
                                    vm.deleteModel(modelId: row.id)
                                } label: {
                                    Image(systemName: "trash").foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help(L.tr("settings.model.deleteHelp"))
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                if !vm.statusText.isEmpty {
                    Text(vm.statusText).font(.caption).foregroundStyle(.secondary)
                }
                if !vm.modelsTotalText.isEmpty {
                    Text(vm.modelsTotalText).font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text(L.tr("settings.model.header"))
            } footer: {
                Text(L.tr("settings.model.footer", vm.ramRecommendationText))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Toggle(L.tr("settings.corrections.manualLayout"), isOn: $vm.config.manualLayoutSwitchEnabled)
                Toggle(L.tr("settings.corrections.autoLayout"), isOn: $vm.config.layoutSwitchEnabled)
                Toggle(L.tr("settings.corrections.autocorrect"), isOn: $vm.config.autocorrectEnabled)
                Toggle(L.tr("settings.corrections.disableSystem"), isOn: $vm.config.disableSystemAutocorrect)
            } header: {
                Text(L.tr("settings.corrections.header"))
            } footer: {
                Text(L.tr("settings.corrections.footer"))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    TextField(L.tr("settings.dictionary.addPlaceholder"), text: $newDictWord)
                        .onSubmit { addWord() }
                    Button(L.tr("settings.dictionary.add")) { addWord() }
                        .disabled(newDictWord.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ForEach(vm.config.customDictionary, id: \.self) { word in
                    HStack {
                        Text(word)
                        Spacer()
                        Button {
                            vm.removeDictionaryWord(word)
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                Text(L.tr("settings.dictionary.header"))
            } footer: {
                Text(L.tr("settings.dictionary.footer"))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                TextField(L.tr("settings.style.placeholder"),
                          text: $vm.config.writingInstructions, axis: .vertical)
                    .lineLimit(2...5)
            } header: {
                Text(L.tr("settings.style.header"))
            } footer: {
                Text(L.tr("settings.style.footer"))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                TextField(L.tr("settings.snippets.placeholder"),
                          text: $vm.config.snippetsRaw, axis: .vertical)
                    .lineLimit(3...8)
                    .font(.system(.body, design: .monospaced))
            } header: {
                Text(L.tr("settings.snippets.header"))
            } footer: {
                Text(L.tr("settings.snippets.footer"))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                ForEach(vm.excludedAppRows) { row in
                    HStack {
                        Text(row.name)
                        Spacer()
                        Button {
                            vm.removeExclusion(bundleId: row.id)
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Menu(L.tr("settings.exclusions.addApp")) {
                    ForEach(vm.pickableApps) { app in
                        Button(app.name) { vm.addExclusion(bundleId: app.id) }
                    }
                }
            } header: {
                Text(L.tr("settings.exclusions.header"))
            } footer: {
                Text(L.tr("settings.exclusions.footer"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 640)
        .onChange(of: vm.config) { _, _ in
            vm.persist()
        }
    }

    private func addWord() {
        vm.addDictionaryWord(newDictWord)
        newDictWord = ""
    }
}
