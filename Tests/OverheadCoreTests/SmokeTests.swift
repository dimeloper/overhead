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

        let ports = PortScanner.report(PortScanner.listeners(pids: samples.map(\.pid)), samples: samples, projects: projects)
        for port in ports.ports { print("  :\(port.port) \(port.process) (\(port.project ?? "outside projects"))") }
        print("listeners from other apps \(ports.otherCount)")
        for usage in SimulatorScanner.usage(of: SimulatorScanner.booted(in: samples), samples: samples, cpu: rates) {
            let sim = usage.simulator
            print("  sim \(sim.name) (\(sim.runtime)) \(sim.udid): \(ByteFormat.short(usage.footprint)), \(usage.processCount) processes, \(ByteFormat.percent(usage.cpu)) CPU, booted \(sim.bootedAt.map { "\($0)" } ?? "?")")
        }
        let busy = KeepAwakePolicy().busyReason(samples: samples, rates: rates, projects: result.projects, cores: ProcessInfo.processInfo.activeProcessorCount)
        print("automatic keep-awake would \(busy.map { "hold: \($0)" } ?? "let the Mac sleep")")

        XCTAssertGreaterThan(memory.used, 0)
        XCTAssertLessThanOrEqual(memory.used, memory.total)
        XCTAssertLessThanOrEqual(rates.values.reduce(0, +), 1.05, "sampled processes cannot use more than the whole machine")
    }
}

/// Takes and releases a real sleep assertion and checks `pmset` sees both. Skipped unless `OVERHEAD_SMOKE=1`.
final class SleepAssertionSmokeTests: XCTestCase {
    func testPmsetSeesTheAssertionWhileHeld() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["OVERHEAD_SMOKE"] == "1", "set OVERHEAD_SMOKE=1")
        let assertion = SleepAssertion()

        assertion.hold("smoke test")
        assertion.hold("smoke test renamed")
        let held = try pmsetAssertions()
        assertion.release()
        let released = try pmsetAssertions()

        XCTAssertTrue(held.contains("Overhead: smoke test renamed"), held)
        XCTAssertFalse(released.contains("Overhead: smoke test"))
    }

    private func pmsetAssertions() throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g", "assertions"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }
}
