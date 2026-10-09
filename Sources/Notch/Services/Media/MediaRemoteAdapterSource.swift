import AppKit

/// Reads now-playing info for every app via Apple's private MediaRemote framework.
///
/// Since macOS 15.4 only Apple-signed processes may talk to MediaRemote, so we run the bundled
/// `mediaremote-adapter.pl` with the system `/usr/bin/perl`, which loads
/// `MediaRemoteAdapter.framework` and streams JSON lines to stdout.
/// See https://github.com/ungive/mediaremote-adapter (BSD-3-Clause).
final class MediaRemoteAdapterSource: MediaSource {
    struct Resources {
        let script: URL
        let framework: URL
        let testClient: URL?
    }

    var onChange: ((NowPlayingInfo?, NSImage?) -> Void)?
    var onFailure: (() -> Void)?
    let displayName = "Using MediaRemote — works with any app, including browsers."

    private static let perl = URL(fileURLWithPath: "/usr/bin/perl")

    private let resources: Resources
    private var process: Process?
    private var stopped = true
    private var recentExits: [Date] = []

    // Accessed only from the pipe's reader queue.
    private var buffer = Data()

    // Main thread state.
    private var state: [String: Any] = [:]
    private var artwork: NSImage?
    private var artworkFingerprint: Int?

    init(resources: Resources) {
        self.resources = resources
    }

    static func locateResources() -> Resources? {
        guard let script = Bundle.main.url(forResource: "mediaremote-adapter", withExtension: "pl"),
              let framework = Bundle.main.privateFrameworksURL?.appendingPathComponent("MediaRemoteAdapter.framework"),
              FileManager.default.fileExists(atPath: framework.path)
        else { return nil }
        let testClient = Bundle.main.url(forAuxiliaryExecutable: "MediaRemoteAdapterTestClient")
        return Resources(script: script, framework: framework, testClient: testClient)
    }

    /// Runs the adapter's self-test (exit code 0 means MediaRemote is usable). Calls back on main.
    static func testFunctional(_ resources: Resources, completion: @escaping (Bool) -> Void) {
        guard let testClient = resources.testClient else {
            completion(true)
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = perl
            process.arguments = [resources.script.path, resources.framework.path, testClient.path, "test"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice

            let finished = DispatchSemaphore(value: 0)
            process.terminationHandler = { _ in finished.signal() }

            var works = false
            do {
                try process.run()
                if finished.wait(timeout: .now() + 8) == .timedOut {
                    process.terminate()
                } else {
                    works = process.terminationStatus == 0
                }
            } catch {
                NSLog("Notch: failed to run adapter test: \(error)")
            }
            DispatchQueue.main.async { completion(works) }
        }
    }

    // MARK: - Lifecycle

    func start() {
        stopped = false
        launch()
    }

    func stop() {
        stopped = true
        if let process {
            (process.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
            if process.isRunning { process.terminate() }
        }
        process = nil
    }

    private func launch() {
        let process = Process()
        process.executableURL = Self.perl
        process.arguments = [
            resources.script.path,
            resources.framework.path,
            "stream",
            "--micros",
            "--debounce=50",
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            self?.consume(data)
        }
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.processExited() }
        }

        do {
            try process.run()
            self.process = process
        } catch {
            NSLog("Notch: failed to launch media adapter: \(error)")
            onFailure?()
        }
    }

    private func processExited() {
        guard !stopped else { return }
        process = nil

        let now = Date()
        recentExits = recentExits.filter { now.timeIntervalSince($0) < 60 } + [now]
        if recentExits.count >= 4 {
            NSLog("Notch: media adapter keeps exiting")
            onFailure?()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, !self.stopped else { return }
            self.launch()
        }
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer.subdata(in: buffer.startIndex..<newline)
            buffer.removeSubrange(buffer.startIndex...newline)
            guard !line.isEmpty,
                  let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any]
            else { continue }
            DispatchQueue.main.async { [weak self] in self?.handle(message: object) }
        }
    }

    // MARK: - Parsing

    private func handle(message: [String: Any]) {
        guard !stopped, let payload = message["payload"] as? [String: Any] else { return }
        if (message["diff"] as? Bool) == true {
            for (key, value) in payload {
                if value is NSNull {
                    state.removeValue(forKey: key)
                } else {
                    state[key] = value
                }
            }
        } else {
            state = payload
        }
        emit()
    }

    private func number(_ key: String) -> Double? {
        (state[key] as? NSNumber)?.doubleValue
    }

    private func emit() {
        guard let title = state["title"] as? String, !title.isEmpty else {
            artwork = nil
            artworkFingerprint = nil
            onChange?(nil, nil)
            return
        }

        if let encoded = state["artworkData"] as? String, !encoded.isEmpty {
            let fingerprint = encoded.hashValue
            if fingerprint != artworkFingerprint {
                artworkFingerprint = fingerprint
                if let data = Data(base64Encoded: encoded, options: .ignoreUnknownCharacters) {
                    artwork = NSImage(data: data)
                } else {
                    artwork = nil
                }
            }
        } else {
            artwork = nil
            artworkFingerprint = nil
        }

        let timestamp = number("timestampEpochMicros").map { Date(timeIntervalSince1970: $0 / 1_000_000) } ?? Date()
        let bundleID = (state["parentApplicationBundleIdentifier"] as? String) ?? (state["bundleIdentifier"] as? String)

        let info = NowPlayingInfo(
            title: title,
            artist: state["artist"] as? String ?? "",
            album: state["album"] as? String ?? "",
            duration: (number("durationMicros") ?? 0) / 1_000_000,
            elapsed: (number("elapsedTimeMicros") ?? 0) / 1_000_000,
            timestamp: timestamp,
            playbackRate: number("playbackRate") ?? 1,
            isPlaying: (state["playing"] as? Bool) ?? false,
            bundleIdentifier: bundleID
        )
        onChange?(info, artwork)
    }

    // MARK: - Commands

    func send(_ command: MediaCommand) {
        let id: Int
        switch command {
        case .play: id = 0
        case .pause: id = 1
        case .togglePlayPause: id = 2
        case .nextTrack: id = 4
        case .previousTrack: id = 5
        }
        runOneShot(["send", String(id)])
    }

    func seek(to seconds: Double) {
        runOneShot(["seek", String(Int64(max(0, seconds) * 1_000_000))])
    }

    private func runOneShot(_ arguments: [String]) {
        let process = Process()
        process.executableURL = Self.perl
        process.arguments = [resources.script.path, resources.framework.path] + arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            NSLog("Notch: media command failed: \(error)")
        }
    }
}
