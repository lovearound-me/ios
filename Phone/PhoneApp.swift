import SafariServices
import SwiftUI

@main
struct LoveAroundApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
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
    @Environment(\.dynamicTypeSize) private var textSize

    var body: some View {
        ZStack {
            if model.signedIn {
                MainTabs()
            } else {
                SignInView()
            }
            if let out = model.outgoing {
                SendGlow(out: out)
                    .id(out.id)
                    .transition(.opacity)
            }
            // One at a time: what the app is for, then why it asks about
            // notifications.
            if model.howItWorks {
                HowItWorksView(button: tr("Начать")) { model.closeHowItWorks() }
                    .transition(.opacity)
                    .zIndex(1)
            } else if model.notifyIntro {
                NotifyIntroView()
                    .transition(.opacity)
                    .zIndex(1)
            }
            if model.incoming {
                SignalOverlay(color: Palette.color(model.myColor), seed: model.signalSeed)
                    .onTapGesture { model.dismissSignal() }
                    .transition(.opacity)
                    .zIndex(2)
            }
        }
        // Font.app measures the text size when a view is drawn: a new size
        // in the iPhone's settings draws everything again.
        .id(textSize)
        // The site's pages (docs, privacy, «Способы входа») open over the
        // app, not in Safari.
        .environment(\.openURL, OpenURLAction { url in
            guard url.scheme == "https" else { return .systemAction }
            InAppPage.open(url)
            return .handled
        })
        .animation(.easeInOut(duration: 0.3), value: model.incoming)
        .animation(.easeInOut(duration: 0.3), value: model.notifyIntro)
        .animation(.easeInOut(duration: 0.3), value: model.howItWorks)
        .animation(.easeOut(duration: 0.4), value: model.outgoing)
        .onOpenURL { url in
            if GoogleAccount.handle(url) { return }
            model.handle(url: url)
        }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            if let url = activity.webpageURL { model.handle(url: url) }
        }
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
                .tabItem { Label(tr("Устройства"), systemImage: "lightbulb") }
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
        .sheet(isPresented: $model.choosingClose, onDismiss: model.closePickerClosed) {
            NavigationStack {
                ChooseCloseView()
            }
        }
        .sheet(item: $model.adding) { adding in
            NavigationStack {
                AddContactView(invite: adding.invite)
            }
        }
        .sheet(item: $model.pairing) { pairing in
            NavigationStack {
                PairView(code: pairing.code)
            }
        }
    }
}

/// What failed, or «Скопировано», for a moment over the tab bar.
struct ToastView: View {
    let toast: AppModel.Toast

    var body: some View {
        Text(toast.text)
            .font(.app(15, weight: .semibold))
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
            case .choose: ChooseCloseView()
            case .board: BoardView(shownToken: "dev_demo_7Hq2kLx9WbN4sP0aZr")
            case .pair: PairView(code: "482913")
            }
        }
        .tint(Theme.link)
    }
}

/// A page of the site in a Safari sheet over whatever is on screen, a sheet
/// of the app's included.
@MainActor
enum InAppPage {
    static func open(_ url: URL) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard var top = scenes.flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController else {
            UIApplication.shared.open(url)
            return
        }
        while let next = top.presentedViewController { top = next }
        let page = SFSafariViewController(url: url)
        page.preferredControlTintColor = UIColor(Theme.link)
        top.present(page, animated: true)
    }
}

/// Before iOS asks about notifications, once after signing in: what they
/// are for. iOS asks only once, so the question comes when the person has
/// just said yes here.
struct NotifyIntroView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Image(systemName: "bell.badge.fill")
                .font(.app(44))
                .foregroundStyle(Theme.heart)
                .frame(width: 104, height: 104)
                .background(Theme.heartSoft, in: Circle())
            Text(tr("Чтобы сердечко дошло, когда телефон в кармане"))
                .font(.app(26, weight: .bold))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
                .padding(.top, 26)
            Text(tr("Разреши уведомления, и сердечко придёт, даже когда приложение закрыто. От кого оно, не видно никогда. Ни о чём другом мы не пишем."))
                .font(.app(17))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .padding(.top, 12)
            Spacer()
            Button(tr("Разрешить уведомления")) { Task { await model.askForNotifications() } }
                .buttonStyle(WideButton(filled: true))
                .accessibilityIdentifier("notifyIntroAllow")
            Button(tr("Не сейчас")) { model.closeNotifyIntro() }
                .font(.app(17))
                .frame(minHeight: 44)
                .padding(.top, 8)
                .accessibilityIdentifier("notifyIntroLater")
            Text(tr("Включить можно и потом: Настройки → Уведомление."))
                .font(.app(13))
                .foregroundStyle(Theme.faint)
                .multilineTextAlignment(.center)
                .padding(.top, 6)
                .padding(.bottom, 24)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.paper.ignoresSafeArea())
        // VoiceOver stays on this screen, not on the tabs under it.
        .accessibilityAddTraits(.isModal)
    }
}
