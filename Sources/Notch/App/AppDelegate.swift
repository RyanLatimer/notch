import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var notchController: NotchWindowController?
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        MediaManager.shared.start()
        BatteryMonitor.shared.start()
        SystemHUDController.shared.start()
        CalendarService.shared.start()

        notchController = NotchWindowController(openSettings: { [weak self] in
            self?.openSettings()
        })

        AppSettings.shared.$showMenuBarIcon
            .receive(on: RunLoop.main)
            .sink { [weak self] show in self?.setStatusItemVisible(show) }
            .store(in: &cancellables)

        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "hasLaunchedBefore") {
            defaults.set(true, forKey: "hasLaunchedBefore")
            openSettings()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MediaManager.shared.stop()
    }

    // Re-opening the app from Finder/Spotlight while it is already running shows settings,
    // which is the only way back in if the menu bar icon is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return false
    }

    // MARK: - Status item

    private func setStatusItemVisible(_ visible: Bool) {
        if visible, statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            if let image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "Notch") {
                image.isTemplate = true
                item.button?.image = image
            } else {
                item.button?.title = "◗"
            }

            let menu = NSMenu()
            let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettingsAction), keyEquivalent: ",")
            settingsItem.target = self
            menu.addItem(settingsItem)

            let restartItem = NSMenuItem(title: "Restart Media Service", action: #selector(restartMedia), keyEquivalent: "")
            restartItem.target = self
            menu.addItem(restartItem)

            menu.addItem(.separator())
            menu.addItem(NSMenuItem(title: "Quit Notch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
            item.menu = menu
            statusItem = item
        } else if !visible, let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    @objc private func openSettingsAction() {
        openSettings()
    }

    @objc private func restartMedia() {
        MediaManager.shared.restart()
    }

    // MARK: - Settings window

    func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 540, height: 640),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Notch Settings"
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: SettingsView())
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
