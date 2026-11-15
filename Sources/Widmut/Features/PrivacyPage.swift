import Foundation
import SwiftUI
import UAF

// MARK: - Preferences

/// A preference value a privacy tweak writes.
enum PlistValue: Equatable, Codable {
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)

    /// The value as CoreFoundation stores it; a Bool becomes a real CFBoolean, not 1.
    var object: AnyObject {
        switch self {
        case .bool(let v): NSNumber(value: v)
        case .int(let v): NSNumber(value: v)
        case .double(let v): NSNumber(value: v)
        case .string(let v): v as NSString
        }
    }

    /// A stored value, or nil for types these tweaks never write.
    init?(_ any: Any?) {
        guard let any else { return nil }
        if let s = any as? String {
            self = .string(s)
        } else if let n = any as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() {
                self = .bool(n.boolValue)
            } else if CFNumberIsFloatType(n) {
                self = .double(n.doubleValue)
            } else {
                self = .int(n.intValue)
            }
        } else {
            return nil
        }
    }

    /// Whether a stored value means the same thing. Booleans and 0/1 are interchangeable,
    /// because `-bool true` and `-int 1` both end up in preferences.
    func matches(_ stored: Any?) -> Bool {
        guard let other = PlistValue(stored) else { return false }
        switch (self, other) {
        case (.bool(let a), .int(let b)), (.int(let b), .bool(let a)): return (b != 0) == a
        case (.double(let a), .int(let b)), (.int(let b), .double(let a)): return a == Double(b)
        default: return self == other
        }
    }

    /// The value as `defaults write` spells it, for the preview.
    var command: (type: String, value: String) {
        switch self {
        case .bool(let v): ("-bool", v ? "true" : "false")
        case .int(let v): ("-int", String(v))
        case .double(let v): ("-float", String(v))
        case .string(let v): ("-string", "\"\(v)\"")
        }
    }
}

/// User preferences, read and written through cfprefsd the way `defaults` does, so no shell
/// is involved and no quoting can go wrong.
enum Prefs {
    static let global = "NSGlobalDomain"

    private static func appID(_ domain: String) -> CFString {
        domain == global || domain == ".GlobalPreferences" ? kCFPreferencesAnyApplication : domain as CFString
    }

    private static func host(_ currentHost: Bool) -> CFString {
        currentHost ? kCFPreferencesCurrentHost : kCFPreferencesAnyHost
    }

    /// The user's own value, ignoring anything an administrator forced with a profile.
    static func userValue(_ domain: String, _ key: String, currentHost: Bool = false) -> Any? {
        CFPreferencesSynchronize(appID(domain), kCFPreferencesCurrentUser, host(currentHost))
        return CFPreferencesCopyValue(key as CFString, appID(domain), kCFPreferencesCurrentUser, host(currentHost))
    }

    /// Writes the user's value; nil removes the key so macOS's own default applies again.
    @discardableResult
    static func write(_ domain: String, _ key: String, _ value: PlistValue?, currentHost: Bool = false) -> Bool {
        CFPreferencesSetValue(key as CFString, value?.object, appID(domain), kCFPreferencesCurrentUser, host(currentHost))
        return CFPreferencesSynchronize(appID(domain), kCFPreferencesCurrentUser, host(currentHost))
    }
}

// MARK: - Catalog

/// One preference a tweak changes.
struct PrivacyChange: Equatable {
    let domain: String
    let key: String
    let value: PlistValue
    var currentHost = false

    /// The journal's key. Two tweaks never change the same preference.
    var journalKey: String { "\(domain):\(key)" + (currentHost ? ":host" : "") }

    /// The equivalent `defaults` command, shown before anything changes.
    var command: String {
        let (type, value) = value.command
        return "defaults\(currentHost ? " -currentHost" : "") write \(domain) \"\(key)\" \(type) \(value)"
    }
}

