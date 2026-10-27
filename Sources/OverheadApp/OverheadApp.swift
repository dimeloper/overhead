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
            HStack(spacing: 4) {
                if model.isHoldingAwake { Image(systemName: "cup.and.saucer.fill") }
                Text(model.menuTitle).monospacedDigit()
            }
        }
        .menuBarExtraStyle(.window)
    }
}
