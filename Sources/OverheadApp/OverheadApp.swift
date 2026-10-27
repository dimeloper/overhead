import SwiftUI

@main
struct OverheadApp: App {
    @StateObject private var model = OverheadModel()

    var body: some Scene {
        MenuBarExtra {
            PopoverView(model: model)
        } label: {
            Text(model.menuTitle).monospacedDigit()
        }
        .menuBarExtraStyle(.window)
    }
}