enum PrivacyGroup: String, CaseIterable, Identifiable {
    case privacy, annoyances, finder, dock, typing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .privacy: "Privacy"
        case .annoyances: "Annoyances"
        case .finder: "Finder"
        case .dock: "Dock and windows"
        case .typing: "Typing"
        }
    }

    var symbol: String {
        switch self {
        case .privacy: "hand.raised"
        case .annoyances: "bell.slash"
        case .finder: "folder"
        case .dock: "dock.rectangle"
        case .typing: "keyboard"
        }
    }

    var summary: String {
        switch self {
        case .privacy: "Stop Siri and Look Up sending what you say and select to Apple."
        case .annoyances: "The wallpaper click that hides every window, and desktop widgets."
        case .finder: "Show what Finder hides and stop the clutter it leaves behind."
        case .dock: "A quicker Dock without the recents, the delay and the bounce."
        case .typing: "Stop macOS rewriting what you type."
        }
    }

    var glow: Glow {
        switch self {
        case .privacy: .ember
        case .annoyances: .magenta
        case .finder: .violet
        case .dock: .blue
        case .typing: .sage
        }
    }
}

struct PrivacySetting: Identifiable {
    let id: String
    let group: PrivacyGroup
    let title: String
    let detail: String
    var caveat: String?
    let changes: [PrivacyChange]
    /// Apps that read the setting once at launch.
    var restart: [String] = []
    /// The first macOS version (major, minor) that has the setting.
    var since: (Int, Int) = (14, 0)

    var supported: Bool {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return (os.majorVersion, os.minorVersion) >= since
    }

    var commands: [String] { changes.map(\.command) }
}

