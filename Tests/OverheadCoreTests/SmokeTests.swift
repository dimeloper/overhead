import Foundation
import XCTest
@testable import OverheadCore

/// Reads this Mac, read-only, and prints what the popover would show. Skipped unless `OVERHEAD_SMOKE=1`.
final class SmokeTests: XCTestCase {
    func testReportOnThisMac() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["OVERHEAD_SMOKE"] == "1", "set OVERHEAD_SMOKE=1")

        let projects = ProjectDiscovery.discover(home: FileManager.default.homeDirectoryForCurrentUser)
        var tracker = ActivityTracker()
        let ticksBefore = try XCTUnwrap(CPUTicks.read())
        _ = tracker.update(ProcessSampler.sampleAll(), at: Date())
        Thread.sleep(forTimeInterval: 3)
        let samples = ProcessSampler.sampleAll()
        let rates = tracker.update(samples, at: Date())
        let load = try XCTUnwrap(CPUTicks.read()).load(since: ticksBefore)
        let memory = try SystemMemory.read()
        let result = ProjectAttribution.attribute(samples, cpu: rates, to: projects)

        print("memory used \(ByteFormat.short(memory.used)) of \(ByteFormat.short(memory.total)), swap \(ByteFormat.short(memory.swapUsed)), pressure \(memory.pressure.label)")
        print("machine CPU \(ByteFormat.percent(load)); sampled processes add up to \(ByteFormat.percent(rates.values.reduce(0, +)))")
        print("processes sampled \(samples.count), checkouts found \(projects.count)")
        for usage in result.projects.prefix(10) {
            print("  \(usage.project.name): \(ByteFormat.short(usage.footprint)), \(ByteFormat.percent(usage.cpu)) CPU [\(usage.processes.prefix(4).joined(separator: ", "))]")
        }
        if let battery = BatteryReading.read() {
            print("battery \(battery.percent)%, \(String(format: "%.1f", battery.remainingWattHours)) Wh left, draw \(String(format: "%.1f", battery.dischargeWatts)) W, external power \(battery.onExternalPower), charging \(battery.isCharging)")
        } else {
            print("no battery")
        }

        XCTAssertGreaterThan(memory.used, 0)
        XCTAssertLessThanOrEqual(memory.used, memory.total)
        XCTAssertLessThanOrEqual(rates.values.reduce(0, +), 1.05, "sampled processes cannot use more than the whole machine")
    }
}
