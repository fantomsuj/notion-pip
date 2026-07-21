import SwiftUI

@main
struct NotionPiPApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var runtime: AppRuntime

    init() {
        let runtime = AppRuntime()
        _runtime = StateObject(wrappedValue: runtime)
        appDelegate.bind(urlHandler: runtime)
        runtime.start()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarRootView(runtime: runtime)
        } label: {
            Label("Notion PiP", systemImage: "rectangle.on.rectangle")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(runtime: runtime)
        }
    }
}