/// The settings Widmut flips itself. Everything here is a per-user preference, so it needs no
/// administrator password, no configuration profile and no change under /System; the ones that
/// macOS only allows through a profile (Mac Analytics, personalized ads, Spotlight web results,
/// Game Center, Apple Intelligence itself) are deliberately not in this list.
enum PrivacyCatalog {
    static let all: [PrivacySetting] = [
        // MARK: Privacy
        PrivacySetting(
            id: "siri-data-share", group: .privacy, title: "Stop sharing Siri and Dictation recordings",
            detail: "Apple stops storing and reviewing what you say to Siri and dictate.",
            changes: [PrivacyChange(domain: "com.apple.assistant.support", key: "Siri Data Sharing Opt-In Status", value: .int(2))]),
        PrivacySetting(
            id: "search-data-share", group: .privacy, title: "Stop sharing search queries",
            detail: "Apple stops keeping your Spotlight, Safari and Look Up searches to improve search.",
            changes: [PrivacyChange(domain: "com.apple.assistant.support", key: "Search Queries Data Sharing Status", value: .int(2))]),
        PrivacySetting(
            id: "lookup-suggestions", group: .privacy, title: "Stop Look Up sending selected words",
            detail: "Looking a word up stays on this Mac instead of asking Apple for web suggestions.",
            changes: [PrivacyChange(domain: "com.apple.lookup.shared", key: "LookupSuggestionsDisabled", value: .bool(true))]),
        PrivacySetting(
            id: "safari-suggestions", group: .privacy, title: "Stop Safari search suggestions",
            detail: "Safari stops sending what you type in the address bar to your search engine and to Apple.",
            caveat: "The address bar no longer suggests searches as you type.",
            changes: [PrivacyChange(domain: "com.apple.Safari", key: "UniversalSearchEnabled", value: .bool(false)),
                      PrivacyChange(domain: "com.apple.Safari", key: "SuppressSearchSuggestions", value: .bool(true))],
            restart: ["Safari"]),

        // MARK: Annoyances
        PrivacySetting(
            id: "click-to-desktop", group: .annoyances, title: "Stop a wallpaper click hiding every window",
            detail: "A stray click on the desktop no longer sweeps every window off the screen.",
            changes: [PrivacyChange(domain: "com.apple.WindowManager", key: "EnableStandardClickToShowDesktop", value: .bool(false))]),
        PrivacySetting(
            id: "desktop-widgets", group: .annoyances, title: "Hide desktop widgets",
            detail: "Widgets leave the desktop, including in Stage Manager.",
            changes: [PrivacyChange(domain: "com.apple.WindowManager", key: "StandardHideWidgets", value: .bool(true)),
                      PrivacyChange(domain: "com.apple.WindowManager", key: "StageManagerHideWidgets", value: .bool(true))]),

        // MARK: Finder
        PrivacySetting(
            id: "file-extensions", group: .finder, title: "Show file extensions",
            detail: "Every file shows its full name, so a file pretending to be a document is easier to spot.",
            changes: [PrivacyChange(domain: Prefs.global, key: "AppleShowAllExtensions", value: .bool(true))],
            restart: ["Finder"]),
        PrivacySetting(
            id: "path-bar", group: .finder, title: "Show the path bar",
            detail: "Finder windows show where the current folder is, at the bottom.",
            changes: [PrivacyChange(domain: "com.apple.finder", key: "ShowPathbar", value: .bool(true))],
            restart: ["Finder"]),
        PrivacySetting(
            id: "status-bar", group: .finder, title: "Show the status bar",
            detail: "Finder windows show how many items are inside and how much space is left.",
            changes: [PrivacyChange(domain: "com.apple.finder", key: "ShowStatusBar", value: .bool(true))],
            restart: ["Finder"]),
        PrivacySetting(
            id: "folders-first", group: .finder, title: "Keep folders above files",
            detail: "Sorting by name keeps folders together at the top.",
            changes: [PrivacyChange(domain: "com.apple.finder", key: "_FXSortFoldersFirst", value: .bool(true))],
            restart: ["Finder"]),
        PrivacySetting(
            id: "search-this-folder", group: .finder, title: "Search the folder you are in",
            detail: "Finder searches the current folder, not the whole Mac.",
            changes: [PrivacyChange(domain: "com.apple.finder", key: "FXDefaultSearchScope", value: .string("SCcf"))],
            restart: ["Finder"]),
        PrivacySetting(
            id: "extension-warning", group: .finder, title: "Skip the extension change warning",
            detail: "Finder stops asking for confirmation each time a file's extension changes.",
            changes: [PrivacyChange(domain: "com.apple.finder", key: "FXEnableExtensionChangeWarning", value: .bool(false))],
            restart: ["Finder"]),
        PrivacySetting(
            id: "trash-30-days", group: .finder, title: "Empty the Trash after 30 days",
            detail: "Items that sat in the Trash for a month are deleted, so it stops filling the disk.",
            changes: [PrivacyChange(domain: "com.apple.finder", key: "FXRemoveOldTrashItems", value: .bool(true))],
            restart: ["Finder"]),
        PrivacySetting(
            id: "save-locally", group: .finder, title: "Save new documents on this Mac",
            detail: "Save dialogs start on your Mac instead of iCloud Drive.",
            changes: [PrivacyChange(domain: Prefs.global, key: "NSDocumentSaveNewDocumentsToCloud", value: .bool(false))]),
        PrivacySetting(
            id: "network-ds-store", group: .finder, title: "Stop .DS_Store files on network drives",
            detail: "Finder stops leaving hidden .DS_Store files in shared folders on other computers.",
            changes: [PrivacyChange(domain: "com.apple.desktopservices", key: "DSDontWriteNetworkStores", value: .bool(true))]),

        // MARK: Dock and windows
        PrivacySetting(
            id: "dock-recents", group: .dock, title: "Hide recent apps in the Dock",
            detail: "The Dock stops adding the apps you opened lately.",
            changes: [PrivacyChange(domain: "com.apple.dock", key: "show-recents", value: .bool(false))],
            restart: ["Dock"]),
        PrivacySetting(
            id: "dock-delay", group: .dock, title: "Remove the Dock auto-hide delay",
            detail: "A hidden Dock appears at once instead of after half a second.",
            changes: [PrivacyChange(domain: "com.apple.dock", key: "autohide-delay", value: .double(0))],
            restart: ["Dock"]),
        PrivacySetting(
            id: "dock-bounce", group: .dock, title: "Stop Dock icons bouncing",
            detail: "Icons stay still while their app opens.",
            changes: [PrivacyChange(domain: "com.apple.dock", key: "launchanim", value: .bool(false))],
            restart: ["Dock"]),
        PrivacySetting(
            id: "minimize-to-app", group: .dock, title: "Minimize windows into their app icon",
            detail: "Minimized windows tuck into the app's icon instead of filling the Dock.",
            changes: [PrivacyChange(domain: "com.apple.dock", key: "minimize-to-application", value: .bool(true))],
            restart: ["Dock"]),
        PrivacySetting(
            id: "window-animations", group: .dock, title: "Turn off window opening animations",
            detail: "New windows open instantly instead of zooming in.",
            changes: [PrivacyChange(domain: Prefs.global, key: "NSAutomaticWindowAnimationsEnabled", value: .bool(false))]),
        PrivacySetting(
            id: "tile-margins", group: .dock, title: "Remove gaps between tiled windows",
            detail: "Windows tiled to the sides of the screen sit flush.",
            changes: [PrivacyChange(domain: "com.apple.WindowManager", key: "EnableTiledWindowMargins", value: .bool(false))],
            since: (15, 0)),
        PrivacySetting(
            id: "screenshot-shadow", group: .dock, title: "Remove shadows from window screenshots",
            detail: "A window screenshot is taken without the large drop shadow around it.",
            changes: [PrivacyChange(domain: "com.apple.screencapture", key: "disable-shadow", value: .bool(true))],
            restart: ["SystemUIServer"]),

        // MARK: Typing
        PrivacySetting(
            id: "autocorrect", group: .typing, title: "Turn off autocorrect",
            detail: "macOS stops correcting words as you type.",
            changes: [PrivacyChange(domain: Prefs.global, key: "NSAutomaticSpellingCorrectionEnabled", value: .bool(false))]),
        PrivacySetting(
            id: "smart-punctuation", group: .typing, title: "Turn off smart quotes and dashes",
            detail: "Straight quotes and double hyphens stay as you typed them, which code and terminals need.",
            changes: [PrivacyChange(domain: Prefs.global, key: "NSAutomaticQuoteSubstitutionEnabled", value: .bool(false)),
                      PrivacyChange(domain: Prefs.global, key: "NSAutomaticDashSubstitutionEnabled", value: .bool(false))]),
        PrivacySetting(
            id: "double-space-period", group: .typing, title: "Turn off the period on two spaces",
            detail: "Two spaces stay two spaces.",
            changes: [PrivacyChange(domain: Prefs.global, key: "NSAutomaticPeriodSubstitutionEnabled", value: .bool(false))]),
        PrivacySetting(
            id: "auto-capitalize", group: .typing, title: "Turn off automatic capitals",
            detail: "macOS stops capitalizing the first word of every sentence.",
            changes: [PrivacyChange(domain: Prefs.global, key: "NSAutomaticCapitalizationEnabled", value: .bool(false))]),
        PrivacySetting(
            id: "key-repeat", group: .typing, title: "Repeat held keys instead of showing accents",
            detail: "Holding a key repeats it, as on a PC, instead of opening the accent menu.",
            caveat: "Type accents with Option shortcuts or the Character Viewer instead.",
            changes: [PrivacyChange(domain: Prefs.global, key: "ApplePressAndHoldEnabled", value: .bool(false))]),
    ]

