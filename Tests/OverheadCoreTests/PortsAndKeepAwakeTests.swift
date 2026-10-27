import Foundation
import XCTest
@testable import OverheadCore

final class PortReportTests: XCTestCase {
    private let app = Project(name: "app", path: "/code/app")

    func testKeepsProjectServersAndKnownDevServersAndCountsTheRest() {
        let samples = [
            ProcessSample(pid: 10, name: "node", workingDirectory: "/code/app", footprint: 1),
            ProcessSample(pid: 11, name: "postgres", workingDirectory: "/opt/homebrew/var/postgresql", footprint: 1),
            ProcessSample(pid: 12, name: "com.docker.backend", workingDirectory: nil, footprint: 1),
            ProcessSample(pid: 13, name: "Spotify", workingDirectory: nil, footprint: 1),
        ]
        let listeners = [
            Listener(port: 8081, pid: 10), Listener(port: 5432, pid: 11), Listener(port: 5432, pid: 12),
            Listener(port: 57621, pid: 13), Listener(port: 9999, pid: 99),
        ]

        let report = PortScanner.report(listeners, samples: samples, projects: [app])

        XCTAssertEqual(report.ports.map(\.port), [8081, 5432, 5432])
        XCTAssertEqual(report.ports.map(\.process), ["node", "postgres", "Docker"])
        XCTAssertEqual(report.ports.map(\.project), ["app", nil, nil])
        XCTAssertEqual(report.otherCount, 2, "Spotify, and a pid that was not sampled")
    }
}

final class KeepAwakePolicyTests: XCTestCase {
    private let cores = 4
    private func sample(_ pid: pid_t, _ name: String) -> ProcessSample {
        ProcessSample(pid: pid, name: name, workingDirectory: nil, footprint: 0)
    }

    func testAnIdleAgentSessionDoesNotHold() {
        let policy = KeepAwakePolicy()
        // claude at 1% of one core: open, but waiting for you.
        let reason = policy.busyReason(samples: [sample(1, "claude")], rates: [1: 0.01 / 4], projects: [], cores: cores)
        XCTAssertNil(reason)
    }

    func testABusyBuildToolHoldsAndNamesItsProject() {
        let policy = KeepAwakePolicy()
        let project = ProjectUsage(project: Project(name: "app", path: "/code/app"), footprint: 0, cpu: 0.5, processes: ["xcodebuild"])

        let reason = policy.busyReason(samples: [sample(1, "xcodebuild")], rates: [1: 0.5], projects: [project], cores: cores)

        XCTAssertEqual(reason, "app is running xcodebuild")
    }

    func testABusyProjectWithoutAWatchedToolHolds() {
        let policy = KeepAwakePolicy()
        let project = ProjectUsage(project: Project(name: "api", path: "/code/api"), footprint: 0, cpu: 0.2, processes: ["pytest"])
        XCTAssertEqual(policy.busyReason(samples: [], rates: [:], projects: [project], cores: cores), "api is busy")
    }

    func testHoldsForTwoMinutesAfterTheWorkStops() {
        var policy = KeepAwakePolicy()
        let start = Date(timeIntervalSince1970: 0)

        XCTAssertEqual(policy.evaluate(busy: "app is busy", at: start), "app is busy")
        XCTAssertEqual(policy.evaluate(busy: nil, at: start.addingTimeInterval(119)), "app is busy")
        XCTAssertNil(policy.evaluate(busy: nil, at: start.addingTimeInterval(121)))
    }
}
