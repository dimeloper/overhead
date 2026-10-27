import Foundation
import IOKit

/// One reading of the internal battery, from the `AppleSmartBattery` service.
public struct BatteryReading: Sendable, Equatable {
    public var percent: Int
    public var remainingWattHours: Double
    /// Power leaving the battery, in watts. Zero or less while charging or on power.
    public var dischargeWatts: Double
    public var onExternalPower: Bool
    public var isCharging: Bool

    public init(percent: Int, remainingWattHours: Double, dischargeWatts: Double, onExternalPower: Bool, isCharging: Bool) {
        self.percent = percent
        self.remainingWattHours = remainingWattHours
        self.dischargeWatts = dischargeWatts
        self.onExternalPower = onExternalPower
        self.isCharging = isCharging
    }

    /// Nil on a Mac without a battery.
    public static func read() -> BatteryReading? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dictionary = properties?.takeRetainedValue() as? [String: Any] else { return nil }
        return parse(dictionary)
    }

    /// Apple silicon keeps the mAh figures inside `BatteryData`; Intel Macs keep them at the top level. Amperage is
    /// signed but often arrives as its unsigned 64-bit pattern.
    static func parse(_ properties: [String: Any]) -> BatteryReading? {
        let data = properties["BatteryData"] as? [String: Any] ?? [:]
        func int(_ key: String) -> Int64? {
            guard let number = (properties[key] ?? data[key]) as? NSNumber else { return nil }
            return Int64(bitPattern: number.uint64Value)
        }
        guard let millivolts = int("Voltage"), millivolts > 0,
              let remaining = int("AppleRawCurrentCapacity") ?? int("RemainingCapacity") else { return nil }
        let milliamps = int("Amperage") ?? int("InstantAmperage") ?? 0
        let volts = Double(millivolts) / 1000
        return BatteryReading(
            percent: Int(int("CurrentCapacity") ?? 0),
            remainingWattHours: Double(remaining) / 1000 * volts,
            dischargeWatts: Double(-milliamps) / 1000 * volts,
            onExternalPower: (properties["ExternalConnected"] as? Bool) ?? false,
            isCharging: (properties["IsCharging"] as? Bool) ?? false
        )
    }
}

/// Recent battery draw, so the estimate follows how you are working now instead of jumping with every spike.
public struct PowerHistory {
    private var readings: [(at: Date, watts: Double)] = []
    public let window: TimeInterval

    public init(window: TimeInterval = 600) {
        self.window = window
    }

    public mutating func add(_ watts: Double, at now: Date) {
        readings.append((now, watts))
        readings.removeAll { now.timeIntervalSince($0.at) > window }
    }

    /// Plugging in starts a new pace: draw from before the charger means nothing for the next discharge.
    public mutating func reset() {
        readings.removeAll()
    }

    public var averageWatts: Double? {
        guard !readings.isEmpty else { return nil }
        return readings.map(\.watts).reduce(0, +) / Double(readings.count)
    }

    /// Time left on battery at the average draw. Nil without enough draw to measure.
    public func runway(remainingWattHours: Double) -> TimeInterval? {
        guard let watts = averageWatts, watts >= 0.5 else { return nil }
        return remainingWattHours / watts * 3600
    }
}
