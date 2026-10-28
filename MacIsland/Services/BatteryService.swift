import Foundation
import IOKit.ps
import Observation

struct BatterySnapshot: Equatable {
    var hasBattery = false
    var level = 0
    var isCharging = false
    var isCharged = false
    var isPluggedIn = false
    var timeToEmptyMinutes: Int?
    var timeToFullMinutes: Int?
    var adapterWatts: Int?

    var symbolName: String {
        if isCharging || (isPluggedIn && isCharged) { return "battery.100percent.bolt" }
        switch level {
        case ..<10: return "battery.0percent"
        case ..<35: return "battery.25percent"
        case ..<65: return "battery.50percent"
        case ..<90: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    /// Human readable remaining time, only when macOS reports a reliable estimate.
    var estimateText: String? {
        func format(_ minutes: Int) -> String {
            let h = minutes / 60, m = minutes % 60
            return h > 0 ? "\(h) h \(String(format: "%02d", m)) min" : "\(m) min"
        }
        if isPluggedIn, let ttf = timeToFullMinutes { return "\(format(ttf)) until full" }
        if !isPluggedIn, let tte = timeToEmptyMinutes { return "\(format(tte)) remaining" }
        return nil
    }
}

/// IOKit power-source observer. Event-driven through `IOPSNotificationCreateRunLoopSource`.
@MainActor
@Observable
final class BatteryService {
    private(set) var snapshot = BatterySnapshot()
    @ObservationIgnored var onChange: ((BatterySnapshot, BatterySnapshot) -> Void)?
    @ObservationIgnored private var runLoopSource: CFRunLoopSource?

    func start() {
        snapshot = Self.read()
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let service = Unmanaged<BatteryService>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in service.update() }
        }, context)?.takeRetainedValue() else {
            Log.system.error("IOPSNotificationCreateRunLoopSource failed")
            return
        }
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        Log.system.notice("battery: \(self.snapshot.level)% plugged=\(self.snapshot.isPluggedIn) charging=\(self.snapshot.isCharging)")
    }

    func update() {
        let new = Self.read()
        let old = snapshot
        guard new != old else { return }
        snapshot = new
        onChange?(new, old)
    }

    nonisolated static func read() -> BatterySnapshot {
        var result = BatterySnapshot()
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            return result
        }
        if let providing = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() {
            result.isPluggedIn = (providing as String) == kIOPSACPowerValue
        }
        for source in list {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any] else { continue }
            guard (description[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            result.hasBattery = true
            let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = description[kIOPSMaxCapacityKey] as? Int ?? 100
            result.level = max > 0 ? Int((Double(current) / Double(max) * 100).rounded()) : current
            result.isCharging = description[kIOPSIsChargingKey] as? Bool ?? false
            result.isCharged = description[kIOPSIsChargedKey] as? Bool ?? false
            if let state = description[kIOPSPowerSourceStateKey] as? String {
                result.isPluggedIn = state == kIOPSACPowerValue
            }
            if let tte = description[kIOPSTimeToEmptyKey] as? Int, tte > 0 { result.timeToEmptyMinutes = tte }
            if let ttf = description[kIOPSTimeToFullChargeKey] as? Int, ttf > 0 { result.timeToFullMinutes = ttf }
        }
        if let adapter = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any],
           let watts = adapter[kIOPSPowerAdapterWattsKey] as? Int {
            result.adapterWatts = watts
        }
        return result
    }
}