    static func setting(_ id: String) -> PrivacySetting? { all.first { $0.id == id } }
}

// MARK: - Journal

/// Every change Widmut made, with the value that was there before it: undo puts back exactly
/// that value, including removing a key that did not exist. Kept in the app's own folder.
@MainActor
final class PrivacyStore: ObservableObject {
    struct Snapshot: Codable {
        var domain: String
        var key: String
        var currentHost: Bool
        var value: PlistValue?
    }

    struct Journal: Codable {
        var previous: [String: Snapshot] = [:]
    }

    @Published private(set) var applied = Set<String>()
    @Published private(set) var mixed = Set<String>()
    @Published private(set) var error: String?
    /// Settings that have an entry in the journal, so their original value can be put back.
    @Published private(set) var restorable = Set<String>()

    let journalURL: URL
    private(set) var journal = Journal()

    init(folder: URL? = nil) {
        let directory = folder ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Widmut", isDirectory: true)
        journalURL = directory.appendingPathComponent("privacy-journal.json")
        load()
        refresh()
    }

    var appliedCount: Int { applied.count }

    /// Reads macOS's own answer for every setting: no cached state to drift.
    func refresh() {
        var on = Set<String>(), partial = Set<String>(), canRestore = Set<String>()
        for setting in PrivacyCatalog.all where setting.supported {
            let matches = setting.changes.map { $0.value.matches(Prefs.userValue($0.domain, $0.key, currentHost: $0.currentHost)) }
            if matches.allSatisfy({ $0 }) {
                on.insert(setting.id)
            } else if matches.contains(true) {
                partial.insert(setting.id)
            }
            if setting.changes.contains(where: { journal.previous[$0.journalKey] != nil }) { canRestore.insert(setting.id) }
        }
        applied = on
        mixed = partial
        restorable = canRestore
    }

