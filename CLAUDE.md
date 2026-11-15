# Widmut: agent instructions

Widmut is a native SwiftUI macOS app that gives a premium GUI Mac cleaner. Repo: github.com/VedasarathiV/widmut, public, GPL-3.0.
Everything about this project is written here or in this repository, never in other projects'
folders or memories.

## Shape
- `Sources/Wildmutt/Engine`: how Mole is run. `Mole.swift` (pipes: JSON and dry-run text, process
  tracking), `MoleSession.swift` (pseudo-terminal for real actions: Mole keeps its prompts, sudo and
  safety checks; the app answers prompts natively), `Reports.swift` (parsers), `TerminalText.swift`.
- `Sources/Wildmutt/Design`: the design system (glow cards, dot-matrix numerals, gauges, motion).
- `Sources/Wildmutt/Features`: one file per page; long-lived scans and stores live in `AppModel`.
  `PrivacyPage.swift` is the one page that does not go through Mole: it writes per-user preferences
  through `CFPreferences` and keeps the value each one replaced in its own undo journal.
- `Vendor/mole`: the bundled Mole engine (`VERSION` file). Do not edit it; update it as a whole.
- `scripts/bundle.sh` builds `build/Wildmutt.app` (release binary + Mole + icon, ad-hoc signed).

## Build rules
- Xcode Command Line Tools only, no Xcode: `swift build`, `swift test`, `scripts/bundle.sh`.
- The `@State` macro plugin ships only with Xcode, so use `@ViewState` (a typealias for
  `SwiftUI.State`) everywhere. Tests use Swift Testing (`import Testing`), not XCTest.
- No new package dependencies without a recorded reason.

## Safety (this runs on the owner's real Mac)
- Agents never run a real Mole action while testing: no `clean`, `uninstall`, `purge`, `slim`,
  `optimize`, `installer` without `--dry-run`, no `touchid enable/disable`, `remove`, `update`.
- In the running app, never press Clean now, Optimize, Uninstall, Remove selected, Move to Trash,
  Slim apps, Touch ID Turn on/off or Remove…, and never confirm a Mole prompt.
- Never write the owner's Mole config and state (`~/.config/mole`, `~/.cache/mole`,
  `~/Library/Logs/mole`); tests use a temporary directory.
- The Privacy page changes the owner's real macOS preferences. Never press Apply, Undo or Undo
  everything while testing, and never let a test write to `~/Library/Application Support/Wildmutt/
  privacy-journal.json`: `PrivacyStore(folder:)` exists so tests take a temporary folder.
- Quit Wildmutt after testing and make sure no `Wildmutt.app/Contents/Resources/mole` process remains.

## Screenshots for reviews
`build/Wildmutt.app/Contents/MacOS/Wildmutt -startPage <page> -snapshot <file.png> [-snapshotDelay 12]
[-snapshotSize 1080x700]` draws the window offscreen and quits; it works while the screen is locked.
Pages: overview, clean, uninstall, optimize, analyze, projects, installers, privacy, slim, history,
settings.
`swift test` must run outside the sandbox; after a sandboxed run, `rm -rf .build` first. Since the
macOS 27.2 Command Line Tools the Testing macro plugin is not found by default: run
`swift test -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing`.

## Design bar
Dark, premium, few large elements: squircle cards lit by one hue (rim or inner glow), dot-matrix
numerals, dotted meters, capsule buttons, white circular icon buttons; smooth, purposeful motion that
honours Reduce Motion. The palette is Wildmutt's: the alien's coat runs coral to rust, its fur is
cream, and Omnitrix green marks what is done. The app icon is drawn by `scripts/make-icon.swift` from the owner's `Wildmutt.jpeg`
(the checkerboard it was saved on is keyed out, composited into the squircle); the menu bar uses a
vector version of his blind head — ears, gill slits, fangs — as a template image in `Tray.swift`. Reviews of UI, UX, visuals and motion are done by a Claude `"opus"` critic with
screenshots of every page and the diff, never by Codex (no design taste); Codex only reviews
engine/backend code.

## Releases
GitHub releases carry `Wildmutt.dmg` (`scripts/dmg.sh`), `Wildmutt.zip`
(`ditto -c -k --keepParent build/Wildmutt.app`) and `appcast.xml` (`scripts/appcast.sh`). Bump
`VERSION`, build, test, zip, run `scripts/appcast.sh`, then `gh release create v<version>` with all
three. Every installed Wildmutt reads `releases/latest/download/appcast.xml` (Sparkle 2, a binary
target in Package.swift; the package itself clones Sparkle's whole history) and updates itself on
quit, so a release without `appcast.xml` stalls every user on the old version. The update zip is
signed with the EdDSA key in the owner's login Keychain (`generate_keys`, public key in
`scripts/bundle.sh`); lose it and updates stop: keep an export (`generate_keys -x <file>`) off this
Mac. Test an update end to end with a copy that has another bundle id and a local http appcast
(`NSAllowsLocalNetworking`), never with the owner's own defaults.
`scripts/demo-video.sh` records the full tour (`build/demo.mp4`, a release asset, plus
`build/demo-raw.mov`): the `-tour` walk, screen-recorded with `screencapture -v` (`cacheDisplay`
misses SwiftUI transitions); the window must stay uncovered ~45 s. `promo/` is the 17 s HyperFrames
edit of that raw take: copy it to `promo/assets/screen.mov`, check the cut times in `index.html`, then
`npx hyperframes@0.8.214 render promo -o build/promo.mp4` (and `-c gif.html` for the README GIF,
`docs/demo.gif`: 880 px, 10 fps, Bayer dither, about 6 MB so it loads fast).

## Performance
Nothing may animate forever behind the content: a repeating animation inside a large layer makes
SwiftUI redraw that layer every frame (v0.2.0 idled at 20–40% CPU from a drifting background).
Check idle CPU with `top -pid` after visual changes. Scan results live in `ResultCache`
(`~/Library/Caches/uz.khan.wildmutt`); pages never re-scan on appear.
