import SwiftUI

/// Squarified treemap layout (Bruls, Huizing, van Wijk): rectangles close to squares.
enum Treemap {
    static func layout(_ values: [Double], in rect: CGRect) -> [CGRect] {
        let total = values.reduce(0, +)
        guard total > 0, rect.width > 0, rect.height > 0 else { return values.map { _ in .zero } }
        let scale = rect.width * rect.height / total
        var areas = values.map { $0 * scale }[...]
        var out: [CGRect] = []
        var free = rect
        var row: [Double] = []
        while let next = areas.first {
            let side = min(free.width, free.height)
            if row.isEmpty || worst(row + [next], side) <= worst(row, side) {
                row.append(next)
                areas.removeFirst()
            } else {
                out += place(row, in: &free)
                row = []
            }
        }
        if !row.isEmpty { out += place(row, in: &free) }
        return out
    }

    private static func worst(_ row: [Double], _ side: Double) -> Double {
        let s = row.reduce(0, +)
        guard let mx = row.max(), let mn = row.min(), s > 0, mn > 0 else { return .infinity }
        return max(side * side * mx / (s * s), s * s / (side * side * mn))
    }

    private static func place(_ row: [Double], in free: inout CGRect) -> [CGRect] {
        let s = row.reduce(0, +)
        var rects: [CGRect] = []
        if free.width >= free.height {
            let w = s / free.height
            var y = free.minY
            for a in row { let h = a / w; rects.append(CGRect(x: free.minX, y: y, width: w, height: h)); y += h }
            free = CGRect(x: free.minX + w, y: free.minY, width: free.width - w, height: free.height)
        } else {
            let h = s / free.width
            var x = free.minX
            for a in row { let w = a / h; rects.append(CGRect(x: x, y: free.minY, width: w, height: h)); x += w }
            free = CGRect(x: free.minX, y: free.minY + h, width: free.width, height: free.height - h)
        }
        return rects
    }
}

/// Mole's size map of one folder at a time, with a trail for drilling down and back. Every
/// folder measured this session is remembered, so going back is instant; the whole-Mac map is
/// also kept between launches. Rescan (`reload`) is the only way to re-measure.
@MainActor
final class DiskMap: ObservableObject {
    @Published var trail: [String] = []
    @Published var result: AnalyzeResult?
    @Published var loading = false
    @Published var error: String?
    @Published private(set) var startedAt = Date()
    /// When the folder on screen was measured.
    @Published private(set) var measuredAt: Date?
    /// The folder `result` belongs to ("" for the whole Mac).
    private var resultKey: String?
    /// Measuring again the folder already on screen: the old map stays, dimmed, meanwhile.
    var remeasuring: Bool { loading && result != nil && resultKey == (current ?? "") }
    var onBusyChange: ((Bool) -> Void)?
    private var task: Task<Void, Never>?
    /// Bumped by every measure; an old one finishing must not clear a newer one's state.
    private var run = 0
    private var measured: [String: (result: AnalyzeResult, at: Date)] = [:]
    private static let wholeMacKey = "analyze --json"
    private var lastAttempt: Date?

    var current: String? { trail.last }

    init() {
        if let saved = ResultCache.load(Self.wholeMacKey), let r = try? Mole.decode(AnalyzeResult.self, from: saved.data) {
            measured[""] = (r, saved.date)
        }
    }

    /// Maps `path` below the current trail; `nil` maps the whole Mac.
    func open(_ path: String?) {
        if let path { trail.append(path) } else { trail = [] }
        show()
    }

    /// Starts a fresh trail at a top-level place.
    func jump(to path: String?) {
        trail = path.map { [$0] } ?? []
        show()
    }

    func back(to index: Int) {
        trail = Array(trail.prefix(index + 1))
        show()
    }

    /// Shows the current folder: the remembered map when there is one, else measures it.
    func show() {
        guard let hit = measured[current ?? ""] else { return reload() }
        if task != nil { stop() }
        result = hit.result
        resultKey = current ?? ""
        measuredAt = hit.at
        error = nil
    }

