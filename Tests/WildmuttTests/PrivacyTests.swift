import Foundation
import Testing
@testable import Wildmutt

/// The Privacy page's rules, without ever writing a preference on this Mac.
@MainActor
struct PrivacyTests {
    @Test func valuesMatchTheWayPreferencesStoreThem() {
        #expect(PlistValue.bool(true).matches(true))
        #expect(PlistValue.bool(true).matches(NSNumber(value: 1)))
        #expect(!PlistValue.bool(true).matches(NSNumber(value: 0)))
        #expect(PlistValue.int(2).matches(NSNumber(value: 2)))
        #expect(PlistValue.double(0).matches(NSNumber(value: 0)))
        #expect(PlistValue.string("SCcf").matches("SCcf"))
        #expect(!PlistValue.string("SCcf").matches("SCsp"))
        #expect(!PlistValue.string("SCcf").matches(nil))
        #expect(PlistValue(nil) == nil)
    }

    /// Two tweaks must never change the same preference, or Undo would restore the wrong value.
    @Test func everyPreferenceHasOneOwner() {
        var seen = Set<String>()
        for setting in PrivacyCatalog.all {
            #expect(!setting.changes.isEmpty, "\(setting.id) changes nothing")
            for change in setting.changes {
                #expect(seen.insert(change.journalKey).inserted, "\(change.journalKey) is changed twice")
            }
        }
        #expect(Set(PrivacyCatalog.all.map(\.id)).count == PrivacyCatalog.all.count)
    }

    @Test func commandsAreTheDefaultsLineForTheValue() {
        let finder = PrivacyChange(domain: "com.apple.finder", key: "ShowPathbar", value: .bool(true))
        #expect(finder.command == #"defaults write com.apple.finder "ShowPathbar" -bool true"#)
        let typing = PrivacyChange(domain: Prefs.global, key: "ApplePressAndHoldEnabled", value: .bool(false))
        #expect(typing.command == #"defaults write NSGlobalDomain "ApplePressAndHoldEnabled" -bool false"#)
        let scope = PrivacyChange(domain: "com.apple.finder", key: "FXDefaultSearchScope", value: .string("SCcf"))
        #expect(scope.command == #"defaults write com.apple.finder "FXDefaultSearchScope" -string "SCcf""#)
    }

    /// The journal that makes Undo exact lives in Widmut's own folder, never in Mole's.
    @Test func journalLivesInTheAppsOwnFolder() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("widmut-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = PrivacyStore(folder: folder)
        #expect(store.journalURL.deletingLastPathComponent().path == folder.path)
        #expect(store.journal.previous.isEmpty)
    }

    @Test func appleIntelligenceModelsAreReadFromTheSystemFolders() {
        for path in AppleIntelligence.modelFolders {
            #expect(path.hasPrefix("/System/Library/AssetsV2/com_apple_MobileAsset_UAF_FM_"))
        }
    }
}
