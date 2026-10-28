import AppKit
import OverheadCore
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: OverheadModel
    @ObservedObject var updater: Updater
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Menu bar") {
                Toggle("CPU", isOn: $model.showCPU)
                Toggle("Memory", isOn: $model.showMemory)
                Picker("Show memory as", selection: $model.memoryAsPercent) {
                    Text("Percent of total").tag(true)
                    Text("Gigabytes in use").tag(false)
                }
                .disabled(!model.showMemory)
                Toggle(isOn: $model.showBattery) {
                    Text("Battery time")
                    Text("Only while unplugged: time left at your current pace")
                }
                Toggle(isOn: $model.showAwakeCup) {
                    Text("Cup while keeping the Mac awake")
                }
                LabeledContent("Preview") {
                    Image(nsImage: model.menuReadout.image())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                }
            }

            Section("General") {
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }

            Section {
                ForEach(model.extraProjectFolders, id: \.self) { folder in
                    HStack {
                        Image(systemName: "folder").foregroundStyle(.secondary)
                        Text(abbreviated(folder)).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button {
                            model.extraProjectFolders.removeAll { $0 == folder }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Remove \(abbreviated(folder))")
                    }
                }
                Button("Add Folder…", action: addFolder)
            } header: {
                Text("Project folders")
            } footer: {
                Text("Overhead finds git checkouts up to two folders below your home folder. Add folders that live elsewhere, or deeper.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("About") {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")
                if updater.isRunning {
                    Toggle("Check for updates automatically", isOn: $updater.automaticChecks)
                    Button("Check for Updates…", action: updater.check)
                }
                Link("Source code on GitHub", destination: URL(string: "https://github.com/dimeloper/overhead")!)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        // A menu bar app is never the active app, so its window would open behind whatever is in front.
        .onAppear { NSApp.activate(ignoringOtherApps: true) }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Could not change this: \(error.localizedDescription). Move Overhead to Applications and try again."
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        let added = panel.urls.map(\.path).filter { !model.extraProjectFolders.contains($0) }
        model.extraProjectFolders += added
    }

    private func abbreviated(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }
}
