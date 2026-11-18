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
            .tint(Theme.link)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            if model.signedIn {
                MainTabs()
            } else {
                SignInView()
            }
            if model.incoming {
                SignalOverlay(color: Palette.color(model.myColor), seed: model.signalSeed)
                    .onTapGesture { model.dismissSignal() }
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: model.incoming)
        .onOpenURL { model.handle(url: $0) }
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active: model.becameActive()
            case .background: model.wentToBackground()
            default: break
            }
        }
    }
}

struct MainTabs: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        TabView(selection: $model.tab) {
            HomeView()
                .tabItem { Label(tr("Сердечки"), systemImage: "heart.fill") }
                .tag(AppModel.Tab.hearts)
            BookView()
                .tabItem { Label(tr("Книга"), systemImage: "book.closed") }
                .tag(AppModel.Tab.book)
            ToysView()
                .tabItem { Label(tr("Игрушки"), systemImage: "lightbulb") }
                .tag(AppModel.Tab.toys)
            SettingsView()
                .tabItem { Label(tr("Настройки"), systemImage: "slider.horizontal.3") }
                .tag(AppModel.Tab.settings)
        }
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                ToastView(toast: toast)
                    .padding(.bottom, 96)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: model.toast)
        .sheet(item: $model.adding) { adding in
            NavigationStack {
                AddContactView(invite: adding.invite)
            }
        }
    }
}

/// «Аня — улетело ♥» for a moment, over the tab bar.
struct ToastView: View {
    let toast: AppModel.Toast

    var body: some View {
        Text(toast.text)
            .font(.system(size: 15, weight: .semibold))
            .multilineTextAlignment(.center)
            .foregroundStyle(toast.failed ? Theme.danger : Theme.ink)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Theme.paper, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.ink.opacity(0.12)))
            .shadow(color: .black.opacity(0.14), radius: 14, y: 6)
            .padding(.horizontal, 24)
            .accessibilityIdentifier("toast")
    }
}

/// A sheet's screen on its own, for screenshots.
struct DemoPageView: View {
    let page: Demo.Page

    var body: some View {
        NavigationStack {
            switch page {
            case .contact: ContactEditor(contact: Demo.contacts[1])
            case .add: AddContactView(invite: "https://lovearound.me/i/B3NWT-8FJD4")
            case .board: BoardView(shownToken: "dev_demo_7Hq2kLx9WbN4sP0aZr")
            case .pair: PairView(code: "482913")
            }
        }
        .tint(Theme.link)
    }
}
