import AppKit
import SwiftUI

/// The menu bar card: free space, the Mac's vitals and the tool results at a glance, each a
/// shortcut into the window. Live status streams only while the card is open.
struct TrayView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var monitor: StatusMonitor
    @ObservedObject var leftovers: LeftoverStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let s = monitor.status
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 20, height: 20).accessibilityHidden(true)
                Text("Widmut").font(.system(size: 14, weight: .semibold))
                Spacer()
                if let score = s?.health_score {
                    Tag(text: "Health \(score)", color: score >= 70 ? Theme.accent : score >= 45 ? .orange : Theme.danger)
                }
            }
            .padding(.horizontal, 4)

            Button { open(.storage) } label: { diskCard(s) }
                .buttonStyle(.plain).hoverLift().accessibilityHint("Opens Storage")

            HStack(spacing: 10) {
                vital("CPU", s.map { String(format: "%.0f", $0.cpu?.usage ?? 0) }, unit: "%", fill: (s?.cpu?.usage ?? 0) / 100, glow: .violet)
                vital("Memory", s.map { String(format: "%.0f", $0.memory?.used_percent ?? 0) }, unit: "%",
                      fill: (s?.memory?.used_percent ?? 0) / 100, glow: .magenta, pressure: monitor.pressure)
                if let b = s?.batteries?.first {
                    vital("Battery", String(format: "%.0f", b.percent ?? 0), unit: "%", fill: (b.percent ?? 0) / 100, glow: .ember)
                } else {
                    // A desktop Mac has no battery: the network takes its place.
                    let rx = (s?.network ?? []).compactMap(\.rx_rate_mbs).reduce(0, +)
                    vital("Network", s.map { _ in String(format: "%.1f", rx) }, unit: "MB/s", fill: min(rx / 10, 1), glow: .ember)
                }
            }

            VStack(spacing: 2) {
                TrayRow(title: "Caches and logs", value: scanValue(model.clean, \.total), busy: model.clean.scanning,
                        clean: canClean ? { open(.cleanup); model.askCleanAt = Date() } : nil) { open(.cleanup) }
                row("Leftovers of removed apps", value: leftoversValue, busy: leftovers.scanning, page: .uninstall)
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.surface))

            HStack(spacing: 8) {
                Button { open(nil) } label: { Text("Open Widmut").frame(maxWidth: .infinity) }.buttonStyle(.pill)
                // Quit sits behind the menu, away from a stray click.
                Menu {
                    Button("Settings…") { open(.settings) }
                    Divider()
                    Button("Quit Widmut") { NSApp.terminate(nil) }.keyboardShortcut("q")
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 14, weight: .semibold))
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(.white.opacity(0.08)))
                        .overlay(Circle().strokeBorder(.white.opacity(0.12)))
                        .contentShape(Circle())
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                .foregroundStyle(.white)
                .accessibilityLabel("More")
            }
        }
        .padding(14)
        .frame(width: 330)
        .background(Theme.background)
        .preferredColorScheme(.dark)
        .onAppear { monitor.acquire("tray") }
        .onDisappear { monitor.release("tray") }
    }

    /// Brings the window forward (or back, once closed), on `page` when given.
    private func open(_ page: Page?) {
        model.askCleanAt = nil
        if let page { model.page = page }
        NSApp.activate()
        if let window = NSApp.widmutWindow {
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "main")
        }
    }

    private func diskCard(_ s: SystemStatus?) -> some View {
        let disk = s?.rootDisk
        let free = (disk?.total ?? 0) - (disk?.used ?? 0)
        return GlowCard(glow: .blue, style: .rim, padding: 18) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Free space").cardTitle()
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.secondaryText)
                }
                MetricValue(value: disk == nil ? "-" : free.metric.value, unit: (disk == nil ? "GB" : free.metric.unit) + " free",
                            dot: 4.5, live: true)
                DotMeter(value: disk.map { Double($0.used) / Double(max($0.total, 1)) } ?? 0, count: 34)
                Text(disk.map { "\($0.used.bytesText) used of \($0.total.bytesText)" } ?? "Reading the disk…").caption()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    /// `pressure` colours the memory meter: a full RAM is normal on a Mac, pressure is not.
    private func vital(_ title: String, _ value: String?, unit: String, fill: Double, glow: Glow,
                       pressure: MemoryPressure? = nil) -> some View {
        Button { open(.overview) } label: {
            GlowCard(glow: glow, style: .core, padding: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 4) {
                        Text(title).font(.system(size: 11)).foregroundStyle(Theme.secondaryText).lineLimit(1)
                        Spacer(minLength: 0)
                        // Only pressure that matters is shown, in words: a full RAM is normal on a Mac.
                        if let pressure, pressure != .normal {
                            Text(pressure.label).font(.system(size: 10, weight: .semibold)).foregroundStyle(pressure.color)
                        }
                    }
                    MetricValue(value: value ?? "-", unit: unit, dot: 3, live: true)
                    DotMeter(value: fill, count: 9, color: pressure == nil || pressure == .normal ? .white : pressure!.color)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain).hoverLift()
        .accessibilityElement(children: .combine)
        .accessibilityValue(pressure.map { "Memory pressure \($0.label)" } ?? "")
        .accessibilityHint("Opens Overview")
    }

    private func row(_ title: String, value: String, busy: Bool, page: Page) -> some View {
        TrayRow(title: title, value: value, busy: busy) { open(page) }
    }

    /// Cleaning starts from the window's own confirmation and run sheet, never from here.
    private var canClean: Bool {
        !model.clean.scanning && (model.clean.report?.total ?? 0) > 0 && model.session == nil
    }

    private func scanValue<R>(_ scan: Scan<R>, _ bytes: KeyPath<R, Int64>) -> String {
        if let r = scan.report { return r[keyPath: bytes].bytesText }
        return scan.scanning ? "Scanning…" : "Not scanned"
    }

    private var leftoversValue: String {
        guard let all = leftovers.leftovers else { return leftovers.scanning ? "Looking…" : "Not checked" }
        return all.isEmpty ? "None" : all.map(\.bytes).reduce(0, +).bytesText
    }
}

