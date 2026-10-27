import Foundation
import XCTest
@testable import OverheadCore

/// Parks a throwaway project with a real server process tree, and prints dry-run plans for real projects.
/// Skipped unless `OVERHEAD_SMOKE=1`. Never parks anything but the throwaway project.
final class ParkSmokeTests: XCTestCase {
    func testParksARealServerGroupAndKeepsItsCommand() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["OVERHEAD_SMOKE"] == "1", "set OVERHEAD_SMOKE=1")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("overhead-park-smoke-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".git"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        // Like `pnpm dev`: a leader in its own process group that starts the actual server.
        try """
        import os, subprocess, time
        os.setpgrp()
        subprocess.Popen(["python3", "-m", "http.server", "8799", "--bind", "127.0.0.1"])
        time.sleep(600)
        """.write(to: root.appendingPathComponent("leader.py"), atomically: true, encoding: .utf8)
        let leader = Process()
        leader.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        leader.arguments = ["python3", "leader.py"]
        leader.currentDirectoryURL = root
        leader.standardOutput = FileHandle.nullDevice
        leader.standardError = FileHandle.nullDevice
        try leader.run()
        defer { if leader.isRunning { leader.terminate() } }
        Thread.sleep(forTimeInterval: 2)

        // The kernel reports /private/var/…; Foundation's resolvingSymlinksInPath would strip /private again.
        let real = try XCTUnwrap(realpath(root.path, nil).map { defer { free($0) }; return String(cString: $0) })
        let project = Project(name: "smoke", path: real)
        let samples = ProcessSampler.sampleAll()
        let ports = PortScanner.report(PortScanner.listeners(pids: samples.map(\.pid)), samples: samples, projects: [project])
        let plan = Parker.plan(for: project, projects: [project], samples: samples, ports: ports, simulators: [], appsBySimulator: [:], bundleIDs: [])
        let server = try XCTUnwrap(plan.servers.first { $0.ports == [8799] }, "server on 8799 not found: \(ports.ports)")
        print("PARK server pid \(server.pid), group \(server.processGroup.map(String.init) ?? "none"), command: \(server.command)")
        let group = try XCTUnwrap(server.processGroup)
        XCTAssertEqual(group, leader.processIdentifier, "the leader's group, not the test runner's")
        XCTAssertTrue(server.command.contains("leader.py"), server.command)

        let sheet = Parker.park(plan)
        Thread.sleep(forTimeInterval: 1)
        let after = ProcessSampler.sampleAll()

        XCTAssertFalse(after.contains { $0.pid == server.pid }, "server still running")
        XCTAssertFalse(after.contains { $0.pid == leader.processIdentifier && $0.processGroup == group }, "leader still running")
        XCTAssertEqual(sheet.commands.first?.ports, [8799])
        print("PARK stopped both; sheet command: \(sheet.commands.first?.command ?? "-")")
    }

    func testDryRunPlansForRealProjects() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["OVERHEAD_SMOKE"] == "1", "set OVERHEAD_SMOKE=1")
        let projects = ProjectDiscovery.discover(home: FileManager.default.homeDirectoryForCurrentUser)
        let samples = ProcessSampler.sampleAll()
        let ports = PortScanner.report(PortScanner.listeners(pids: samples.map(\.pid)), samples: samples, projects: projects)
        let simulators = SimulatorScanner.booted(in: samples)
        var apps: [String: Set<String>] = [:]
        for simulator in simulators { apps[simulator.udid] = BundleIdentifiers.runningApps(in: simulator, samples: samples) }
        print("PLAN simulator apps: \(simulators.map { "\($0.name): \(apps[$0.udid]?.sorted() ?? [])" })")

        for project in projects where simulators.contains(where: { _ in true }) {
            let ids = BundleIdentifiers.declared(in: project.path)
            let plan = Parker.plan(for: project, projects: projects, samples: samples, ports: ports, simulators: simulators,
                                   appsBySimulator: apps, bundleIDs: ids)
            guard !plan.simulators.isEmpty || !plan.servers.isEmpty else { continue }
            print("PLAN \(project.name): servers \(plan.servers.map { "\($0.ports) \($0.process)" }), simulators \(plan.simulators.map(\.name)), agents \(plan.agents.count)")
        }
    }
}
