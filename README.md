<div align="center">

<img src="docs/logo.png" width="160" alt="Widmut logo" />

# Widmut

**The modern, powerful, and private Mac cleaner.**  
A fast, native macOS application designed to clean caches, uninstall apps with all leftovers, visualize and manage disk space, optimize performance, and protect your privacy.

[![License: GPL-3.0](https://img.shields.io/badge/license-GPL--3.0-2fa37a)](LICENSE)
[![macOS 26+](https://img.shields.io/badge/macOS-Apple%20Silicon-111?logo=apple)](#install)
[![Swift 6.2+](https://img.shields.io/badge/Swift-6.2%2B-FA9322?logo=swift)](#build)

<br/>

<img src="docs/widmut-preview.png" width="880" alt="Widmut Overview and System Monitor" />

</div>

---

## Highlights

* **100% Free & Open Source:** Full GPL-3.0 license. No subscriptions, no ads, no telemetry, no tracking.
* **Modern Pro Obsidian Design:** Solid dark surfaces with Solar Amber accents built entirely with native SwiftUI and SF Pro typography.
* **Safety First:** Actions default to Trash so you can easily restore anything. Critical macOS and application directories are strictly protected.
* **Next-Level Storage Map:** Interactive visual breakdown of your drives with one-click cleanup for caches, developer artifacts, and old downloads, plus multi-select batch deletion.
* **App Uninstaller & Leftover Cleaner:** Completely remove applications alongside their hidden Application Support, cache, and preference files.
* **Apple Intelligence Manager:** Detect, inspect, and purge on-device AI model weights to instantly reclaim gigabytes of storage.
* **Live System Monitor:** Real-time menu bar and dashboard monitor for CPU, memory pressure, battery, network, and disk usage.

---

## Features

| Feature | Description |
|---|---|
| **Overview** | Real-time Mac vitals: CPU load, memory pressure, network throughput, battery health, and quick actions |
| **Cleanup** | Scan and preview system and user caches, log files, and temporary data with one-click safe cleaning |
| **Uninstaller** | Comprehensive app catalog sorted by size or name with leftovers detection for already-deleted apps |
| **Speed Up** | One-click maintenance routines: DNS flush, Spotlight re-index, RAM release, and preference repairs |
| **Storage** | High-performance space visualizer with direct "Clean" actions, bulk deletion, and Finder reveals |
| **Privacy** | Toggle 27 system privacy settings, and inspect or purge Apple Intelligence / on-device AI models |
| **Activity** | Searchable audit trail of all actions and reclaimed disk space |
| **Menu Bar Tray** | Discreet, lightweight status monitor with quick actions right from your menu bar |

---

## Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| <kbd>⌘</kbd> <kbd>1</kbd> … <kbd>⌘</kbd> <kbd>7</kbd>, <kbd>⌘</kbd> <kbd>,</kbd> | Jump directly to any page |
| <kbd>⌘</kbd> <kbd>R</kbd> | Rescan or stop current scan |
| <kbd>⌘</kbd> <kbd>F</kbd> | Search applications in Uninstall |
| <kbd>Esc</kbd> | Clear current selection |
| <kbd>Return</kbd> | Confirm selected action |

---

## Installation

### Requirements
* macOS 26.0 or later
* Apple Silicon (M1, M2, M3, M4)

### Building from Source

Widmut requires only the standard Swift toolchain and command-line tools:

```bash
# Clone the repository
git clone https://github.com/VedasarathiV/widmut.git
cd widmut

# Run the test suite
swift test

# Build and bundle the application
./scripts/bundle.sh

# Install to Applications
cp -R build/Widmut.app /Applications/Widmut.app
xattr -cr /Applications/Widmut.app
```

---

## License

Widmut is free software licensed under the **GNU General Public License v3.0** ([GPL-3.0](LICENSE)).

---

Developed by [DigiMartrix](https://digimartrix.com/).
