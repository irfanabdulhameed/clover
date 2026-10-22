import SwiftUI
import CloverCore

/// What Home can ask the app to do.
struct HomeActions {
    var chooseFiles: () -> Void
    var filesDropped: ([URL]) -> Void
    var reveal: (RecentItem) -> Void
    var open: (RecentItem) -> Void
    var remove: (RecentItem) -> Void
    var clearAll: () -> Void
    var refreshTools: () -> Void
    var openDashboard: () -> Void
    var quit: () -> Void

    /// Does nothing. For previews and renders.
    static let none = HomeActions(
        chooseFiles: {}, filesDropped: { _ in }, reveal: { _ in }, open: { _ in }, remove: { _ in },
        clearAll: {}, refreshTools: {}, openDashboard: {}, quit: {})
}

/// The popover's content, wired to the live model.
struct HomeRoot: View {
    @ObservedObject var model: AppModel
    @ObservedObject var recents: RecentStore
    @ObservedObject var settings: Settings
    let actions: HomeActions

    init(model: AppModel, actions: HomeActions) {
        self.model = model
        self.recents = model.recents
        self.settings = model.settings
        self.actions = actions
    }

    var body: some View {
        HomeView(items: recents.items, engines: EngineInfo.list(from: model.tools), trigger: settings.triggerKey, actions: actions)
    }
}

/// The Home popover: drop zone, recent conversions (or the first-use hint), engines and footer.
struct HomeView: View {
    let items: [RecentItem]
    let engines: [EngineInfo]
    let trigger: TriggerKey
    let actions: HomeActions
    /// For renders only: show the drop zone as if a drag were over it, or one row as hovered.
    var forceDropTargeted = false
    var forceHoverRow: UUID?

    var body: some View {
        VStack(spacing: 0) {
            DropZone(forceTargeted: forceDropTargeted, onChoose: actions.chooseFiles, onDrop: actions.filesDropped)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, items.isEmpty ? 10 : 8)

            if items.isEmpty {
                EmptyHint(trigger: trigger)
            } else {
                RecentsSection(items: items, actions: actions, forceHoverRow: forceHoverRow)
                    .padding(.bottom, 6)
            }

            Divider()
            EnginesSection(engines: engines, refresh: actions.refreshTools)
            Divider()
            footer
        }
        .frame(width: 320)
    }

    private var footer: some View {
        HStack(spacing: 0) {
            HoverButton(shortcut: KeyboardShortcut(",", modifiers: .command), action: actions.openDashboard) {
                footerLabel("Dashboard", symbol: "square.grid.2x2")
            }
            Spacer()
            HoverButton(shortcut: KeyboardShortcut("q", modifiers: .command), action: actions.quit) {
                footerLabel("Quit", symbol: "power")
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }

    /// A footer button's icon and title.
    private func footerLabel(_ title: String, symbol: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 12))
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
    }
}
