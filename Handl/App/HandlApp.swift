import SwiftUI

/// -HandlScreen <name> renders a single screen with demo data. Used by the
/// CI screenshot pipeline; inert in production (launch arguments cannot be
/// injected into an App Store build).
enum DemoScreen: String {
    case auth, gate, home, detail, form, household

    static func fromLaunchArguments() -> DemoScreen? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-HandlScreen"), index + 1 < args.count else {
            return nil
        }
        return DemoScreen(rawValue: args[index + 1])
    }
}

extension AppModel {
    static func demoModel(for screen: DemoScreen) -> AppModel {
        let model = AppModel(backend: DemoBackend(startSignedIn: screen != .auth))
        switch screen {
        case .auth:
            model.phase = .signedOut
        case .gate:
            model.user = DemoBackend.user
            model.phase = .noHousehold
        case .home, .detail, .form, .household:
            model.user = DemoBackend.user
            model.household = DemoBackend.household
            model.services = DemoBackend.seedServices
            model.members = DemoBackend.seedMembers
            model.phase = .ready
        }
        return model
    }
}

struct DemoScreenHost: View {
    let screen: DemoScreen

    var body: some View {
        switch screen {
        case .auth: AuthView()
        case .gate: HouseholdGateView()
        case .home: HomeNavigationView()
        case .detail:
            NavigationStack {
                ServiceDetailView(service: DemoBackend.seedServices[0])
            }
        case .form: ServiceFormView(mode: .add)
        case .household: HouseholdView()
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.phase {
        case .loading:
            VStack(spacing: 16) {
                Image(systemName: "house.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Theme.terracotta)
                ProgressView()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
        case .signedOut:
            AuthView()
        case .noHousehold:
            HouseholdGateView()
        case .failed:
            VStack(spacing: 20) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 48))
                    .foregroundStyle(Theme.inkSecondary)
                Text("Couldn't load your information")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                if let message = model.errorMessage {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(Theme.inkSecondary)
                        .multilineTextAlignment(.center)
                }
                BigButton(title: "Try again", systemImage: "arrow.clockwise") {
                    Task { await model.start() }
                }
                .padding(.horizontal, 40)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
        case .ready:
            HomeNavigationView()
        }
    }
}

struct HomeNavigationView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            ServicesListView()
                .navigationDestination(for: Service.self) { service in
                    ServiceDetailView(service: service)
                }
        }
    }
}

@main
struct HandlApp: App {
    private let screenOverride = DemoScreen.fromLaunchArguments()
    @State private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let override = DemoScreen.fromLaunchArguments()
        _model = State(initialValue: override.map { AppModel.demoModel(for: $0) } ?? AppModel())
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let screenOverride {
                    DemoScreenHost(screen: screenOverride)
                } else {
                    RootView()
                        .task { await model.start() }
                }
            }
            .environment(model)
            .tint(Theme.terracotta)
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    Task { await model.refreshQuietly() }
                }
            }
        }
    }
}