    /// Applies one setting, recording the value it replaces first.
    func apply(_ setting: PrivacySetting) {
        error = nil
        for change in setting.changes {
            if journal.previous[change.journalKey] == nil {
                journal.previous[change.journalKey] = Snapshot(
                    domain: change.domain, key: change.key, currentHost: change.currentHost,
                    value: PlistValue(Prefs.userValue(change.domain, change.key, currentHost: change.currentHost)))
            }
            if !Prefs.write(change.domain, change.key, change.value, currentHost: change.currentHost) {
                error = "macOS refused to write \(change.domain) \(change.key)."
            }
        }
        save()
        refresh()
    }

    /// Puts back the value that was there before Widmut changed this setting.
    func undo(_ setting: PrivacySetting) {
        error = nil
        for change in setting.changes {
            guard let snapshot = journal.previous[change.journalKey] else { continue }
            if !Prefs.write(snapshot.domain, snapshot.key, snapshot.value, currentHost: snapshot.currentHost) {
                error = "macOS refused to restore \(snapshot.domain) \(snapshot.key)."
            }
            journal.previous[change.journalKey] = nil
        }
        save()
        refresh()
    }

    /// Undoes everything Widmut ever changed, whatever is still applied.
    func undoEverything() {
        error = nil
        for snapshot in journal.previous.values {
            if !Prefs.write(snapshot.domain, snapshot.key, snapshot.value, currentHost: snapshot.currentHost) {
                error = "macOS refused to restore \(snapshot.domain) \(snapshot.key)."
            }
        }
        journal.previous.removeAll()
        save()
        refresh()
    }

    // MARK: - Disk

    private func load() {
        guard let data = try? Data(contentsOf: journalURL),
              let saved = try? JSONDecoder().decode(Journal.self, from: data) else { return }
        journal = saved
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: journalURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(journal).write(to: journalURL, options: .atomic)
        } catch {
            self.error = "Widmut could not save its undo history: \(error.localizedDescription)"
        }
    }
}

// MARK: - Apple Intelligence

/// The on-device Apple Intelligence models and how much disk they take, plus model purging
/// and configuration profile generation to turn features off and block downloads.
enum AppleIntelligence {
    static let modelFolders = [
        "/System/Library/AssetsV2/com_apple_MobileAsset_UAF_FM_GenerativeModels",
        "/System/Library/AssetsV2/com_apple_MobileAsset_UAF_FM_Visual",
        "/System/Library/AssetsV2/com_apple_MobileAsset_UAF_FM_Overrides",
    ]

    static let modelSets = [
        "com.apple.modelcatalog",
        "com.apple.MobileAsset.UAF.FM.Visual",
        "com.apple.MobileAsset.UAF.FM.CodeLM",
        "com.apple.MobileAsset.UAF.Photos.MagicCleanup",
        "com.apple.MobileAsset.UAF.Photos.SpatialPhotosRelive",
    ]

    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.AppleIntelligence-Settings.extension")!

