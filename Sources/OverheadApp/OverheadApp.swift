import SwiftUI

@main
struct OverheadApp: App {
    @StateObject private var model: OverheadModel

    init() {
        let model = OverheadModel()
        _model = StateObject(wrappedValue: model)
        Snapshot.runIfRequested(model: model)
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView(model: model)
        } label: {
            Image(nsImage: model.menuReadout.image())
                .accessibilityLabel(model.menuAccessibilityLabel)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
        }
    }
}
