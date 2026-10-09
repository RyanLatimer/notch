import AudioToolbox
import CoreAudio
import CoreGraphics
import Foundation

// MARK: - Volume

enum VolumeControl {
    private static var defaultDeviceAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    static var volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )

    static var muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )

    static var defaultOutputDevice: AudioDeviceID? {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &defaultDeviceAddress, 0, nil, &size, &deviceID
        )
        return status == noErr && deviceID != kAudioObjectUnknown ? deviceID : nil
    }

    static var canSetVolume: Bool {
        guard let device = defaultOutputDevice else { return false }
        var address = volumeAddress
        guard AudioObjectHasProperty(device, &address) else { return false }
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(device, &address, &settable) == noErr && settable.boolValue
    }

    static var volume: Float? {
        guard let device = defaultOutputDevice else { return nil }
        var address = volumeAddress
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    static func setVolume(_ newValue: Float) {
        guard let device = defaultOutputDevice else { return }
        var address = volumeAddress
        var value = Float32(min(1, max(0, newValue)))
        let size = UInt32(MemoryLayout<Float32>.size)
        AudioObjectSetPropertyData(device, &address, 0, nil, size, &value)
    }

    static var isMuted: Bool {
        guard let device = defaultOutputDevice else { return false }
        var address = muteAddress
        guard AudioObjectHasProperty(device, &address) else { return false }
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return false }
        return value != 0
    }

    static func setMuted(_ muted: Bool) {
        guard let device = defaultOutputDevice else { return }
        var address = muteAddress
        guard AudioObjectHasProperty(device, &address) else { return }
        var value = UInt32(muted ? 1 : 0)
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }
}

/// Watches the default output device's volume and mute state, following device switches.
final class VolumeObserver {
    private let onChange: () -> Void
    private var device: AudioDeviceID = kAudioObjectUnknown
    private var registered: [AudioObjectPropertyAddress] = []
    private lazy var propertyListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        self?.onChange()
    }
    private lazy var deviceListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        self?.rebind()
    }

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
    }

    func start() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, deviceListener)
        rebind()
    }

    private func rebind() {
        if device != kAudioObjectUnknown {
            for var address in registered {
                AudioObjectRemovePropertyListenerBlock(device, &address, .main, propertyListener)
            }
        }
        registered = []
        device = VolumeControl.defaultOutputDevice ?? kAudioObjectUnknown
        guard device != kAudioObjectUnknown else { return }

        // Not every device exposes every property; register what sticks. Per-element scalars
        // cover devices whose virtual main volume doesn't send notifications.
        var candidates = [VolumeControl.volumeAddress, VolumeControl.muteAddress]
        for element: AudioObjectPropertyElement in [kAudioObjectPropertyElementMain, 1, 2] {
            candidates.append(AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: element
            ))
        }
        for var address in candidates {
            if AudioObjectAddPropertyListenerBlock(device, &address, .main, propertyListener) == noErr {
                registered.append(address)
            }
        }
    }
}

// MARK: - Brightness (private DisplayServices framework, loaded dynamically)

enum BrightnessControl {
    private typealias GetFunction = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFunction = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private typealias RegisterFunction = @convention(c) (CGDirectDisplayID, UnsafeRawPointer?, CFNotificationCallback) -> Int32

    private static let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)

    private static let getFunction: GetFunction? = symbol("DisplayServicesGetBrightness")
    private static let setFunction: SetFunction? = symbol("DisplayServicesSetBrightness")
    private static let registerFunction: RegisterFunction? = symbol("DisplayServicesRegisterForBrightnessChangeNotifications")

    private static func symbol<T>(_ name: String) -> T? {
        guard let handle, let pointer = dlsym(handle, name) else { return nil }
        return unsafeBitCast(pointer, to: T.self)
    }

    static var builtInDisplay: CGDirectDisplayID? {
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(16, &displays, &count) == .success else { return nil }
        return displays.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 }
    }

    static var isAvailable: Bool {
        getFunction != nil && setFunction != nil && builtInDisplay != nil
    }

    static var brightness: Float? {
        guard let getFunction, let display = builtInDisplay else { return nil }
        var value: Float = 0
        return getFunction(display, &value) == 0 ? value : nil
    }

    static func setBrightness(_ value: Float) {
        guard let setFunction, let display = builtInDisplay else { return }
        _ = setFunction(display, min(1, max(0, value)))
    }

    /// Invokes `SystemHUDController.brightnessDidChange` whenever the built-in panel's brightness changes.
    static func observeChanges() {
        guard let registerFunction, let display = builtInDisplay else { return }
        _ = registerFunction(display, nil) { _, _, _, _, _ in
            DispatchQueue.main.async {
                SystemHUDController.shared.brightnessDidChange()
            }
        }
    }
}