    /// Total bytes of on-device Apple Intelligence models, using Apple's UnifiedAssetFramework
    /// service first, then falling back to filesystem checks.
    static func modelBytes() -> Int64? {
        let bytes = UAFTotalPresentAssetBytes()
        if bytes > 0 { return bytes }
        let present = modelFolders.filter { FileManager.default.fileExists(atPath: $0) }
        guard !present.isEmpty else { return nil }
        let fbytes = present.map { FolderSize.of($0) }.reduce(0, +)
        return fbytes > 0 ? fbytes : nil
    }

    /// Asks Apple's asset service (com.apple.siri.uaf.subscription.service) via XPC to purge
    /// and reset the downloaded models.
    static func purgeModels(completion: @escaping (Result<Void, Error>) -> Void) {
        guard UAFLoad() else {
            completion(.failure(NSError(domain: "Widmut", code: 1, userInfo: [NSLocalizedDescriptionKey: "Apple Asset Service unavailable"])))
            return
        }
        let sets = UAFAllModelSets()
        let toPurge = sets.isEmpty ? modelSets : sets
        UAFResetAssetSets(toPurge) { error in
            DispatchQueue.main.async {
                if let error {
                    completion(.failure(error))
                } else {
                    completion(.success(()))
                }
            }
        }
    }

    /// Generates a configuration profile (.mobileconfig) that disables Apple Intelligence
    /// system-wide and prevents background daemons from re-downloading model sets.
    static func generateDisableProfile() throws -> URL {
        let identifier = "io.widmut.mac.disableai"
        let downloadDomain = "com.apple.MobileAsset"
        let blockedURL = "https://127.0.0.1:9/widmut-blocked/"

        let restrictions: [String: Any] = [
            "PayloadType": "com.apple.applicationaccess",
            "PayloadVersion": 1,
            "PayloadIdentifier": identifier + ".restrictions",
            "PayloadUUID": UUID().uuidString,
            "PayloadDisplayName": "Apple Intelligence Restrictions",
            "allowAssistant": false,
            "allowWritingTools": false,
            "allowGenmoji": false,
            "allowImagePlayground": false,
            "allowImageWand": false,
            "allowMailSummary": false,
            "allowSafariSummary": false,
            "allowNotesTranscriptionSummary": false,
            "allowVisualIntelligenceSummary": false,
            "allowExternalIntelligenceIntegrations": false,
            "allowExternalIntelligenceIntegrationsSignIn": false,
        ]

        var forcedMobileAsset: [String: Any] = [:]
        let assetTypes = [
            "com.apple.MobileAsset.UAF.FM.GenerativeModels",
            "com.apple.MobileAsset.UAF.FM.Visual",
            "com.apple.MobileAsset.UAF.FM.CodeLM",
            "com.apple.MobileAsset.UAF.Photos.MagicCleanup",
            "com.apple.MobileAsset.UAF.Photos.SpatialPhotosRelive",
        ]
        for t in assetTypes {
            forcedMobileAsset["DownloadServerBaseURLOverride-" + t] = blockedURL
        }

        let preferencesPayload: [String: Any] = [
            "PayloadType": "com.apple.ManagedClient.preferences",
            "PayloadVersion": 1,
            "PayloadIdentifier": identifier + ".preferences.MobileAsset",
            "PayloadUUID": UUID().uuidString,
            "PayloadDisplayName": "Block Model Downloads",
            "PayloadContent": [
                downloadDomain: [
                    "Forced": [
                        ["mcx_preference_settings": forcedMobileAsset]
                    ]
                ]
            ]
        ]

        let profile: [String: Any] = [
            "PayloadType": "Configuration",
            "PayloadVersion": 1,
            "PayloadIdentifier": identifier,
            "PayloadUUID": UUID().uuidString,
            "PayloadDisplayName": "Disable Apple Intelligence (Widmut)",
            "PayloadDescription": "Turns off Apple Intelligence features and blocks models from downloading automatically. Remove profile to undo.",
            "PayloadOrganization": "Widmut",
            "PayloadScope": "System",
            "PayloadRemovalDisallowed": false,
            "PayloadContent": [restrictions, preferencesPayload]
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: profile, format: .xml, options: 0)
        let file = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads/Widmut-Disable-Apple-Intelligence.mobileconfig")
        try data.write(to: file)
        return file
    }
}

