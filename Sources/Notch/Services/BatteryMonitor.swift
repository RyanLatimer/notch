import Combine
import Foundation
import IOKit.ps

final class BatteryMonitor: ObservableObject {
    static let shared = BatteryMonitor()

    @Published private(set) var level = 100
    @Published private(set) var isCharging = false
    @Published private(set) var isPluggedIn = false
    @Published private(set) var hasBattery = false

    /// Fires when a power adapter is connected.
    let pluggedIn = PassthroughSubject<Void, Never>()

    private var runLoopSource: CFRunLoopSource?

    private init() {}

    func start() {
        update(initial: true)

        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue().update(initial: false)
        }, context)?.takeRetainedValue() else { return }

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        runLoopSource = source
    }

    private func update(initial: Bool) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return }

        var foundBattery = false
        var newLevel = level
        var charging = false
        var plugged = false

        for source in list {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  (description[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType
            else { continue }

            foundBattery = true
            let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = description[kIOPSMaxCapacityKey] as? Int ?? 100
            newLevel = max > 0 ? Int((Double(current) / Double(max) * 100).rounded()) : current
            charging = description[kIOPSIsChargingKey] as? Bool ?? false
            plugged = (description[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        }

        let wasPluggedIn = isPluggedIn
        hasBattery = foundBattery
        level = newLevel
        isCharging = charging
        isPluggedIn = plugged

        if !initial && plugged && !wasPluggedIn {
            pluggedIn.send()
        }
    }
}
