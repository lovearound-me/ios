import SwiftUI

@main
struct LoveAroundApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            Group {
                if let page = model.demo?.page {
                    DemoPageView(page: page)
                } else {
                    RootView()
                }
            }
            .environmentObject(model)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch model.screen {
            case .signIn: SignInView()
            case .emailExists: EmailExistsView()
            case .code: CodeView()
            case .connected: ConnectedView()
            case .main: MainView()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.refresh() } }
        }
    }
}

/// A navigation screen on its own, for screenshots.
struct DemoPageView: View {
    let page: Demo.Page

    var body: some View {
        NavigationStack {
            switch page {
            case .computer: ComputerView(code: Demo.code.code)
            case .settings: SettingsView()
            case .delete: DeleteAccountView()
            }
        }
    }
}