private struct TrayRow: View {
    let title: String
    let value: String
    let busy: Bool
    /// A Clean button on the row, when there is something to clean.
    var clean: (() -> Void)?
    let action: () -> Void
    @ViewState private var hover = false

    var body: some View {
        // The Clean button sits beside the row's own button: a button inside another's label
        // does not reliably get its click.
        HStack(spacing: 8) {
            Button(action: action) {
                HStack(spacing: 8) {
                    Text(title).font(.system(size: 13))
                    Spacer()
                    if busy { PulseDot() }
                    Text(value).font(.system(size: 13, weight: .medium)).monospacedDigit().foregroundStyle(Theme.secondaryText)
                    if clean == nil { chevron }
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hover = $0 }
            .accessibilityLabel("\(title), \(value)")
            if let clean {
                Button("Clean", action: clean)
                    .buttonStyle(PillButtonStyle(kind: .secondary, compact: true))
                    .accessibilityLabel("Clean \(title.lowercased()), \(value)")
                    .accessibilityHint("Asks before Widmut cleans")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(hover ? 0.07 : 0)))
        .animation(Motion.quick, value: hover)
    }

    private var chevron: some View {
        Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.tertiaryText)
    }
}

/// The menu bar mark: the app icon's own art with the icon's dark squircle taken away, so the bar
/// shows the same Widmut as the window and the Dock instead of the old blind head.
enum TrayIcon {
    static let image: NSImage = {
        // Without a cut (never in the bundled app) the icon itself still shows, tile and all.
        guard let icon = NSApp.applicationIconImage else { return NSImage(size: NSSize(width: 18, height: 18)) }
        guard let mark = cutout(from: icon) else { return icon }
        mark.accessibilityDescription = "Widmut"
        return mark
    }()

