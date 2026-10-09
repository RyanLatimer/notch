import AppKit
import ApplicationServices
import Combine

enum HUDKind: String {
    case volume
    case brightness
}

struct HUDEvent: Equatable {
    let kind: HUDKind
    let value: Float
    let muted: Bool

    var symbolName: String {
        switch kind {
        case .brightness:
            return value < 0.35 ? "sun.min.fill" : "sun.max.fill"
        case .volume:
            if muted || value <= 0.001 { return "speaker.slash.fill" }
            if value < 0.34 { return "speaker.wave.1.fill" }
            if value < 0.67 { return "speaker.wave.2.fill" }
            return "speaker.wave.3.fill"
        }
    }
}

/// Publishes volume/brightness changes for the notch HUD and, when enabled, takes over the
/// hardware keys so the macOS overlay never appears.
final class SystemHUDController: NSObject {
    static let shared = SystemHUDController()

    let events = PassthroughSubject<HUDEvent, Never>()

    private var volumeObserver: VolumeObserver?
    private var keyTap: MediaKeyTap?
    private var trustTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    private var lastVolumeEvent: (value: Float, muted: Bool, time: Date)?
    private var brightnessAnchor: (value: Float, time: Date)?
    private var lastBrightnessKeyPress = Date.distantPast

    private override init() {}

    func start() {
        let observer = VolumeObserver { [weak self] in self?.volumeDidChange() }
        observer.start()
        volumeObserver = observer

        brightnessAnchor = BrightnessControl.brightness.map { (value: $0, time: Date()) }
        BrightnessControl.observeChanges()

        AppSettings.shared.$replaceSystemHUD
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in self?.setKeyInterception(enabled) }
            .store(in: &cancellables)
    }

    // MARK: - Passive observation

    private func volumeDidChange() {
        guard let volume = VolumeControl.volume else { return }
        let muted = VolumeControl.isMuted
        let now = Date()
        // Several properties fire for one change; collapse duplicates.
        if let last = lastVolumeEvent, last.value == volume, last.muted == muted, now.timeIntervalSince(last.time) < 0.25 {
            return
        }
        lastVolumeEvent = (volume, muted, now)
        events.send(HUDEvent(kind: .volume, value: volume, muted: muted))
    }

    func brightnessDidChange() {
        guard let value = BrightnessControl.brightness else { return }
        let now = Date()

        // Keys we intercepted already emitted their own event.
        if now.timeIntervalSince(lastBrightnessKeyPress) < 0.6 { return }

        // Auto-brightness drifts slowly; only surface deliberate jumps.
        guard let anchor = brightnessAnchor, now.timeIntervalSince(anchor.time) < 1.5 else {
            brightnessAnchor = (value, now)
            return
        }
        if abs(value - anchor.value) >= 0.05 {
            brightnessAnchor = (value, now)
            events.send(HUDEvent(kind: .brightness, value: value, muted: false))
        }
    }

    // MARK: - Key interception

    private func setKeyInterception(_ enabled: Bool) {
        trustTimer?.invalidate()
        trustTimer = nil

        guard enabled else {
            keyTap?.stop()
            keyTap = nil
            return
        }

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) {
            startKeyTap()
        } else {
            // Wait for the user to grant Accessibility access.
            let timer = Timer(timeInterval: 2, target: self, selector: #selector(checkTrust), userInfo: nil, repeats: true)
            RunLoop.main.add(timer, forMode: .common)
            trustTimer = timer
        }
    }

    @objc private func checkTrust() {
        guard AXIsProcessTrusted() else { return }
        trustTimer?.invalidate()
        trustTimer = nil
        if AppSettings.shared.replaceSystemHUD { startKeyTap() }
    }

    private func startKeyTap() {
        guard keyTap == nil else { return }
        let tap = MediaKeyTap { [weak self] key, isDown, fine in
            self?.handle(key: key, isDown: isDown, fine: fine) ?? false
        }
        if tap.start() {
            keyTap = tap
        } else {
            NSLog("Notch: could not create event tap")
        }
    }

    /// Returns true when the key was handled and should be swallowed.
    private func handle(key: MediaKey, isDown: Bool, fine: Bool) -> Bool {
        let step: Float = fine ? 1.0 / 64.0 : 1.0 / 16.0

        switch key {
        case .volumeUp, .volumeDown, .mute:
            guard VolumeControl.canSetVolume else { return false }
            guard isDown else { return true }

            var volume = VolumeControl.volume ?? 0
            var muted = VolumeControl.isMuted
            switch key {
            case .mute:
                muted.toggle()
                VolumeControl.setMuted(muted)
            case .volumeUp:
                volume = stepped(volume, by: step)
                if muted { muted = false; VolumeControl.setMuted(false) }
                VolumeControl.setVolume(volume)
            default:
                volume = stepped(volume, by: -step)
                VolumeControl.setVolume(volume)
                if volume <= 0.001 && !muted { muted = true; VolumeControl.setMuted(true) }
                else if muted && volume > 0 { muted = false; VolumeControl.setMuted(false) }
            }
            lastVolumeEvent = (volume, muted, Date())
            events.send(HUDEvent(kind: .volume, value: volume, muted: muted))
            return true

        case .brightnessUp, .brightnessDown:
            guard BrightnessControl.isAvailable else { return false }
            guard isDown else { return true }

            let current = BrightnessControl.brightness ?? 0.5
            let value = stepped(current, by: key == .brightnessUp ? step : -step)
            BrightnessControl.setBrightness(value)
            lastBrightnessKeyPress = Date()
            brightnessAnchor = (value, Date())
            events.send(HUDEvent(kind: .brightness, value: value, muted: false))
            return true
        }
    }

    private func stepped(_ value: Float, by step: Float) -> Float {
        let snapped = (value / abs(step)).rounded() * abs(step)
        return min(1, max(0, snapped + step))
    }
}

enum MediaKey: Int {
    case volumeUp = 0
    case volumeDown = 1
    case brightnessUp = 2
    case brightnessDown = 3
    case mute = 7
}

/// CGEvent tap for the NX_SYSDEFINED "aux control" events produced by the media keys.
final class MediaKeyTap {
    typealias Handler = (MediaKey, _ isDown: Bool, _ fine: Bool) -> Bool

    private let handler: Handler
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    func start() -> Bool {
        let systemDefined: UInt32 = 14 // NX_SYSDEFINED
        let mask = CGEventMask(1 << systemDefined)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let me = Unmanaged<MediaKeyTap>.fromOpaque(refcon).takeUnretainedValue()
                return me.process(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        tap = nil
        source = nil
    }

    private func process(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        guard type.rawValue == 14,
              let nsEvent = NSEvent(cgEvent: event),
              nsEvent.subtype.rawValue == 8
        else { return Unmanaged.passUnretained(event) }

        let data = nsEvent.data1
        let keyCode = (data & 0xFFFF_0000) >> 16
        let keyFlags = data & 0x0000_FFFF
        let isDown = ((keyFlags & 0xFF00) >> 8) == 0x0A

        guard let key = MediaKey(rawValue: keyCode) else { return Unmanaged.passUnretained(event) }
        let fine = nsEvent.modifierFlags.contains([.option, .shift])

        return handler(key, isDown, fine) ? nil : Unmanaged.passUnretained(event)
    }
}
