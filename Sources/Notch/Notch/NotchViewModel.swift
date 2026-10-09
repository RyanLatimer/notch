import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

enum NotchState: Equatable {
    case collapsed
    case expanded
}

enum NotchTab: String, CaseIterable, Identifiable {
    case home
    case shelf

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .home: return "house.fill"
        case .shelf: return "tray.full.fill"
        }
    }
}

/// Short-lived "live activities" that widen the collapsed notch.
enum TransientActivity: Equatable {
    case charging
    case hud(HUDEvent)

    var sideWidth: CGFloat {
        switch self {
        case .charging: return 62
        case .hud: return 78
        }
    }

    /// Identity used for layout animation; HUD value changes should not re-trigger the spring.
    var layoutKey: String {
        switch self {
        case .charging: return "charging"
        case .hud(let event): return "hud-\(event.kind)"
        }
    }
}

enum DebugFlags {
    /// `NOTCH_DEMO=expanded|collapsed` loads sample media, disables hover tracking and pins the
    /// notch in that state. Used for the CI screenshots.
    static let demoMode = ProcessInfo.processInfo.environment["NOTCH_DEMO"]
    static let demo = demoMode != nil
    static let demoExpanded = demoMode == "expanded"
}

@MainActor
final class NotchViewModel: ObservableObject {
    @Published private(set) var state: NotchState = .collapsed
    @Published var tab: NotchTab = .home
    @Published private(set) var transient: TransientActivity?
    @Published private(set) var isHovering = false
    @Published private(set) var notchSize = CGSize(width: 185, height: 32)
    @Published private(set) var hasPhysicalNotch = true
    @Published var isDropTargeted = false {
        didSet {
            if isDropTargeted && !oldValue { dropEntered() }
        }
    }

    let openSettings: () -> Void

    private let settings = AppSettings.shared
    private let media = MediaManager.shared
    private var hoverTask: Task<Void, Never>?
    private var collapseTask: Task<Void, Never>?
    private var transientTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    static let musicSideWidth: CGFloat = 40
    static let panelSize = CGSize(width: 760, height: 320)

    init(openSettings: @escaping () -> Void) {
        self.openSettings = openSettings

        BatteryMonitor.shared.pluggedIn
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.showCharging() }
            .store(in: &cancellables)

        SystemHUDController.shared.events
            .receive(on: RunLoop.main)
            .sink { [weak self] event in self?.showHUD(event) }
            .store(in: &cancellables)

        settings.$enableShelf
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                if !enabled, self?.tab == .shelf { self?.tab = .home }
            }
            .store(in: &cancellables)

        if DebugFlags.demoExpanded {
            state = .expanded
        }
    }

    // MARK: - Geometry

    func updateGeometry(for screen: NSScreen) {
        notchSize = screen.notchSize
        hasPhysicalNotch = screen.hasNotch
    }

    var showsMusicActivity: Bool {
        settings.showMusicActivity && media.isPlaying
    }

    var topRadius: CGFloat { state == .expanded ? 14 : 6 }
    var bottomRadius: CGFloat { state == .expanded ? 26 : 10 }

    var expandedBodySize: CGSize {
        CGSize(width: max(500, notchSize.width + 330), height: notchSize.height + 150)
    }

    /// Size of the black body, excluding the top flares.
    var bodySize: CGSize {
        switch state {
        case .expanded:
            return expandedBodySize
        case .collapsed:
            if let transient {
                return CGSize(width: notchSize.width + 2 * transient.sideWidth, height: notchSize.height)
            }
            if showsMusicActivity {
                return CGSize(width: notchSize.width + 2 * Self.musicSideWidth, height: notchSize.height)
            }
            if isHovering {
                return CGSize(width: notchSize.width + 14, height: notchSize.height + 4)
            }
            return notchSize
        }
    }

    var frameSize: CGSize {
        let body = bodySize
        return CGSize(width: body.width + 2 * topRadius, height: body.height)
    }

    /// Area (in screen coordinates) that should capture the mouse.
    func hitRect(in screenFrame: NSRect) -> NSRect {
        let size = frameSize
        let padX: CGFloat = state == .expanded ? 10 : 8
        let padBottom: CGFloat = state == .expanded ? 14 : 6
        return NSRect(
            x: screenFrame.midX - size.width / 2 - padX,
            y: screenFrame.maxY - size.height - padBottom,
            width: size.width + 2 * padX,
            height: size.height + padBottom + 4
        )
    }

    /// Hashable summary of everything that changes the notch's outline, used to drive the spring.
    var layoutKey: String {
        "\(state)-\(transient?.layoutKey ?? "none")-\(showsMusicActivity)-\(isHovering)-\(notchSize.width)"
    }

    // MARK: - Hover & expansion

    func mouseMoved(inside: Bool, isDraggingFiles: Bool) {
        if DebugFlags.demo { return }

        if inside {
            collapseTask?.cancel()
            collapseTask = nil
            guard state == .collapsed else { return }

            if !isHovering { isHovering = true }

            if isDraggingFiles && settings.enableShelf {
                hoverTask?.cancel()
                expand(tab: .shelf)
            } else if settings.expandOnHover && hoverTask == nil {
                let delay = settings.hoverDelay
                hoverTask = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: UInt64(max(0, delay) * 1_000_000_000))
                    guard !Task.isCancelled else { return }
                    self?.hoverTask = nil
                    self?.expand()
                }
            }
        } else {
            hoverTask?.cancel()
            hoverTask = nil
            if isHovering { isHovering = false }
            if state == .expanded && collapseTask == nil {
                scheduleCollapse()
            }
        }
    }

    private func scheduleCollapse() {
        collapseTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            // Wait for an in-flight drag (scrubbing, dragging a file out of the shelf) to finish.
            while NSEvent.pressedMouseButtons & 1 != 0 {
                try? await Task.sleep(nanoseconds: 100_000_000)
                if Task.isCancelled { return }
            }
            guard !Task.isCancelled else { return }
            self?.collapseTask = nil
            self?.collapse()
        }
    }

    func expand(tab newTab: NotchTab? = nil) {
        if let newTab { tab = newTab }
        guard state != .expanded else { return }
        state = .expanded
        isHovering = false
        if settings.hapticFeedback {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
    }

    func collapse() {
        guard state != .collapsed, !DebugFlags.demo else { return }
        state = .collapsed
    }

    /// Click on the collapsed notch (used when hover-to-expand is off).
    func tappedCollapsed() {
        expand()
    }

    private func dropEntered() {
        guard settings.enableShelf else { return }
        expand(tab: .shelf)
    }

    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard settings.enableShelf else { return false }
        var accepted = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            accepted = true
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async {
                    ShelfStore.shared.add([url])
                }
            }
        }
        if accepted { expand(tab: .shelf) }
        return accepted
    }

    // MARK: - Transient activities

    private func showCharging() {
        guard settings.showChargingActivity else { return }
        showTransient(.charging, duration: 3)
    }

    private func showHUD(_ event: HUDEvent) {
        switch event.kind {
        case .volume: guard settings.showVolumeHUD else { return }
        case .brightness: guard settings.showBrightnessHUD else { return }
        }
        showTransient(.hud(event), duration: 1.6)
    }

    private func showTransient(_ activity: TransientActivity, duration: Double) {
        guard state == .collapsed else { return }
        transient = activity
        transientTask?.cancel()
        transientTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.transient = nil
        }
    }
}
