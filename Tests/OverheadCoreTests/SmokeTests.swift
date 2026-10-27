import Foundation
import XCTest
@testable import OverheadCore

/// Reads this Mac, read-only, and prints what the popover would show. Skipped unless `OVERHEAD_SMOKE=1`.
final class SmokeTests: XCTestCase {
    func testReportOnThisMac() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["OVERHEAD_SMOKE"] == "1", "set OVERHEAD_SMOKE=1")

        let memory = try SystemMemory.read()
        let samples = ProcessSampler.sampleAll()
        let projects = ProjectDiscovery.discover(home: FileManager.default.homeDirectoryForCurrentUser)
        let result = ProjectAttribution.attribute(samples, to: projects)

        print("memory used \(ByteFormat.short(memory.used)) of \(ByteFormat.short(memory.total)), swap \(ByteFormat.short(memory.swapUsed)), pressure \(memory.pressure.label)")
        print("processes sampled \(samples.count), with a working directory \(samples.filter { $0.workingDirectory != nil }.count)")
        print("checkouts found \(projects.count)")
        for usage in result.projects.prefix(10) {
            print("  \(usage.project.name): \(ByteFormat.short(usage.footprint)) [\(usage.processes.prefix(5).joined(separator: ", "))]")
        }
        print("unattributed \(ByteFormat.short(result.unattributed))")

        XCTAssertGreaterThan(memory.used, 0)
        XCTAssertLessThanOrEqual(memory.used, memory.total)
        XCTAssertFalse(samples.isEmpty)
    }
}