    /// Measures the whole Mac in the background when its map is missing or old, while the
    /// whole-Mac view is on screen. It runs like Rescan (progress, sidebar dot, ⌘R does not start
    /// a second one); deeper in a folder it waits for the next return to the app.
    func refreshIfStale() async {
        guard task == nil, trail.isEmpty, ResultCache.isStale(measured[""]?.at), ResultCache.isStale(lastAttempt) else { return }
        let started = Date()
        reload()
        await task?.value
        // Navigating away cancels it; then it is tried again on the next return to the app.
        if error != nil || !ResultCache.isStale(measured[""]?.at) { lastAttempt = started }
    }

    /// Everything measured is out of date after something was trashed; the current folder is measured again.
    func forgetAndReload() {
        measured.removeAll()
        ResultCache.markStale(Self.wholeMacKey)
        reload()
    }

    /// Measures the current folder. A newer request replaces an older one still measuring.
    func reload() {
        task?.cancel()
        run += 1
        let current = run
        let key = self.current ?? ""
        let args = ["analyze", "--json"] + (self.current.map { [$0] } ?? [])
        loading = true
        error = nil
        startedAt = Date()
        onBusyChange?(true)
        task = Task {
            do {
                let data = try await Mole.capture(args)
                let r = try Mole.decode(AnalyzeResult.self, from: data)
                guard !Task.isCancelled, run == current else { return }
                remember(r, data: data, for: key)
                result = r
                resultKey = key
                measuredAt = Date()
            } catch {
                guard !Task.isCancelled, run == current else { return }
                result = nil
                self.error = error.localizedDescription
            }
            task = nil
            loading = false
            onBusyChange?(false)
        }
    }

    private func stop() {
        run += 1
        task?.cancel()
        task = nil
        loading = false
        onBusyChange?(false)
    }

    private func remember(_ r: AnalyzeResult, data: Data, for key: String) {
        measured[key] = (r, Date())
        if key.isEmpty { ResultCache.save(data, as: Self.wholeMacKey) }
    }
}

/// Which Disk Map items may be moved to the Trash. Only a real item directly inside the folder
/// being mapped, inside the home folder, and never one of the folders macOS and apps rely on.
enum TrashPolicy {
    /// Inside ~/Library only these hold disposable things (caches, logs, app data the user may
    /// prune); everything else there (Keychains, Mail, Messages, Containers, iCloud Drive,
    /// CloudStorage, Accounts…) is never offered.
    static let libraryAllowed: Set<String> = ["Caches", "Logs", "Application Support", "Developer"]
    /// Folders whose direct children belong to tools and apps: only one level further down.
    static let toolFolders: Set<String> = [".config", ".local", ".cache"]
    /// Never touched at any depth, wherever they appear.
    static let never: Set<String> = [".ssh", ".gnupg", ".Trash", "Keychains", "Mobile Documents", "CloudStorage",
                                     "Mail", "Messages", "Containers", "Group Containers", "Accounts"]
    /// Personal data and sync state in ~/Library/Application Support: contacts, iPhone backups,
    /// call history, iCloud/File Provider sync, Siri knowledge. Apple's own `com.apple.*` too.
    static let appSupportNever: Set<String> = ["AddressBook", "FileProvider", "MobileSync", "CallHistoryDB",
                                               "CallHistoryTransactions", "Knowledge", "CloudDocs", "iCloud",
                                               "Dock", "DifferentialPrivacy", "Photos", "Calendars"]

    static func allows(_ path: String, inside current: String?, home: String) -> Bool {
        guard let current else { return false } // the whole-Mac tour lists summaries, not items
        let expPath = (path as NSString).expandingTildeInPath
        let expCurrent = (current as NSString).expandingTildeInPath
        let expHome = (home as NSString).expandingTildeInPath
        let item = URL(fileURLWithPath: expPath).standardizedFileURL
        let folder = URL(fileURLWithPath: expCurrent).standardizedFileURL
        let homeURL = URL(fileURLWithPath: expHome).standardizedFileURL
        // Directly inside the mapped folder (Mole lists its children), and inside the home folder.
        guard item.deletingLastPathComponent().path == folder.path,
              item.path.hasPrefix(homeURL.path + "/") else { return false }
        let inHome = Array(item.pathComponents.dropFirst(homeURL.pathComponents.count))
        // Top-level home folders (Documents, Downloads, Projects…) hold everything else.
        guard inHome.count >= 2, inHome.allSatisfy({ !never.contains($0) }) else { return false }
        if inHome[0] == "Library" {
            if inHome[1] == "Application Support",
               inHome.dropFirst(2).contains(where: { appSupportNever.contains($0) || $0.hasPrefix("com.apple.") }) { return false }
            return libraryAllowed.contains(inHome[1]) && inHome.count >= 3
        }
        return !toolFolders.contains(inHome[0]) || inHome.count >= 3
    }

