import AppKit

/// Fallback source for Spotify and Apple Music using their AppleScript dictionaries.
/// Track changes arrive via the players' distributed notifications; a slow timer keeps the
/// position in sync. Requires the Automation permission, which macOS prompts for once per app.
final class AppleScriptMediaSource: NSObject, MediaSource {
    private struct Player {
        let bundleID: String
        let notification: String
        let infoScript: String
        let artworkScript: String?
    }

    private struct Snapshot {
        let title: String
        let artist: String
        let album: String
        let duration: Double
        let position: Double
        let isPlaying: Bool
        let trackID: String
        let artworkURL: String
    }

    var onChange: ((NowPlayingInfo?, NSImage?) -> Void)?
    var onFailure: (() -> Void)?
    let displayName = "Using AppleScript — supports Spotify and Apple Music."

    private let players: [Player] = [
        Player(
            bundleID: "com.spotify.client",
            notification: "com.spotify.client.PlaybackStateChanged",
            infoScript: """
            tell application id "com.spotify.client"
                if player state is stopped then return {}
                set t to current track
                return {name of t, artist of t, album of t, (duration of t) / 1000, player position, (player state is playing), id of t, artwork url of t}
            end tell
            """,
            artworkScript: nil
        ),
        Player(
            bundleID: "com.apple.Music",
            notification: "com.apple.Music.playerInfo",
            infoScript: """
            tell application id "com.apple.Music"
                if player state is stopped then return {}
                try
                    set t to current track
                    return {name of t, artist of t, album of t, duration of t, player position, (player state is playing), persistent ID of t, ""}
                on error
                    return {}
                end try
            end tell
            """,
            artworkScript: """
            tell application id "com.apple.Music"
                try
                    return raw data of artwork 1 of current track
                end try
            end tell
            """
        ),
    ]

    private var compiled: [String: NSAppleScript] = [:]
    private var activeBundleID: String?
    private var trackKey: String?
    private var artwork: NSImage?
    private var lastInfo: NowPlayingInfo?
    private var timer: Timer?
    private var running = false

    func start() {
        running = true
        let center = DistributedNotificationCenter.default()
        for player in players {
            center.addObserver(self, selector: #selector(playerDidChange(_:)), name: Notification.Name(player.notification), object: nil)
        }
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(appsDidChange(_:)), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        workspace.addObserver(self, selector: #selector(appsDidChange(_:)), name: NSWorkspace.didTerminateApplicationNotification, object: nil)

        let timer = Timer(timeInterval: 5, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        refresh()
    }

    func stop() {
        running = false
        DistributedNotificationCenter.default().removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        timer?.invalidate()
        timer = nil
    }

    @objc private func playerDidChange(_ notification: Notification) {
        // Give the player a moment to settle before querying it.
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(refreshNow), object: nil)
        perform(#selector(refreshNow), with: nil, afterDelay: 0.15)
    }

    @objc private func appsDidChange(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              players.contains(where: { $0.bundleID == app.bundleIdentifier })
        else { return }
        perform(#selector(refreshNow), with: nil, afterDelay: 1)
    }

    @objc private func tick() {
        if players.contains(where: isRunning) { refresh() }
    }

    @objc private func refreshNow() {
        refresh()
    }

    private func isRunning(_ player: Player) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: player.bundleID).isEmpty
    }

    private func refresh() {
        guard running else { return }

        var candidates: [(Player, Snapshot)] = []
        for player in players where isRunning(player) {
            if let snapshot = query(player) {
                candidates.append((player, snapshot))
            }
        }

        let chosen = candidates.first(where: { $0.1.isPlaying })
            ?? candidates.first(where: { $0.0.bundleID == activeBundleID })
            ?? candidates.first

        guard let chosen else {
            activeBundleID = nil
            trackKey = nil
            artwork = nil
            lastInfo = nil
            onChange?(nil, nil)
            return
        }

        let (player, snapshot) = chosen
        activeBundleID = player.bundleID

        let key = player.bundleID + "|" + snapshot.trackID + "|" + snapshot.title
        if key != trackKey {
            trackKey = key
            artwork = nil
            loadArtwork(for: player, snapshot: snapshot, key: key)
        }

        let info = NowPlayingInfo(
            title: snapshot.title,
            artist: snapshot.artist,
            album: snapshot.album,
            duration: snapshot.duration,
            elapsed: snapshot.position,
            timestamp: Date(),
            playbackRate: 1,
            isPlaying: snapshot.isPlaying,
            bundleIdentifier: player.bundleID
        )
        lastInfo = info
        onChange?(info, artwork)
    }

    private func script(_ source: String) -> NSAppleScript? {
        if let cached = compiled[source] { return cached }
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        guard script.compileAndReturnError(&error) else {
            NSLog("Notch: AppleScript compile error: \(String(describing: error))")
            return nil
        }
        compiled[source] = script
        return script
    }

    private func execute(_ source: String) -> NSAppleEventDescriptor? {
        guard let script = script(source) else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            NSLog("Notch: AppleScript error: \(error)")
            return nil
        }
        return result
    }

    private func query(_ player: Player) -> Snapshot? {
        guard let result = execute(player.infoScript), result.numberOfItems >= 8 else { return nil }
        func string(_ index: Int) -> String { result.atIndex(index)?.stringValue ?? "" }
        func double(_ index: Int) -> Double { result.atIndex(index)?.doubleValue ?? 0 }

        let title = string(1)
        guard !title.isEmpty else { return nil }
        return Snapshot(
            title: title,
            artist: string(2),
            album: string(3),
            duration: double(4),
            position: double(5),
            isPlaying: result.atIndex(6)?.booleanValue ?? false,
            trackID: string(7),
            artworkURL: string(8)
        )
    }

    private func loadArtwork(for player: Player, snapshot: Snapshot, key: String) {
        if let artworkScript = player.artworkScript {
            if let data = execute(artworkScript)?.data, let image = NSImage(data: data) {
                artwork = image
            }
            return
        }

        guard let url = URL(string: snapshot.artworkURL), url.scheme?.hasPrefix("http") == true else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let image = NSImage(data: data) else { return }
            DispatchQueue.main.async {
                guard let self, self.trackKey == key else { return }
                self.artwork = image
                self.onChange?(self.lastInfo, image)
            }
        }.resume()
    }

    // MARK: - Commands

    func send(_ command: MediaCommand) {
        guard let bundleID = activeBundleID ?? players.first(where: isRunning)?.bundleID else { return }
        let verb: String
        switch command {
        case .play: verb = "play"
        case .pause: verb = "pause"
        case .togglePlayPause: verb = "playpause"
        case .nextTrack: verb = "next track"
        case .previousTrack: verb = "previous track"
        }
        _ = execute("tell application id \"\(bundleID)\" to \(verb)")
        perform(#selector(refreshNow), with: nil, afterDelay: 0.3)
    }

    func seek(to seconds: Double) {
        guard let bundleID = activeBundleID else { return }
        _ = execute("tell application id \"\(bundleID)\" to set player position to \(max(0, seconds))")
        perform(#selector(refreshNow), with: nil, afterDelay: 0.3)
    }
}
