import SwiftUI

enum Page: String, CaseIterable, Identifiable {
    case overview, cleanup, uninstall, optimize, storage, privacy, activity, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .cleanup: "Cleanup"
        case .uninstall: "Uninstaller"
        case .optimize: "Speed Up"
        case .storage: "Storage"
        case .privacy: "Privacy"
        case .activity: "Activity"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "circle.hexagongrid"
        case .cleanup: "sparkles"
        case .uninstall: "trash"
        case .optimize: "bolt"
        case .storage: "square.grid.3x3.square"
        case .privacy: "hand.raised"
        case .activity: "clock.arrow.circlepath"
        case .settings: "slider.horizontal.3"
        }
    }

    var glow: Glow {
        switch self {
        case .overview, .activity: .violet
        case .cleanup: .magenta
        case .uninstall, .privacy: .ember
        case .optimize, .settings: .sage
        case .storage: .blue
        }
    }

    var subtitle: String {
        switch self {
        case .overview: "Live health of this Mac"
        case .cleanup: "Caches, logs and leftovers of removed apps"
        case .uninstall: "Remove apps with everything they left behind"
        case .optimize: "Refresh system caches and services"
        case .storage: "See what takes the space and clean it up"
        case .privacy: "Apple Intelligence, telemetry, and the settings macOS hides"
        case .activity: "Everything Widmut changed, newest first"
        case .settings: "Protection rules, Touch ID, deleted apps"
        }
    }

    var shortcut: KeyEquivalent {
        let keys: [Page: Character] = [.overview: "1", .cleanup: "2", .uninstall: "3", .optimize: "4",
                                       .storage: "5", .privacy: "6", .activity: "7", .settings: ","]
        return KeyEquivalent(keys[self] ?? "1")
    }
}

/// Shared state: navigation, the running Mole session and the last scan of each tool.
@MainActor
final class AppModel: ObservableObject {
    /// Set by the menu bar card: the Clean page asks to clean once it is on screen. A time, so a
    /// request the page never saw expires instead of asking hours later.
    @Published var askCleanAt: Date?
    /// `-startPage clean` on the command line opens a page directly (handy for screenshots).
    @Published var page = Page(rawValue: UserDefaults.standard.string(forKey: "startPage") ?? "") ?? .overview
    @Published var session: MoleSession?
    /// Pages with work in progress, marked in the sidebar.
    @Published private(set) var busy = Set<Page>()

    let clean = Scan(["clean", "--dry-run"], parse: SectionReport.parse)
    let optimize = Scan(["optimize", "--dry-run"], parse: SectionReport.parse)
    let apps = AppCatalog()
    let diskMap = DiskMap()
    let leftovers = LeftoverStore()
    /// The privacy switches and their undo history, kept while the app runs.
    let privacy = PrivacyStore()
    /// Offers the leftovers of an app the moment it is deleted.
    private(set) lazy var removals = RemovalWatcher(store: leftovers)
    /// Lives here, not on the page, so the last numbers are on screen at once on every visit.
    let status = StatusMonitor()

    init() {
        clean.onBusyChange = { [weak self] in self?.mark(.cleanup, $0) }
        optimize.onBusyChange = { [weak self] in self?.mark(.optimize, $0) }
        leftovers.onBusyChange = { [weak self] in self?.mark(.uninstall, $0) }
        diskMap.onBusyChange = { [weak self] in self?.mark(.storage, $0) }
        Task {
            await leftovers.load()
            await refreshStale()
        }
        if !Self.reviewMode {
            removals.start()
        }
        // A window left open for days still gets fresh results when the user comes back to it.
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil,
                                               queue: .main) { [weak self] _ in
            _ = MainActor.assumeIsolated { Task { await self?.refreshStale() } }
        }
    }

    private var refreshing = false

    /// Review snapshots, the demo tour and replayed runs show what is cached; they never start Mole.
    nonisolated static var reviewMode: Bool {
        ["snapshot", "tour", "replayRun", "scanPreview"].contains { UserDefaults.standard.string(forKey: $0) != nil }
    }

    /// Last results come from the cache at once. In the background, one at a time so the Mac
    /// stays responsive, anything missing or older than a few hours is checked again: quick
    /// scans first, the slow walk (Storage) last. Pages never re-scan on their own; the Rescan
    /// buttons do.
    func refreshStale() async {
        guard !refreshing, !Self.reviewMode else { return }
        refreshing = true
        defer { refreshing = false }
        await leftovers.refreshIfAppsChanged()
        await optimize.refreshIfStale()
        await apps.refreshIfStale()
        await clean.refreshIfStale()
        await diskMap.refreshIfStale()
    }

    private func mark(_ page: Page, _ on: Bool) {
        if on { busy.insert(page) } else { busy.remove(page) }
    }

    /// Starts a Mole command in the run sheet. `onFinish` runs after the user closes the sheet.
    func run(_ title: String, _ args: [String], plan: Int64? = nil, responders: [MoleSession.Responder] = [],
             onFinish: (() -> Void)? = nil) {
        guard session == nil else { return }
        let s = MoleSession(title: title, args: args, plan: plan, responders: responders)
        finishHandler = onFinish
        session = s
        s.start()
    }

    /// `-replayRun <transcript>`: the run sheet plays a recorded Mole run; Mole never starts.
    func replay(_ title: String, transcript: String, plan: Int64?, pace: Double = 0.45) {
        guard session == nil else { return }
        let s = MoleSession(title: title, args: [], plan: plan)
        session = s
        s.replay(transcript, pace: pace)
    }

    private var finishHandler: (() -> Void)?

    /// Closes the run sheet; `sessionDismissed` follows once it is gone.
    func closeSession() { session = nil }

    /// Runs once the sheet is gone, however it was closed.
    func sessionDismissed() {
        let handler = finishHandler
        finishHandler = nil
        handler?()
    }
}
