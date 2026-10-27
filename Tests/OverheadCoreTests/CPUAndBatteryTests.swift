import Foundation
import XCTest
@testable import OverheadCore

final class ActivityTrackerTests: XCTestCase {
    private func sample(_ pid: pid_t, cpuSeconds: Double) -> ProcessSample {
        ProcessSample(pid: pid, name: "p\(pid)", workingDirectory: nil, footprint: 0, cpuTime: UInt64(cpuSeconds * 1_000_000_000))
    }

    func testRateIsShareOfTheWholeMachine() {
        var tracker = ActivityTracker(cores: 4)
        let start = Date(timeIntervalSince1970: 1_000)

        XCTAssertTrue(tracker.update([sample(1, cpuSeconds: 10)], at: start).isEmpty)
        // 2 s of CPU over 1 s of wall time on 4 cores: half the machine.
        let rates = tracker.update([sample(1, cpuSeconds: 12)], at: start.addingTimeInterval(1))

        XCTAssertEqual(rates[1] ?? -1, 0.5, accuracy: 0.0001)
    }

    func testAReusedPidIsSkippedRatherThanReportedAsNegative() {
        var tracker = ActivityTracker(cores: 1)
        let start = Date(timeIntervalSince1970: 1_000)
        _ = tracker.update([sample(7, cpuSeconds: 50)], at: start)

        let rates = tracker.update([sample(7, cpuSeconds: 1)], at: start.addingTimeInterval(1))

        XCTAssertNil(rates[7])
    }

    func testCPUTimeIsConvertedFromMachTicks() {
        let (numer, denom) = ProcessSampler.timebase
        XCTAssertEqual(ProcessSampler.nanoseconds(denom * 1_000), numer * 1_000)
    }

    func testAttributionSumsCPUPerProject() {
        let project = Project(name: "app", path: "/code/app")
        let samples = [
            ProcessSample(pid: 1, name: "node", workingDirectory: "/code/app", footprint: 1),
            ProcessSample(pid: 2, name: "xcodebuild", workingDirectory: "/code/app/ios", footprint: 1),
        ]

        let result = ProjectAttribution.attribute(samples, cpu: [1: 0.1, 2: 0.25], to: [project])

        XCTAssertEqual(result.projects.first?.cpu ?? 0, 0.35, accuracy: 0.0001)
    }

    func testMachineLoadBetweenTwoReadings() {
        let before = CPUTicks(busy: 100, idle: 300)
        let after = CPUTicks(busy: 130, idle: 370)
        XCTAssertEqual(after.load(since: before), 0.3, accuracy: 0.0001)
    }
}

final class BatteryTests: XCTestCase {
    /// Apple silicon shape: mAh inside `BatteryData`, amperage as an unsigned 64-bit pattern of a negative number.
    func testParsesAppleSiliconPropertiesWhileDischarging() throws {
        let properties: [String: Any] = [
            "Voltage": NSNumber(value: 12_000),
            "Amperage": NSNumber(value: UInt64(bitPattern: -1_250)),
            "CurrentCapacity": NSNumber(value: 64),
            "ExternalConnected": false,
            "IsCharging": false,
            "BatteryData": ["AppleRawCurrentCapacity": NSNumber(value: 4_000)],
        ]

        let reading = try XCTUnwrap(BatteryReading.parse(properties))

        XCTAssertEqual(reading.percent, 64)
        XCTAssertEqual(reading.dischargeWatts, 15, accuracy: 0.001)
        XCTAssertEqual(reading.remainingWattHours, 48, accuracy: 0.001)
        XCTAssertFalse(reading.onExternalPower)
    }

    func testChargingReadsAsNoDischarge() throws {
        let properties: [String: Any] = [
            "Voltage": NSNumber(value: 13_000), "Amperage": NSNumber(value: 2_000),
            "AppleRawCurrentCapacity": NSNumber(value: 5_000), "ExternalConnected": true, "IsCharging": true,
        ]

        let reading = try XCTUnwrap(BatteryReading.parse(properties))

        XCTAssertLessThan(reading.dischargeWatts, 0)
        XCTAssertTrue(reading.isCharging)
    }

    func testNoVoltageMeansNoBattery() {
        XCTAssertNil(BatteryReading.parse(["Amperage": NSNumber(value: 0)]))
    }

    func testRunwayUsesTheAverageDrawInTheWindow() {
        var history = PowerHistory(window: 600)
        let start = Date(timeIntervalSince1970: 0)
        history.add(100, at: start)  // falls out of the window below
        history.add(10, at: start.addingTimeInterval(700))
        history.add(20, at: start.addingTimeInterval(703))

        XCTAssertEqual(history.averageWatts ?? 0, 15, accuracy: 0.001)
        // 45 Wh at 15 W: 3 hours.
        XCTAssertEqual(history.runway(remainingWattHours: 45) ?? 0, 3 * 3600, accuracy: 1)
    }

    func testNoRunwayWithoutMeasurableDraw() {
        var history = PowerHistory()
        history.add(0.1, at: Date())
        XCTAssertNil(history.runway(remainingWattHours: 50))
        history.reset()
        XCTAssertNil(history.averageWatts)
    }

    func testDurations() {
        XCTAssertEqual(ByteFormat.duration(2 * 3600 + 40 * 60), "2 h 40 m")
        XCTAssertEqual(ByteFormat.duration(35 * 60), "35 m")
        XCTAssertEqual(ByteFormat.clock(2 * 3600 + 5 * 60), "2:05")
        XCTAssertEqual(ByteFormat.percent(0.004), "<1%")
        XCTAssertEqual(ByteFormat.percent(0.22), "22%")
    }
}
