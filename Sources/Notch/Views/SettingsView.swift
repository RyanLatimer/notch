import ApplicationServices
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @ObservedObject var media = MediaManager.shared
    @State var launchAtLogin = LaunchAtLogin.isEnabled
    @State var accessibilityTrusted = AXIsProcessTrusted()

    let refresh = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { newValue in
                        LaunchAtLogin.setEnabled(newValue)
                        launchAtLogin = LaunchAtLogin.isEnabled
                    }
                ))
                Toggle("Show menu bar icon", isOn: $settings.showMenuBarIcon)
                Toggle("Show on displays without a notch", isOn: $settings.showOnNonNotchDisplays)
            }

            Section("Interaction") {
                Toggle("Open when hovering", isOn: $settings.expandOnHover)
                if settings.expandOnHover {
                    HStack {
                        Text("Hover delay")
                        Slider(value: $settings.hoverDelay, in: 0...1, step: 0.05)
                        Text(String(format: "%.2fs", settings.hoverDelay))
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                } else {
                    Text("Click the notch to open it.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Toggle("Haptic feedback", isOn: $settings.hapticFeedback)
            }

            Section("Live activities") {
                Toggle("Now playing", isOn: $settings.showMusicActivity)
                Toggle("Tint visualizer with album colors", isOn: $settings.artworkTintedVisualizer)
                Toggle("Charging", isOn: $settings.showChargingActivity)
                Toggle("Volume", isOn: $settings.showVolumeHUD)
                Toggle("Brightness", isOn: $settings.showBrightnessHUD)
            }

            Section {
                Toggle("Replace the system volume & brightness HUD", isOn: $settings.replaceSystemHUD)
                if settings.replaceSystemHUD && !accessibilityTrusted {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Needs Accessibility access to intercept the volume and brightness keys.")
                            .font(.caption)
                        Spacer()
                        Button("Open Settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }
            } header: {
                Text("System HUD")
            } footer: {
                Text("When on, the volume and brightness keys are handled by Notch and the macOS overlay is hidden. Hold ⌥⇧ for finer steps.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Widgets") {
                Toggle("Calendar", isOn: $settings.showCalendar)
                Toggle("File shelf", isOn: $settings.enableShelf)
            }

            Section {
                Picker("Source", selection: $settings.mediaSource) {
                    ForEach(MediaSourcePreference.allCases) { source in
                        Text(source.title).tag(source)
                    }
                }
                HStack {
                    Text(media.sourceDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Restart") { media.restart() }
                }
            } header: {
                Text("Media")
            }

            Section("About") {
                HStack {
                    Text("Notch")
                    Spacer()
                    Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")")
                        .foregroundColor(.secondary)
                }
                Button("Quit Notch") { NSApp.terminate(nil) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 540, height: 640)
        .onReceive(refresh) { _ in
            accessibilityTrusted = AXIsProcessTrusted()
            launchAtLogin = LaunchAtLogin.isEnabled
        }
    }
}