// MARK: - Page

struct PrivacyPage: View {
    @ObservedObject var store: PrivacyStore
    @ViewState private var confirm: ConfirmAction?
    @ViewState private var models: Int64?
    @ViewState private var actionMessage: String?
    @ViewState private var isPurging = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            hero
            appleIntelligence

            if let error = store.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12.5)).foregroundStyle(Theme.danger)
            }

            ForEach(PrivacyGroup.allCases) { group in
                let settings = PrivacyCatalog.all.filter { $0.group == group && $0.supported }
                if !settings.isEmpty {
                    GlowCard(glow: group.glow, style: .plain, padding: 20) {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 8) {
                                Image(systemName: group.symbol).font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(group.glow.color)
                                Text(group.title).cardTitle()
                                Spacer()
                                Text("\(settings.filter { store.applied.contains($0.id) }.count)/\(settings.count)")
                                    .font(.system(size: 11.5, weight: .medium)).monospacedDigit()
                                    .foregroundStyle(Theme.tertiaryText)
                            }
                            Text(group.summary).caption()
                            VStack(spacing: 4) {
                                ForEach(settings) { setting in
                                    row(setting)
                                    if setting.id != settings.last?.id { Rectangle().fill(Theme.hairline).frame(height: 1) }
                                }
                            }
                        }
                    }
                }
            }
        }
        .confirmation($confirm)
        .task {
            store.refresh()
            if models == nil { models = await Task.detached { AppleIntelligence.modelBytes() }.value }
        }
    }

    private var hero: some View {
        GlowCard(glow: .ember, style: .rim, padding: 26) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Settings Widmut can settle").cardTitle()
                HStack(alignment: .bottom, spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        MetricValue(value: "\(store.appliedCount)", unit: "of \(total) applied", dot: 7)
                        Text("Each one is a per-user preference, shown with the exact command before it changes, and every change can be undone.")
                            .caption().lineLimit(2)
                    }
                    Spacer(minLength: 12)
                    Button("Recheck") { store.refresh() }.buttonStyle(.pillSecondary)
                    if !store.journal.previous.isEmpty {
                        Button("Undo everything") { askToUndoEverything() }.buttonStyle(.pillDanger)
                    }
                }
            }
        }
        .frame(minHeight: 200)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Settings this Mac has; the count the hero figure is measured against.
    private var total: Int { PrivacyCatalog.all.filter(\.supported).count }

    private var appleIntelligence: some View {
        GlowCard(glow: .ember, style: .rim, padding: 22) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Image(systemName: "brain.head.profile").font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Glow.ember.color)
                            Text("Remove Mac AI (Apple Intelligence)").cardTitle()
                            if let models {
                                Tag(text: models == 0 ? "No models" : "\(models.bytesText) of AI models", color: Glow.ember.color)
                                    .help("The on-device models Apple Intelligence downloaded to this Mac")
                            } else {
                                Tag(text: "Scanning AI models…", color: Theme.tertiaryText)
                            }
                        }
                        Text(models == 0
                             ? "No on-device models currently downloaded on this Mac."
                             : "Purge downloaded Apple Intelligence foundation models, Siri understanding, and visual assets (up to 10+ GB), or install a profile to block automatic redownloads.")
                            .caption().frame(maxWidth: 640, alignment: .leading)
                    }
                    Spacer(minLength: 8)
                    HStack(spacing: 8) {
                        Button(isPurging ? "Purging…" : "Purge Models") {
                            askToPurgeModels()
                        }
                        .buttonStyle(.pillDanger)
                        .disabled(isPurging)

                        Button("Disable Profile") {
                            createDisableProfile()
                        }
                        .buttonStyle(.pillSecondary)
                        .help("Creates and opens a configuration profile that disables Apple Intelligence and prevents models from redownloading.")

                        Button("Settings") { NSWorkspace.shared.open(AppleIntelligence.settingsURL) }
                            .buttonStyle(.pillSecondary)
                    }
                }

                if let actionMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 12)).foregroundStyle(Theme.accent)
                        Text(actionMessage).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.accent)
                    }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func askToPurgeModels() {
        let sizeText = models.map { "\($0.bytesText) of " } ?? ""
        confirm = .init(
            title: "Purge Apple Intelligence Models?",
            message: "This will call Apple's Unified Asset Framework service to purge \(sizeText)on-device models (foundation, visual, and clean up models) to free up your disk space.",
            button: "Purge Models"
        ) {
            isPurging = true
            AppleIntelligence.purgeModels { result in
                isPurging = false
                switch result {
                case .success:
                    actionMessage = "Purge request sent to Apple Asset Service. Free space will update shortly."
                    Task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        models = await Task.detached { AppleIntelligence.modelBytes() }.value
                    }
                case .failure(let error):
                    actionMessage = "Purge error: \(error.localizedDescription)"
                }
            }
        }
    }

    private func createDisableProfile() {
        do {
            _ = try AppleIntelligence.generateDisableProfile()
            actionMessage = "Profile saved to Downloads/Widmut-Disable-Apple-Intelligence.mobileconfig and opened."
            NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads/Widmut-Disable-Apple-Intelligence.mobileconfig"))
        } catch {
            actionMessage = "Failed to create profile: \(error.localizedDescription)"
        }
    }

    private func row(_ setting: PrivacySetting) -> some View {
        let on = store.applied.contains(setting.id)
        let partly = store.mixed.contains(setting.id)
        return HStack(alignment: .top, spacing: 12) {
            CheckDot(on: on, tint: setting.group.glow.color)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(setting.title).font(.system(size: 13, weight: .medium))
                    if partly { Tag(text: "Partly", color: .orange) }
                    if let restart = setting.restart.first, !restart.isEmpty {
                        Tag(text: "Restart \(restart)").help("The setting is read when \(restart) starts")
                    }
                }
                Text(setting.detail).font(.system(size: 11.5)).foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if let caveat = setting.caveat {
                    Label(caveat, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11)).foregroundStyle(.orange)
                }
            }
                        Spacer(minLength: 8)
            // A setting that was already on when Widmut looked has no journal entry, so there is
            // nothing of ours to undo: say it is on instead of offering an Undo that would do nothing.
            if on, !store.restorable.contains(setting.id) {
                Tag(text: "Already on", color: Theme.accent)
                    .help("macOS already had this setting; Widmut did not change it")
            } else {
                Button(on ? "Undo" : "Apply") {
                    if on { askToUndo(setting) } else { askToApply(setting) }
                }
                .buttonStyle(PillButtonStyle(kind: .secondary, compact: true))
                .help(setting.commands.joined(separator: "\n"))
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(on ? "Applied" : partly ? "Partly applied" : "Not applied")
    }

    private func askToApply(_ setting: PrivacySetting) {
        confirm = .init(title: "Apply “\(setting.title)”?",
                        message: setting.commands.joined(separator: "\n") + "\n\nWidmut records the current value first, so Undo puts it back exactly.",
                        button: "Apply") { store.apply(setting) }
    }

    private func askToUndo(_ setting: PrivacySetting) {
        confirm = .init(title: "Undo “\(setting.title)”?",
                        message: "The value that was there before Widmut changed it is put back.",
                        button: "Undo") { store.undo(setting) }
    }

    private func askToUndoEverything() {
        let count = store.journal.previous.count
        confirm = .init(title: "Undo all \(count) change\(count == 1 ? "" : "s")?",
                        message: "Every preference Widmut changed is put back to the value it had before, including removing keys that did not exist.",
                        button: "Undo all") { store.undoEverything() }
    }
}
