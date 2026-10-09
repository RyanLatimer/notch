import AppKit
import Combine

struct NowPlayingInfo: Equatable {
    var title: String
    var artist: String
    var album: String
    /// Seconds; 0 when unknown (e.g. live streams).
    var duration: Double
    /// Elapsed seconds as of `timestamp`.
    var elapsed: Double
    var timestamp: Date
    var playbackRate: Double
    var isPlaying: Bool
    var bundleIdentifier: String?

    var subtitle: String {
        if !artist.isEmpty && !album.isEmpty { return "\(artist) — \(album)" }
        return artist.isEmpty ? album : artist
    }

    func currentElapsed(at date: Date = Date()) -> Double {
        guard isPlaying else { return elapsed }
        let rate = playbackRate > 0 ? playbackRate : 1
        let value = elapsed + date.timeIntervalSince(timestamp) * rate
        return duration > 0 ? min(duration, max(0, value)) : max(0, value)
    }
}

enum MediaCommand {
    case play
    case pause
    case togglePlayPause
    case nextTrack
    case previousTrack
}

protocol MediaSource: AnyObject {
    /// Called on the main thread with the full current state.
    var onChange: ((NowPlayingInfo?, NSImage?) -> Void)? { get set }
    /// Called on the main thread if the source stops working and a fallback should be used.
    var onFailure: (() -> Void)? { get set }
    var displayName: String { get }
    func start()
    func stop()
    func send(_ command: MediaCommand)
    func seek(to seconds: Double)
}

/// Single source of truth for now-playing state. Picks the MediaRemote adapter when it works
/// (covers every app, including browsers) and falls back to AppleScript for Spotify and Music.
final class MediaManager: ObservableObject {
    static let shared = MediaManager()

    @Published private(set) var info: NowPlayingInfo?
    @Published private(set) var artwork: NSImage?
    @Published private(set) var accentColor: NSColor = .white
    @Published private(set) var appIcon: NSImage?
    @Published private(set) var appName: String?
    @Published private(set) var sourceDescription = "Starting media service…"

    var isPlaying: Bool { info?.isPlaying ?? false }

    private var source: MediaSource?
    private var cancellables = Set<AnyCancellable>()
    private var configureGeneration = 0

    private init() {}

    func start() {
        if DebugFlags.demo {
            loadDemoContent()
            return
        }
        configure(AppSettings.shared.mediaSource)
        AppSettings.shared.$mediaSource
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] preference in self?.configure(preference) }
            .store(in: &cancellables)
    }

    func stop() {
        source?.stop()
        source = nil
    }

    func restart() {
        configure(AppSettings.shared.mediaSource)
    }

    private func configure(_ preference: MediaSourcePreference) {
        stop()
        apply(info: nil, artwork: nil)
        configureGeneration += 1
        let generation = configureGeneration

        let adapterResources = MediaRemoteAdapterSource.locateResources()

        switch preference {
        case .appleScript:
            use(AppleScriptMediaSource())
        case .mediaRemote:
            if let adapterResources {
                use(MediaRemoteAdapterSource(resources: adapterResources))
            } else {
                use(AppleScriptMediaSource())
            }
        case .automatic:
            guard let adapterResources else {
                use(AppleScriptMediaSource())
                return
            }
            sourceDescription = "Checking MediaRemote…"
            MediaRemoteAdapterSource.testFunctional(adapterResources) { [weak self] works in
                guard let self, generation == self.configureGeneration else { return }
                if works {
                    self.use(MediaRemoteAdapterSource(resources: adapterResources))
                } else {
                    NSLog("Notch: MediaRemote adapter not functional, falling back to AppleScript")
                    self.use(AppleScriptMediaSource())
                }
            }
        }
    }

    private func use(_ newSource: MediaSource) {
        source?.stop()
        source = newSource
        sourceDescription = newSource.displayName
        newSource.onChange = { [weak self] info, artwork in
            self?.apply(info: info, artwork: artwork)
        }
        newSource.onFailure = { [weak self, weak newSource] in
            guard let self, let newSource, self.source === newSource, !(newSource is AppleScriptMediaSource) else { return }
            NSLog("Notch: media source failed, falling back to AppleScript")
            self.use(AppleScriptMediaSource())
        }
        newSource.start()
    }

    private func apply(info newInfo: NowPlayingInfo?, artwork newArtwork: NSImage?) {
        if info != newInfo { info = newInfo }

        if artwork !== newArtwork {
            artwork = newArtwork
            accentColor = newArtwork?.accentColor ?? .white
        }

        let bundleID = newInfo?.bundleIdentifier
        if bundleID != currentBundleID {
            currentBundleID = bundleID
            if let bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                appIcon = NSWorkspace.shared.icon(forFile: url.path)
                appName = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            } else {
                appIcon = nil
                appName = nil
            }
        }
    }

    private var currentBundleID: String?

    // MARK: - Controls

    func togglePlayPause() {
        source?.send(.togglePlayPause)
        // Optimistic update so the button flips immediately.
        if var current = info {
            current.elapsed = current.currentElapsed()
            current.timestamp = Date()
            current.isPlaying.toggle()
            info = current
        }
    }

    func nextTrack() {
        source?.send(.nextTrack)
    }

    func previousTrack() {
        source?.send(.previousTrack)
    }

    func seek(to seconds: Double) {
        source?.seek(to: seconds)
        if var current = info {
            current.elapsed = seconds
            current.timestamp = Date()
            info = current
        }
    }

    func openPlayerApp() {
        guard let bundleID = info?.bundleIdentifier,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    // MARK: - Demo

    private func loadDemoContent() {
        sourceDescription = "Demo mode"
        let size = NSSize(width: 300, height: 300)
        let image = NSImage(size: size)
        image.lockFocus()
        NSGradient(colors: [
            NSColor(calibratedRed: 0.98, green: 0.35, blue: 0.45, alpha: 1),
            NSColor(calibratedRed: 0.45, green: 0.2, blue: 0.85, alpha: 1),
        ])?.draw(in: NSRect(origin: .zero, size: size), angle: -45)
        image.unlockFocus()

        apply(
            info: NowPlayingInfo(
                title: "Midnight City",
                artist: "M83",
                album: "Hurry Up, We're Dreaming",
                duration: 243,
                elapsed: 81,
                timestamp: Date(),
                playbackRate: 1,
                isPlaying: true,
                bundleIdentifier: "com.apple.Music"
            ),
            artwork: image
        )
    }
}

extension NSImage {
    /// Average colour, lifted so it stays visible on black.
    var accentColor: NSColor? {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        let drawn: Bool = pixel.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard drawn else { return nil }

        let color = NSColor(
            calibratedRed: CGFloat(pixel[0]) / 255,
            green: CGFloat(pixel[1]) / 255,
            blue: CGFloat(pixel[2]) / 255,
            alpha: 1
        )
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return NSColor(
            calibratedHue: hue,
            saturation: min(1, saturation * 1.2),
            brightness: max(0.75, brightness),
            alpha: 1
        )
    }
}
