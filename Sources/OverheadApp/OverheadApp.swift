import SwiftUI

@main
struct OverheadApp: App {
    @StateObject private var model: OverheadModel
    @StateObject private var updater: Updater

    init() {
        let model = OverheadModel(demo: CommandLine.arguments.contains("--demo"))
        _model = StateObject(wrappedValue: model)
        Snapshot.runIfRequested(model: model)
        let updater = Updater()
        if !model.isDemo { updater.start() }
        _updater = StateObject(wrappedValue: updater)
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView(model: model, updater: updater)
        } label: {
            Image(nsImage: model.menuReadout.image())
                .accessibilityLabel(model.menuAccessibilityLabel)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model, updater: updater)
        }
    }
}
