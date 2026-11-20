import SwiftUI
import WatchKit

@main
struct LoveAroundApp: App {
    @WKApplicationDelegateAdaptor(WatchDelegate.self) private var delegate
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
        // A heart's notification while the app isn't in front.
        WKNotificationScene(controller: SignalNotificationController.self, category: "signal")
    }
}

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            switch model.screen {
            case .signIn: SignInView()
            case .emailExists: EmailExistsView()
            case .code: CodeView()
            case .connected: ConnectedView()
            case .main: MainView()
            }
            if model.incoming {
                SignalOverlay(color: Palette.color(model.myColor), seed: model.signalSeed)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: model.incoming)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.refresh() } }
        }
    }
}

/// A navigation screen on its own, for screenshots.
struct DemoPageView: View {
    let page: Demo.Page
    @EnvironmentObject var model: AppModel

    var body: some View {
        ZStack {
            NavigationStack {
                switch page {
                case .computer: ComputerView(code: Demo.code.code)
                case .settings: SettingsView()
                case .layout: LayoutView()
                case .glow: GlowView()
                case .notification:
                    SignalNotificationView(color: Palette.color(model.myColor), box: .init("✨💗💖💞💖💗✨"))
                case .delete: DeleteAccountView()
                }
            }
            if model.incoming {
                SignalOverlay(color: Palette.color(model.myColor), seed: model.signalSeed)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: model.incoming)
    }
}
