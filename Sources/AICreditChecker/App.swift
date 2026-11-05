import SwiftUI

@main
struct AICreditCheckerApp: App {
    @State private var store = UsageStore()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(store: store)
        } label: {
            Image(systemName: "gauge.with.dots.needle.33percent")
        }
        .menuBarExtraStyle(.window)
    }
}
