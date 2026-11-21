import AppKit
import SwiftUI
import CloverCore

/// The places in the Dashboard, in sidebar order: Home, the settings under Customize,
/// then History.
enum DashboardSection: String, CaseIterable, Identifiable {
    case home, clover, quality, saving, controls, general, history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .clover: "Clover"
        case .quality: "Quality"
        case .saving: "Saving"
        case .controls: "Controls"
        case .general: "General"
        case .history: "History"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .clover: "leaf"
        case .quality: "slider.horizontal.3"
        case .saving: "folder"
        case .controls: "keyboard"
        case .general: "gearshape"
        case .history: "clock.arrow.circlepath"
        }
    }

    /// The settings pages, grouped under Customize in the sidebar.
    static let settings: [DashboardSection] = [.clover, .quality, .saving, .controls, .general]
}

/// Which section the Dashboard shows. Held outside the view so the app can switch it.
@MainActor
final class DashboardNavigator: ObservableObject {
    @Published var section = DashboardSection.home
}

/// How "Open at login" stands, for the General section.
struct LoginState: Equatable {
    var isEnabled = false
    /// Why the last change didn't work, in words the user can act on.
    var message: String?
    var needsApproval = false
    var inApplications = true
}

/// What the Dashboard can ask the app to do.
struct DashboardActions {
    var chooseFiles: () -> Void = {}
    var filesDropped: ([URL]) -> Void = { _ in }
    var reveal: (RecentItem) -> Void
    var open: (RecentItem) -> Void
    var convertAgain: (RecentItem) -> Void
    var remove: (RecentItem) -> Void
    var clearAll: () -> Void
    var refreshTools: () -> Void
    var setLaunchAtLogin: (Bool) -> Void
    var openLoginItems: () -> Void
    var checkForUpdates: () -> Void

    /// Does nothing. For previews and renders.
    static let none = DashboardActions(
        reveal: { _ in }, open: { _ in }, convertAgain: { _ in }, remove: { _ in }, clearAll: {},
        refreshTools: {}, setLaunchAtLogin: { _ in }, openLoginItems: {}, checkForUpdates: {})
}

/// States a render can force, because a picture can't hover, type or search.
struct DashboardForced {
    var leafKey: LayoutKey?
    var leafSelected: String?
    var leafHovered: String?
    /// The Leaves list's Hidden part, open.
    var leafShowHidden = false
    var recording = false
    var rejected = false
    var query = ""
}

/// Everything the sections show and change.
struct DashboardData {
    var catalog: Catalog
    var layouts: Binding<[LayoutKey: LeafLayout]>
    var conversion: Binding<ConversionSettings>
    var outputFolder: Binding<URL?>
    var revealAfterConverting: Binding<Bool>
    var triggerKey: Binding<TriggerKey>
    var holdToOpen: Binding<Bool>
    var hotkey: Binding<Hotkey?>
    var motion: Binding<MotionPreference>
    var haptics: Binding<Bool>
    var completionSound: Binding<Bool>
    var glassTint: Binding<GlassTint>
    var login: LoginState
    var items: [RecentItem]
    var engines: [EngineInfo]
    var forced = DashboardForced()
}

/// The Dashboard's content, wired to the live model.
struct DashboardRoot: View {
    @ObservedObject var model: AppModel
    @ObservedObject var recents: RecentStore
    @ObservedObject var settings: Settings
    @ObservedObject var login: LaunchAtLogin
    @ObservedObject var navigator: DashboardNavigator
    let actions: DashboardActions

    init(model: AppModel, login: LaunchAtLogin, navigator: DashboardNavigator, actions: DashboardActions) {
        self.model = model
        self.recents = model.recents
        self.settings = model.settings
        self.login = login
        self.navigator = navigator
        self.actions = actions
    }

    var body: some View {
        DashboardView(
            section: $navigator.section,
            data: DashboardData(
                catalog: model.catalog,
                layouts: $settings.layouts,
                conversion: $settings.conversion,
                outputFolder: $settings.outputFolder,
                revealAfterConverting: $settings.revealAfterConverting,
                triggerKey: $settings.triggerKey,
                holdToOpen: $settings.holdToOpen,
                hotkey: $settings.hotkey,
                motion: $settings.motion,
                haptics: $settings.haptics,
                completionSound: $settings.completionSound,
                glassTint: $settings.glassTint,
                login: LoginState(isEnabled: login.isEnabled, message: login.message,
                                  needsApproval: login.needsApproval, inApplications: login.isInApplications),
                items: recents.items,
                engines: EngineInfo.list(from: model.tools)),
            actions: actions)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            login.refresh()
        }
    }
}