    /// Checks if a safe insight cache, simulator, or leftover folder can be moved to Trash.
    static func allowsInsight(_ path: String, home: String) -> Bool {
        let expanded = (path as NSString).expandingTildeInPath
        let item = URL(fileURLWithPath: expanded).standardizedFileURL
        let homeURL = URL(fileURLWithPath: home).standardizedFileURL
        guard item.path.hasPrefix(homeURL.path + "/") else { return false }
        if item.path == homeURL.path || item.path == homeURL.appendingPathComponent("Downloads").path { return false }
        let inHome = Array(item.pathComponents.dropFirst(homeURL.pathComponents.count))
        guard inHome.count >= 2, inHome.allSatisfy({ !never.contains($0) }) else { return false }
        if inHome[0] == "Library" {
            if inHome.count >= 2 && inHome[1] == "Application Support",
               inHome.dropFirst(2).contains(where: { appSupportNever.contains($0) || $0.hasPrefix("com.apple.") }) { return false }
            return inHome.count >= 2 && libraryAllowed.contains(inHome[1])
        }
        return true
    }
}

/// One treemap tile: a real entry, or the folded "N more" tile.
struct MapTile: Identifiable {
    let id: String
    let name: String
    let size: Int64
    let entry: AnalyzeResult.Entry?
}

struct AnalyzePage: View {
    @ObservedObject var map: DiskMap
    @ViewState private var confirm: ConfirmAction?
    @ViewState private var hovered: String?
    @ViewState private var trashError: String?
    @ViewState private var selectedPaths: Set<String> = []

    private let places: [(String, String?)] = [
        ("Whole Mac", nil), ("Home", "~"), ("Downloads", "~/Downloads"), ("Documents", "~/Documents"),
        ("Library", "~/Library"), ("Applications", "/Applications"), ("Drives", "/Volumes"),
    ]

    private var entries: [AnalyzeResult.Entry] {
        (map.result?.entries ?? []).filter { $0.size > 0 }.sorted { $0.size > $1.size }
    }

    /// The whole-Mac tour: overlapping places and summaries, shown as lists, never as one map.
    private var isOverview: Bool { map.result?.overview ?? false }

