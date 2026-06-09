import SwiftUI

struct SettingsView: View {
    @ObservedObject var vm: SettingsViewModel

    var body: some View {
        Form {
            Section {
                Toggle("Запускать при входе в систему", isOn: Binding(
                    get: { vm.launchAtLogin },
                    set: { vm.launchAtLogin = $0 }
                ))
                Toggle("Поддержка Electron-приложений", isOn: $vm.config.electronSupport)
            } header: {
                Text("Система")
            } footer: {
                Text("Поддержка Electron включает чтение текста в Claude, VS Code и подобных (исправления и раскладка). Может влиять на оконные менеджеры (Magnet, Rectangle) - включайте при необходимости.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Toggle("Контекст экрана (OCR)", isOn: $vm.config.screenContextEnabled)
                if vm.config.screenContextEnabled {
                    Button("Открыть настройки записи экрана…") {
                        ScreenCapturePermission.openSettings()
                    }
                }
                Toggle("Контекст буфера обмена", isOn: $vm.config.clipboardContextEnabled)
                Toggle("Память (помнить написанное в окне)", isOn: $vm.config.memoryEnabled)
                if vm.config.memoryEnabled {
                    Button("Очистить память…") { vm.clearMemory() }
                }
            } header: {
                Text("Контекст")
            } footer: {
                Text("Подсказки учитывают текст вокруг поля (тема письма, собеседник, заголовок), недавно скопированный текст и историю того, что вы писали в этом окне. Всё локально (SQLite на вашем Mac), ничего не уходит в сеть. OCR требует «Запись экрана». Буфер подмешивается только если свежий (<5 мин) и пересекается с тем, что вы печатаете. Память хранится до 14 дней, секреты не записываются. Ничего не работает в secure-полях и исключённых приложениях.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Подсказки") {
                Toggle("Показывать подсказки", isOn: $vm.config.enabled)
                Stepper("Задержка: \(vm.config.debounceMs) мс",
                        value: $vm.config.debounceMs, in: 60...1500, step: 10)
                Stepper("Минимум символов: \(vm.config.minChars)",
                        value: $vm.config.minChars, in: 1...20)
                Stepper("Длина дополнения: до \(vm.config.maxCompletionWords) слов",
                        value: $vm.config.maxCompletionWords, in: 1...12)
            }

            Section("Модель") {
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
                        } else if row.selected {
                            Text("используется").font(.caption).foregroundStyle(.secondary)
                        } else {
                            Button(row.downloaded ? "Выбрать" : "Скачать") { vm.choose(modelId: row.id) }
                                .disabled(vm.downloadingId != nil)
                        }
                    }
                    .padding(.vertical, 4)
                }
                if !vm.statusText.isEmpty {
                    Text(vm.statusText).font(.caption).foregroundStyle(.secondary)
                }
            }

            Section {
                Toggle("Переключать раскладку по тапу Option", isOn: $vm.config.manualLayoutSwitchEnabled)
                Toggle("Автопереключение раскладки", isOn: $vm.config.layoutSwitchEnabled)
                Toggle("Предлагать исправление опечаток (зелёным, Tab)", isOn: $vm.config.autocorrectEnabled)
                Toggle("Гасить системное автоисправление macOS", isOn: $vm.config.disableSystemAutocorrect)
            } header: {
                Text("Исправления")
            } footer: {
                Text("Опечатка не заменяется сама - предлагается исправление зелёным призраком, Tab заменяет слово. Системное автоисправление macOS можно погасить, чтобы оно не конфликтовало (применяется после перезапуска приложения).")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                TextField("Напр.: пиши кратко и по-деловому, без воды",
                          text: $vm.config.writingInstructions, axis: .vertical)
                    .lineLimit(2...5)
            } header: {
                Text("Указания по стилю")
            } footer: {
                Text("Подмешиваются в начало промпта, влияют на стиль/тон продолжений. Пусто - без указаний.")
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
                Menu("Добавить приложение…") {
                    ForEach(vm.pickableApps) { app in
                        Button(app.name) { vm.addExclusion(bundleId: app.id) }
                    }
                }
            } header: {
                Text("Не работать в приложениях")
            } footer: {
                Text("Dopishi работает во всех приложениях. Здесь - где полностью выключить (подсказки, авто- и ручное переключение).")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 640)
        .onChange(of: vm.config) { _, _ in
            vm.persist()
        }
    }
}