/// The Dashboard: a sidebar of sections and the section beside it.
struct DashboardView: View {
    @Binding var section: DashboardSection
    let data: DashboardData
    let actions: DashboardActions
    @State private var columns = NavigationSplitViewVisibility.all

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            sidebar
        } detail: {
            detail
                // The Leaves preview shows the clover in the chosen tint.
                .environment(\.glassTint, data.glassTint.wrappedValue)
                .navigationTitle(section.title)
                .toolbar {
                    // A window around a hosted view doesn't get the sidebar button by itself.
                    ToolbarItem(placement: .navigation) {
                        Button {
                            columns = columns == .detailOnly ? .all : .detailOnly
                        } label: {
                            Image(systemName: "sidebar.leading")
                        }
                        .help("Show or hide the sidebar")
                        .accessibilityLabel("Show or hide the sidebar")
                    }
                }
        }
    }

    private var sidebar: some View {
        List(selection: Binding<DashboardSection?>(get: { section }, set: { if let new = $0 { section = new } })) {
            row(.home)
            Section("Customize") {
                ForEach(DashboardSection.settings) { row($0) }
            }
            Section {
                row(.history)
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
        .safeAreaInset(edge: .bottom, spacing: 0) { AboutBlock(checkForUpdates: actions.checkForUpdates) }
    }

    private func row(_ item: DashboardSection) -> some View {
        Label(item.title, systemImage: item.symbol).tag(item)
    }

    @ViewBuilder private var detail: some View {
        switch section {
        case .home:
            DashboardHome(items: data.items, engines: data.engines, trigger: data.triggerKey.wrappedValue,
                          actions: actions, go: { section = $0 })
        case .clover:
            LeavesSection(catalog: data.catalog, layouts: data.layouts, glassTint: data.glassTint,
                          reduceMotion: data.motion.wrappedValue.reduces, forced: data.forced)
        case .quality:
            QualitySection(conversion: data.conversion)
        case .saving:
            OutputSection(conversion: data.conversion, outputFolder: data.outputFolder,
                          revealAfterConverting: data.revealAfterConverting)
        case .controls:
            ShortcutsSection(triggerKey: data.triggerKey, holdToOpen: data.holdToOpen, hotkey: data.hotkey,
                             forceRecording: data.forced.recording, forceRejected: data.forced.rejected)
        case .general:
            GeneralSection(motion: data.motion, haptics: data.haptics, completionSound: data.completionSound,
                           login: data.login, engines: data.engines, actions: actions)
        case .history:
            HistorySection(items: data.items, actions: actions, initialQuery: data.forced.query)
        }
    }
}

/// The icon, name, version, copyright and Check for Updates at the bottom of the sidebar.
private struct AboutBlock: View {
    let checkForUpdates: () -> Void

    private var version: String {
        let info = Bundle.main.infoDictionary
        guard let short = info?["CFBundleShortVersionString"] as? String else { return "Development build" }
        let build = info?["CFBundleVersion"] as? String
        return build.map { "Version \(short) (\($0))" } ?? "Version \(short)"
    }

    private var copyright: String {
        Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String ?? "© 2026 Irfan Abdul Hameed"
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 32, height: 32)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Clover")
                            .font(.system(size: 12, weight: .semibold))
                        Text(version)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                Text(copyright)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Button("Check for Updates", action: checkForUpdates)
                    .controlSize(.small)
                    .help("Ask GitHub whether a newer Clover is out")
                    .padding(.top, 2)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
        }
    }
}

/// A line of explanation under a setting.
struct Hint: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The line under a group of settings, left-aligned with the group.
struct FormFooter: View {
    let text: String
    var tint: Color?
    init(_ text: String, tint: Color? = nil) {
        self.text = text
        self.tint = tint
    }

    var body: some View {
        Text(text)
            .foregroundStyle(tint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.secondary))
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension MotionPreference {
    /// True when motion should be reduced, from this choice or the system's.
    var reduces: Bool {
        switch self {
        case .system: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        case .full: false
        case .reduced: true
        }
    }
}
