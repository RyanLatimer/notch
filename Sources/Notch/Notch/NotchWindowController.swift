import AppKit
import Combine
import SwiftUI

/// Owns the notch panel, keeps it pinned to the notched screen, and decides when it should
/// capture the mouse. Outside the notch the panel ignores mouse events entirely so it never
/// blocks the menu bar.
@MainActor
final class NotchWindowController {
    private let viewModel: NotchViewModel
    private let panel: NotchPanel
    private var screen: NSScreen?
    private var monitors: [Any] = []
    private var cancellables = Set<AnyCancellable>()

    init(openSettings: @escaping () -> Void) {
        viewModel = NotchViewModel(openSettings: openSettings)
        panel = NotchPanel(contentRect: NSRect(origin: .zero, size: NotchViewModel.panelSize))

        let hostingView = NotchHostingView(rootView: NotchRootView(vm: viewModel))
        hostingView.sizingOptions = []
        hostingView.frame = NSRect(origin: .zero, size: NotchViewModel.panelSize)
        panel.contentView = hostingView

        positionPanel()
        installMouseMonitors()

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.positionPanel() }
            .store(in: &cancellables)

        AppSettings.shared.$showOnNonNotchDisplays
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.positionPanel() }
            .store(in: &cancellables)

        if DebugFlags.demo {
            panel.ignoresMouseEvents = false
        }
    }

    private func targetScreen() -> NSScreen? {
        if let notched = NSScreen.screens.first(where: { $0.hasNotch }) {
            return notched
        }
        if AppSettings.shared.showOnNonNotchDisplays || DebugFlags.demo {
            return NSScreen.main ?? NSScreen.screens.first
        }
        return nil
    }

    private func positionPanel() {
        guard let target = targetScreen() else {
            screen = nil
            panel.orderOut(nil)
            return
        }
        screen = target
        viewModel.updateGeometry(for: target)

        let size = NotchViewModel.panelSize
        let frame = NSRect(
            x: target.frame.midX - size.width / 2,
            y: target.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }

    private func installMouseMonitors() {
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseUp]

        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            let type = event.type
            MainActor.assumeIsolated { self?.handleMouse(type: type) }
        }) {
            monitors.append(global)
        }

        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            let type = event.type
            MainActor.assumeIsolated { self?.handleMouse(type: type) }
            return event
        }) {
            monitors.append(local)
        }
    }

    private func handleMouse(type: NSEvent.EventType) {
        guard let screen, !DebugFlags.demo else { return }
        let location = NSEvent.mouseLocation
        let inside = viewModel.hitRect(in: screen.frame).contains(location)
        let draggingFiles = type == .leftMouseDragged && inside && Self.dragPasteboardHasFiles()

        if panel.ignoresMouseEvents == inside {
            panel.ignoresMouseEvents = !inside
        }
        viewModel.mouseMoved(inside: inside, isDraggingFiles: draggingFiles)
    }

    private static func dragPasteboardHasFiles() -> Bool {
        NSPasteboard(name: .drag).types?.contains(.fileURL) ?? false
    }
}