    /// Copies the icon small, drops the drop shadow and the squircle's antialiased rim, then grows
    /// the icon's dark warm brown background away from that rim. The black line art and the orange
    /// coat stop the fill, so Widmut's own shading survives; what is left is trimmed to him and
    /// sized for the bar.
    private static func cutout(from icon: NSImage) -> NSImage? {
        guard let full = icon.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        // 160 px is far more than the bar needs, and keeps the fill instant.
        let scale = min(160 / CGFloat(full.width), 160 / CGFloat(full.height))
        let width = Int(CGFloat(full.width) * scale), height = Int(CGFloat(full.height) * scale)
        guard width > 8, height > 8 else { return nil }

        let space = CGColorSpaceCreateDeviceRGB()
        let count = width * height
        let pixels = UnsafeMutablePointer<UInt8>.allocate(capacity: count * 4)
        pixels.initialize(repeating: 0, count: count * 4)
        defer { pixels.deallocate() }
        guard let canvas = CGContext(data: pixels, width: width, height: height, bitsPerComponent: 8,
                                     bytesPerRow: width * 4, space: space,
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        canvas.interpolationQuality = .high
        canvas.draw(full, in: CGRect(x: 0, y: 0, width: width, height: height))
        // The icon as it came, kept for its colours; `pixels` is the copy being cut.
        let art = Array(UnsafeBufferPointer(start: pixels, count: count * 4))

        func alpha(_ i: Int) -> Int { Int(art[i * 4 + 3]) }
        func colour(_ i: Int) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
            let a = CGFloat(max(alpha(i), 1))
            return (CGFloat(art[i * 4]) / a, CGFloat(art[i * 4 + 1]) / a, CGFloat(art[i * 4 + 2]) / a)
        }
        func clear(_ i: Int) {
            pixels[i * 4] = 0
            pixels[i * 4 + 1] = 0
            pixels[i * 4 + 2] = 0
            pixels[i * 4 + 3] = 0
        }
        // The background is a dark, warm brown gradient; black line art and the bright coat are not.
        func isBackground(_ i: Int) -> Bool {
            guard alpha(i) > 50 else { return false }
            let c = colour(i)
            return c.r > 0.02 && c.r < 0.62 && c.g < c.r * 0.78 && c.b < c.r * 0.38
        }
        // A fill that only continues colours close to the one it came from follows the gradient to
        // the art's edge and stops there, instead of jumping across it.
        func continues(_ i: Int, _ from: Int) -> Bool {
            let a = colour(i), b = colour(from)
            return abs(a.r - b.r) < 0.07 && abs(a.g - b.g) < 0.05 && abs(a.b - b.b) < 0.04
                && abs(alpha(i) - alpha(from)) < 40
        }

        // The shadow and the squircle's rim are the only translucent pixels around the art:
        // clearing them leaves the background itself to fill.
        for i in 0..<count where alpha(i) < 250 { clear(i) }

        var seen = [Bool](repeating: false, count: count)
        var stack: [Int] = []
        for y in 0..<height {
            for x in 0..<width {
                let i = y * width + x
                guard pixels[i * 4 + 3] > 50, isBackground(i) else { continue }
                let onRim = [(1, 0), (-1, 0), (0, 1), (0, -1)].contains { dx, dy in
                    let nx = x + dx, ny = y + dy
                    return nx < 0 || ny < 0 || nx >= width || ny >= height || pixels[(ny * width + nx) * 4 + 3] <= 50
                }
                if onRim { seen[i] = true; stack.append(i) }
            }
        }
        while let i = stack.popLast() {
            clear(i)
            let x = i % width, y = i / width
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let nx = x + dx, ny = y + dy
                guard nx >= 0, ny >= 0, nx < width, ny < height else { continue }
                let n = ny * width + nx
                if !seen[n], isBackground(n), continues(n, i) { seen[n] = true; stack.append(n) }
            }
        }

        var minX = width, minY = height, maxX = -1, maxY = -1
        for i in 0..<count where pixels[i * 4 + 3] > 12 {
            minX = min(minX, i % width)
            maxX = max(maxX, i % width)
            minY = min(minY, i / width)
            maxY = max(maxY, i / width)
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        let cutW = maxX - minX + 1, cutH = maxY - minY + 1
        var cut = [UInt8](repeating: 0, count: cutW * cutH * 4)
        for y in 0..<cutH {
            for x in 0..<cutW {
                let from = ((y + minY) * width + (x + minX)) * 4, to = (y * cutW + x) * 4
                cut[to] = pixels[from]
                cut[to + 1] = pixels[from + 1]
                cut[to + 2] = pixels[from + 2]
                cut[to + 3] = pixels[from + 3]
            }
        }
        guard let provider = CGDataProvider(data: Data(cut) as CFData),
              let image = CGImage(width: cutW, height: cutH, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: cutW * 4, space: space,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: true,
                                  intent: .defaultIntent) else { return nil }
        // The bar's own height, the width following the art so he is never squashed.
        let barHeight: CGFloat = 18
        return NSImage(cgImage: image, size: NSSize(width: barHeight * CGFloat(cutW) / CGFloat(cutH),
                                                    height: barHeight))
    }
}