    /// Treemap tiles: everything at least 1.5% of the folder, the rest folded into one "Other" tile.
    private var tiles: [MapTile] {
        let total = entries.map(\.size).reduce(0, +)
        let big = entries.prefix(28).filter { Double($0.size) >= Double(total) * 0.015 }
        let rest = entries.dropFirst(big.count)
        var out = big.map { MapTile(id: $0.id, name: $0.name, size: $0.size, entry: $0) }
        if !rest.isEmpty {
            out.append(MapTile(id: "other", name: "\(rest.count) more", size: rest.map(\.size).reduce(0, +), entry: nil))
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 10) {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(places, id: \.0) { place in
                            let path = place.1.map { ($0 as NSString).expandingTildeInPath }
                            let active = map.trail.first == path || (path == nil && map.trail.isEmpty)
                            Button(place.0) { map.jump(to: path) }
                                .buttonStyle(active ? .pill : .pillSecondary)
                                .accessibilityAddTraits(active ? .isSelected : [])
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .scrollIndicators(.never)
                // A soft trailing edge shows there is more to scroll when the window is narrow.
                .mask(LinearGradient(stops: [.init(color: .black, location: 0),
                                             .init(color: .black, location: 0.94), .init(color: .clear, location: 1)],
                                     startPoint: .leading, endPoint: .trailing))
                CircleIconButton(symbol: "folder", help: "Map another folder…") { choose() }
            }

            breadcrumb

            if let trashError {
                Label(trashError, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12.5)).foregroundStyle(Theme.danger)
                    .transition(.blurFade)
            }

            if isOverview, !map.loading || map.remeasuring, map.error == nil {
                overview.opacity(map.remeasuring ? 0.5 : 1).animation(Motion.quick, value: map.remeasuring)
            } else {
                GlowCard(glow: .blue, style: .plain, padding: 10) {
                    GeometryReader { geo in
                        // Nothing under the veil: the previous folder (or the whole-Mac tour) would
                        // show through as the wrong map.
                        let tiles = map.loading && !map.remeasuring ? [] : tiles
                        let rects = Treemap.layout(tiles.map { Double($0.size) }, in: CGRect(origin: .zero, size: geo.size))
                        ZStack(alignment: .topLeading) {
                            ForEach(Array(tiles.enumerated()), id: \.element.id) { i, t in
                                tile(t, index: i, rect: rects[i])
                            }
                        }
                    }
                    .animation(Motion.spring, value: tiles.map(\.id))
                    .opacity(map.remeasuring ? 0.5 : 1)
                    .overlay {
                        if map.loading, !map.remeasuring {
                            VStack(spacing: 10) {
                                ProgressView().tint(.white)
                                Text("Widmut is measuring \(currentName)…").font(.system(size: 13, weight: .medium))
                                HStack(spacing: 4) { Text("Large folders take a minute ·"); Elapsed(since: map.startedAt) }.caption()
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.black.opacity(0.55)))
                            .transition(.opacity)
                        } else if let error = map.error {
                            EmptyState(symbol: "exclamationmark.triangle", text: "Widmut could not map \(currentName)", detail: error,
                                       actionTitle: "Try again", action: map.reload)
                        } else if entries.isEmpty {
                            EmptyState(symbol: "square.grid.3x3", text: map.result == nil ? "Pick a place above to map it." : "This folder is empty.")
                        }
                    }
                    .animation(Motion.quick, value: map.loading)
                }
                .frame(height: 460)

                if !entries.isEmpty, !map.loading || map.remeasuring { list }
            }
        }
        .bottomBar(!selectedPaths.isEmpty) { selectionActionBar }
        .confirmation($confirm)
        .onAppear { if map.result == nil, !map.loading, map.error == nil { map.show() } }
        .onChange(of: map.trail) {
            trashError = nil
            selectedPaths.removeAll()
        }
    }

    // MARK: - Whole-Mac overview

    /// "~/Library", but a bare "~" reads as a typo: say what it is.
    private static func placeLabel(_ path: String) -> String {
        let short = (path as NSString).abbreviatingWithTildeInPath
        return short == "~" ? "Your home folder" : short
    }

    private var overview: some View {
        let placesList = entries.filter { !$0.isInsight }
        let insights = entries.filter(\.isInsight)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let cleanableInsights = insights.filter {
            $0.size > 0 &&
            (TrashPolicy.allowsInsight($0.path, home: home) || $0.cleanable == true) &&
            !$0.name.contains("Old Downloads")
        }
        let totalCleanable = cleanableInsights.map(\.size).reduce(0, +)

        return VStack(alignment: .leading, spacing: 18) {
            // An even grid: three across for 3 or 6 places, otherwise two.
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: placesList.count % 3 == 0 ? 3 : 2),
                      spacing: 14) {
                ForEach(Array(placesList.enumerated()), id: \.element.id) { i, entry in
                    Button { map.open(entry.path) } label: {
                        GlowCard(glow: [Glow.blue, .violet, .magenta, .sage][i % 4], style: .core, padding: 18) {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text(entry.name).cardTitle()
                                    Spacer()
                                    Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .bold)).foregroundStyle(.black)
                                        .frame(width: 26, height: 26).background(Circle().fill(.white))
                                }
                                MetricValue(value: entry.size.metric.value, unit: entry.size.metric.unit, dot: 5)
                                Text(Self.placeLabel(entry.path)).caption().lineLimit(1)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .hoverLift()
                    .contextMenu { menu(for: entry) }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isButton)
                }
            }
            Label("These places overlap (your Home includes your Library and Downloads), so their sizes do not add up.",
                  systemImage: "info.circle").font(.system(size: 12)).foregroundStyle(Theme.secondaryText)

            if !insights.isEmpty {
                GlowCard(glow: .ember, style: .core, padding: 18) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 8) {
                                    Text("Worth a look").cardTitle()
                                    if totalCleanable > 0 {
                                        Tag(text: "\(totalCleanable.bytesText) cleanable", color: Theme.accent)
                                    }
                                }
                                Text("Safe caches, simulators, and developer leftovers you can clean directly to reclaim space.")
                                    .font(.system(size: 11.5)).foregroundStyle(Theme.secondaryText)
                            }
                            Spacer()
                            if totalCleanable > 0 {
                                Button {
                                    confirm = .init(
                                        title: "Clean all safe items?",
                                        message: "This will move \(totalCleanable.bytesText) of safe caches and logs to the Trash. You can recover them from the Trash anytime.",
                                        button: "Clean All (\(totalCleanable.bytesText))"
                                    ) {
                                        cleanAllInsights(cleanableInsights)
                                    }
                                } label: {
                                    Label("Clean All (\(totalCleanable.bytesText))", systemImage: "sparkles")
                                }
                                .buttonStyle(.pill)
                            }
                        }

                        Divider().opacity(0.12)

                        ForEach(insights) { entry in
                            insightRow(entry, home: home)
                        }
                    }
                }
            }
        }
        .transition(.blurFade)
    }

    private func insightRow(_ entry: AnalyzeResult.Entry, home: String) -> some View {
        let isOldDownloads = entry.name.contains("Old Downloads") || entry.path.hasSuffix("/Downloads")
        // Expand tilde so FileManager.fileExists works correctly
        let expandedPath = (entry.path as NSString).expandingTildeInPath
        let pathExists = FileManager.default.fileExists(atPath: expandedPath)
        let canTrash = !isOldDownloads && TrashPolicy.allowsInsight(expandedPath, home: home) && (pathExists || entry.size > 0)
        // Icon: sparkles for backend-confirmed safe, trash.circle for policy-safe, clock for downloads
        let icon = isOldDownloads ? "folder.badge.clock" : ((entry.cleanable == true || canTrash) ? "sparkles" : "eye")

        return HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(isOldDownloads ? Glow.blue.color : Theme.accent)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.name).font(.system(size: 13, weight: .semibold))
                    if canTrash {
                        Tag(text: "Can clean", color: Theme.accent)
                    } else if entry.cleanable == true {
                        Tag(text: "Safe to clean", color: Theme.accent)
                    }
                }
                Text((entry.path as NSString).abbreviatingWithTildeInPath)
                    .font(.system(size: 11)).foregroundStyle(Theme.tertiaryText)
            }

            Spacer()

            Text(entry.size > 0 ? entry.size.bytesText : "–")
                .font(.system(size: 13, weight: .semibold)).monospacedDigit()
                .frame(minWidth: 70, alignment: .trailing)

            HStack(spacing: 8) {
                CircleIconButton(symbol: "folder", help: "Show in Finder") {
                    let revealPath = pathExists ? expandedPath : (entry.path as NSString).expandingTildeInPath
                    NSWorkspace.shared.selectFile(revealPath, inFileViewerRootedAtPath: "")
                }

                if isOldDownloads {
                    Button("Review Downloads") {
                        map.jump(to: entry.path)
                    }
                    .buttonStyle(PillButtonStyle(kind: .secondary, compact: true))
                } else if canTrash {
                    Button("Clean") {
                        confirm = .init(
                            title: "Clean \(entry.name)?",
                            message: "This will move \(entry.size.bytesText) at \((entry.path as NSString).abbreviatingWithTildeInPath) to the Trash. You can restore it from the Trash anytime.",
                            button: "Clean Now"
                        ) {
                            trashPath(expandedPath, name: entry.name)
                        }
                    }
                    .buttonStyle(PillButtonStyle(kind: .primary, compact: true))
                } else if entry.cleanable == true {
                    Button("Clean") {
                        confirm = .init(
                            title: "Clean \(entry.name)?",
                            message: "This will move \(entry.size.bytesText) at \((entry.path as NSString).abbreviatingWithTildeInPath) to the Trash.",
                            button: "Clean Now"
                        ) {
                            trashPath(expandedPath, name: entry.name)
                        }
                    }
                    .buttonStyle(PillButtonStyle(kind: .primary, compact: true))
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(hovered == entry.id ? 0.05 : 0.025)))
        .contentShape(Rectangle())
        .onHover { isHovered in
            hovered = isHovered ? entry.id : (hovered == entry.id ? nil : hovered)
        }
        .onTapGesture {
            if entry.isDirectory { map.open(entry.path) }
        }
        .contextMenu { menu(for: entry) }
        .accessibilityElement(children: .combine)
    }

    /// Used space of the startup volume, the honest total for the whole-Mac view.
    private static var usedOnDisk: Int64? {
        let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
        guard let total = v?.volumeTotalCapacity, let free = v?.volumeAvailableCapacityForImportantUsage else { return nil }
        return Int64(total) - free
    }

    private var currentName: String {
        guard let path = map.current else { return "this Mac" }
        return (path as NSString).lastPathComponent.isEmpty ? path : (path as NSString).lastPathComponent
    }

    private var breadcrumb: some View {
        HStack(spacing: 6) {
            Button("This Mac") { map.jump(to: nil) }.buttonStyle(.plain)
                .foregroundStyle(map.trail.isEmpty ? .white : Theme.secondaryText)
            ForEach(Array(map.trail.enumerated()), id: \.offset) { i, path in
                Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(Theme.tertiaryText)
                Button((path as NSString).lastPathComponent.isEmpty ? path : (path as NSString).lastPathComponent) {
                    map.back(to: i)
                }
                .buttonStyle(.plain)
                .foregroundStyle(i == map.trail.count - 1 ? .white : Theme.secondaryText)
            }
            Spacer()
            if map.remeasuring {
                ScanningBadge(started: map.startedAt)
                Text("·").foregroundStyle(Theme.tertiaryText)
            } else if let at = map.measuredAt, !map.loading {
                CheckedAgo(date: at)
                Button("Rescan") { map.reload() }.buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                    .keyboardShortcut("r", modifiers: .command)
                    .help("Measure this folder again (⌘R)")
                Text("·").foregroundStyle(Theme.tertiaryText)
            }
            if isOverview {
                if let used = Self.usedOnDisk { Text("\(used.bytesText) used on this Mac").font(.system(size: 13, weight: .semibold)) }
            } else if let total = map.result?.entries?.map(\.size).reduce(0, +), total > 0 {
                Text(total.bytesText).font(.system(size: 13, weight: .semibold))
            }
        }
        .font(.system(size: 13))
    }

    private func tile(_ t: MapTile, index: Int, rect: CGRect) -> some View {
        let glow = t.entry == nil ? Glow.graphite : [Glow.blue, .violet, .magenta, .ember, .sage][index % 5]
        let big = rect.width > 90 && rect.height > 50
        let medium = rect.width > 56 && rect.height > 30
        return Button {
            if let e = t.entry, e.isDirectory { map.open(e.path) }
        } label: {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(RadialGradient(colors: [glow.color.opacity(hovered == t.id ? 0.95 : 0.7), glow.color.opacity(0.18)],
                                         center: .bottomTrailing, startRadius: 0, endRadius: max(rect.width, rect.height)))
                RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(hovered == t.id ? 0.4 : 0.14))
                if big {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.name).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                        Text(t.size.bytesText).font(.system(size: 11)).foregroundStyle(.white.opacity(0.75))
                    }
                    .padding(10)
                } else if medium {
                    Text(t.name).font(.system(size: 10.5, weight: .medium)).lineLimit(1).padding(7)
                }
            }
        }
        .buttonStyle(.plain)
        .frame(width: max(rect.width - 4, 0), height: max(rect.height - 4, 0))
        .offset(x: rect.minX + 2, y: rect.minY + 2)
        .onHover { hovered = $0 ? t.id : (hovered == t.id ? nil : hovered) }
        .animation(Motion.quick, value: hovered == t.id)
        .help("\(t.name) — \(t.size.bytesText)")
        .contextMenu { if let e = t.entry { menu(for: e) } }
        .accessibilityLabel("\(t.name), \(t.size.bytesText)")
    }

    private var list: some View {
        let top = Double(entries.first?.size ?? 1)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let trashableEntries = entries.filter {
            let expPath = ($0.path as NSString).expandingTildeInPath
            return TrashPolicy.allows(expPath, inside: map.current, home: home) && (FileManager.default.fileExists(atPath: expPath) || $0.size > 0)
        }

        return GlowCard(glow: .graphite, style: .plain, padding: 18) {
            VStack(spacing: 8) {
                // Header row with select-all
                HStack(spacing: 12) {
                    if !trashableEntries.isEmpty {
                        Button {
                            if selectedPaths.count == trashableEntries.count {
                                selectedPaths.removeAll()
                            } else {
                                selectedPaths = Set(trashableEntries.map(\.path))
                            }
                        } label: {
                            Image(systemName: selectedPaths.count == trashableEntries.count && !trashableEntries.isEmpty ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 14))
                                .foregroundStyle(selectedPaths.isEmpty ? Theme.tertiaryText : Theme.accent)
                        }
                        .buttonStyle(.plain)
                        .help(selectedPaths.count == trashableEntries.count ? "Deselect all" : "Select all trashable items")
                    }

                    Text("Files and Folders").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.secondaryText)
                    Spacer()
                    Text("Size").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.secondaryText).frame(width: 84, alignment: .trailing)
                    Text("Actions").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.secondaryText).frame(width: 68, alignment: .center)
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 4)

                Divider().opacity(0.12)

                ForEach(entries.prefix(60)) { entry in
                    entryRow(entry, top: top, home: home)
                }
            }
        }
    }

    private func entryRow(_ entry: AnalyzeResult.Entry, top: Double, home: String) -> some View {
        let expPath = (entry.path as NSString).expandingTildeInPath
        let canTrash = TrashPolicy.allows(expPath, inside: map.current, home: home) && (FileManager.default.fileExists(atPath: expPath) || entry.size > 0)
        let isSelected = selectedPaths.contains(entry.path)

        return HStack(spacing: 12) {
            if canTrash {
                Button {
                    if isSelected {
                        selectedPaths.remove(entry.path)
                    } else {
                        selectedPaths.insert(entry.path)
                    }
                } label: {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14))
                        .foregroundStyle(isSelected ? Theme.accent : Theme.tertiaryText)
                }
                .buttonStyle(.plain)
            } else {
                Image(systemName: "lock")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.tertiaryText.opacity(0.4))
                    .frame(width: 14)
            }

            Image(systemName: entry.isDirectory ? "folder.fill" : "doc.fill")
                .foregroundStyle(entry.isDirectory ? Glow.blue.color : Theme.secondaryText)
                .frame(width: 18)

            Text(entry.name)
                .font(.system(size: 13, weight: entry.isDirectory ? .medium : .regular))
                .lineLimit(1)

            Spacer()

            DotMeter(value: Double(entry.size) / top, count: 20, color: Glow.blue.color)

            Text(entry.size.bytesText)
                .font(.system(size: 12.5))
                .monospacedDigit()
                .frame(width: 84, alignment: .trailing)

            HStack(spacing: 6) {
                CircleIconButton(symbol: "folder", help: "Show in Finder") {
                    let reveal = FileManager.default.fileExists(atPath: expPath) ? expPath : entry.path
                    NSWorkspace.shared.selectFile(reveal, inFileViewerRootedAtPath: "")
                }

                if canTrash {
                    CircleIconButton(symbol: "trash", help: "Move to Trash") {
                        confirm = .init(
                            title: "Move \(entry.name) to the Trash?",
                            message: "\(entry.size.bytesText) at \((entry.path as NSString).abbreviatingWithTildeInPath). You can restore it from the Trash.",
                            button: "Move to Trash"
                        ) {
                            trashPath(entry.path, name: entry.name)
                        }
                    }
                } else {
                    Spacer().frame(width: 26)
                }
            }
            .frame(width: 68)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(isSelected ? Theme.accent.opacity(0.08) : Color.white.opacity(hovered == entry.id ? 0.04 : 0)))
        .contentShape(Rectangle())
        .onHover { isHovered in
            hovered = isHovered ? entry.id : (hovered == entry.id ? nil : hovered)
        }
        .onTapGesture {
            if entry.isDirectory {
                selectedPaths.removeAll()
                map.open(entry.path)
            }
        }
        .contextMenu { menu(for: entry) }
    }

    private var selectionActionBar: some View {
        let selectedEntries = entries.filter { selectedPaths.contains($0.path) }
        let totalSelectedBytes = selectedEntries.map(\.size).reduce(0, +)

        return SelectionBar(
            glow: .ember,
            title: "\(selectedPaths.count) selected · \(totalSelectedBytes.bytesText)",
            subtitle: selectedEntries.prefix(3).map(\.name).joined(separator: ", ") + (selectedEntries.count > 3 ? "…" : ""),
            clear: { selectedPaths.removeAll() }
        ) {
            Button("Move to Trash (\(totalSelectedBytes.bytesText))") {
                confirm = .init(
                    title: "Move \(selectedPaths.count) item\(selectedPaths.count == 1 ? "" : "s") to the Trash?",
                    message: "\(totalSelectedBytes.bytesText) total. You can restore them from the Trash anytime.",
                    button: "Move to Trash"
                ) {
                    let paths = Array(selectedPaths).map { ($0 as NSString).expandingTildeInPath }
                    let failed = Trash.move(paths)
                    selectedPaths.removeAll()
                    if !failed.isEmpty {
                        withAnimation(Motion.quick) {
                            trashError = "\(failed.count) item(s) could not be moved to the Trash."
                        }
                    } else {
                        trashError = nil
                    }
                    map.forgetAndReload()
                }
            }
            .buttonStyle(.pill)
        }
    }

    private func cleanAllInsights(_ list: [AnalyzeResult.Entry]) {
        let paths = list.map { ($0.path as NSString).expandingTildeInPath }
            .filter { FileManager.default.fileExists(atPath: $0) || true }
        guard !paths.isEmpty else { return }
        let failed = Trash.move(paths)
        if !failed.isEmpty {
            withAnimation(Motion.quick) {
                trashError = "\(failed.count) item(s) could not be moved to the Trash."
            }
        } else {
            trashError = nil
        }
        map.forgetAndReload()
    }

    private func trashPath(_ path: String, name: String) {
        let expPath = (path as NSString).expandingTildeInPath
        let failed = Trash.move([expPath])
        if failed.isEmpty {
            trashError = nil
            selectedPaths.remove(path)
            selectedPaths.remove(expPath)
            map.forgetAndReload()
        } else {
            withAnimation(Motion.quick) {
                trashError = "\(name) could not be moved to the Trash. It may belong to macOS or another process."
            }
        }
    }

    @ViewBuilder private func menu(for entry: AnalyzeResult.Entry) -> some View {
        let expPath = (entry.path as NSString).expandingTildeInPath
        if entry.isDirectory { Button("Open") { map.open(entry.path) } }
        Button("Show in Finder") {
            let reveal = FileManager.default.fileExists(atPath: expPath) ? expPath : entry.path
            NSWorkspace.shared.selectFile(reveal, inFileViewerRootedAtPath: "")
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let canTrash = (TrashPolicy.allows(expPath, inside: map.current, home: home) ||
                        (isOverview && entry.isInsight && TrashPolicy.allowsInsight(expPath, home: home))) &&
                       (FileManager.default.fileExists(atPath: expPath) || entry.size > 0) &&
                       !entry.name.contains("Old Downloads")
        if canTrash {
            Divider()
            Button("Move to Trash…", role: .destructive) {
                confirm = .init(title: "Move \(entry.name) to the Trash?",
                                message: "\(entry.size.bytesText) at \((entry.path as NSString).abbreviatingWithTildeInPath). You can restore it from the Trash.",
                                button: "Move to Trash") {
                    trashPath(entry.path, name: entry.name)
                }
            }
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url { map.jump(to: url.path) }
    }
}
