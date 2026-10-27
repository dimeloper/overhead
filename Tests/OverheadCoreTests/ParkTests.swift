import Foundation
import XCTest
@testable import OverheadCore

final class ParkPlanTests: XCTestCase {
    private let app = Project(name: "app", path: "/code/app")
    private let other = Project(name: "other", path: "/code/other")

    private func plan(samples: [ProcessSample], ports: [PortUsage], simulators: [BootedSimulator] = [], apps: [String: Set<String>] = [:], ids: Set<String> = []) -> ParkPlan {
        Parker.plan(
            for: app, projects: [app, other], samples: samples, ports: PortReport(ports: ports, otherCount: 0),
            simulators: simulators, appsBySimulator: apps, bundleIDs: ids
        )
    }

    func testStopsTheServersGroupWhenItsLeaderIsAProjectProcess() {
        // `pnpm dev` (group leader 50) started `node` (51), which listens on 3000.
        let samples = [
            ProcessSample(pid: 50, name: "pnpm", workingDirectory: "/code/app", footprint: 0, parentPid: 40, processGroup: 50),
            ProcessSample(pid: 51, name: "node", workingDirectory: "/code/app", footprint: 0, parentPid: 50, processGroup: 50),
        ]
        let result = plan(samples: samples, ports: [PortUsage(port: 3000, pid: 51, process: "node", project: "app")])

        XCTAssertEqual(result.servers.map(\.pid), [51])
        XCTAssertEqual(result.servers.first?.processGroup, 50)
    }

    func testNeverSignalsAGroupLedByAShell() {
        let samples = [
            ProcessSample(pid: 40, name: "zsh", workingDirectory: "/code/app", footprint: 0, processGroup: 40),
            ProcessSample(pid: 41, name: "python3.13", workingDirectory: "/code/app", footprint: 0, parentPid: 40, processGroup: 40),
        ]
        let result = plan(samples: samples, ports: [PortUsage(port: 8000, pid: 41, process: "python3.13", project: "app")])

        XCTAssertNil(result.servers.first?.processGroup, "only the server itself, never the shell's group")
    }

    func testOnlyThisProjectsServersAndAgentsAreIncluded() {
        let samples = [
            ProcessSample(pid: 1, name: "node", workingDirectory: "/code/other", footprint: 0, processGroup: 1),
            ProcessSample(pid: 2, name: "claude", workingDirectory: "/code/app", footprint: 0, processGroup: 2),
            ProcessSample(pid: 3, name: "claude", workingDirectory: "/code/other", footprint: 0, processGroup: 3),
        ]
        let result = plan(samples: samples, ports: [PortUsage(port: 3000, pid: 1, process: "node", project: "other")])

        XCTAssertTrue(result.servers.isEmpty)
        XCTAssertEqual(result.agents, ["claude"])
    }

    func testShutsDownOnlySimulatorsRunningThisProjectsApp() {
        let mine = BootedSimulator(udid: "A", name: "iPhone", runtime: "iOS 27.0", launchdPid: 10, bootedAt: nil)
        let theirs = BootedSimulator(udid: "B", name: "iPad", runtime: "iOS 27.0", launchdPid: 11, bootedAt: nil)

        let result = plan(samples: [], ports: [], simulators: [mine, theirs],
                          apps: ["A": ["com.acme.app"], "B": ["com.other.app"]], ids: ["com.acme.app.widget"])

        XCTAssertEqual(result.simulators.map(\.udid), ["A"])
    }

    func testCommandsPasteBackIntoAShell() {
        XCTAssertEqual(Parker.shellCommand(["node", "server.js", "--port", "3000"], fallback: "node"), "node server.js --port 3000")
        XCTAssertEqual(Parker.shellCommand(["echo", "it's here", ""], fallback: "echo"), #"echo 'it'\''s here' ''"#)
        XCTAssertEqual(Parker.shellCommand([], fallback: "node"), "node")
        XCTAssertEqual(Parker.shellCommand(["/opt/homebrew/Cellar/python@3.14/3.14.7/Frameworks/Python.framework/Versions/3.14/Resources/Python.app/Contents/MacOS/Python", "leader.py"], fallback: "x"), "python3 leader.py")
        XCTAssertEqual(Parker.shellCommand(["/Users/dev/.nvm/versions/node/v22.11.0/bin/node", "server.js"], fallback: "x"), "node server.js")
        XCTAssertEqual(Parker.shellCommand(["/usr/local/bin/myserver"], fallback: "x"), "/usr/local/bin/myserver")
    }
}

final class ParkSheetTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("overhead-park-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".git"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    func testRecordsBranchEnvFileNamesAndToolVersionsButNeverEnvContents() throws {
        try "ref: refs/heads/feat/park\n".write(to: root.appendingPathComponent(".git/HEAD"), atomically: true, encoding: .utf8)
        try "SECRET=hunter2".write(to: root.appendingPathComponent(".env.local"), atomically: true, encoding: .utf8)
        try "22.11\n".write(to: root.appendingPathComponent(".nvmrc"), atomically: true, encoding: .utf8)
        let plan = ParkPlan(project: Project(name: "app", path: root.path), servers: [], simulators: [], agents: [], uncommittedChanges: nil)

        let sheet = Parker.sheet(for: plan, now: Date(timeIntervalSince1970: 0))

        XCTAssertEqual(sheet.branch, "feat/park")
        XCTAssertEqual(sheet.envFiles, [".env.local"])
        XCTAssertEqual(sheet.toolVersions, [".nvmrc": "22.11"])
        let encoded = String(decoding: try JSONEncoder().encode(sheet), as: UTF8.self)
        XCTAssertFalse(encoded.contains("hunter2"))
    }

    func testFollowsAWorktreesGitFileToItsBranch() throws {
        let gitDir = root.appendingPathComponent("real-git-dir")
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
        try "ref: refs/heads/fix/worktree\n".write(to: gitDir.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8)
        let checkout = root.appendingPathComponent("wt")
        try FileManager.default.createDirectory(at: checkout, withIntermediateDirectories: true)
        try "gitdir: \(gitDir.path)\n".write(to: checkout.appendingPathComponent(".git"), atomically: true, encoding: .utf8)

        XCTAssertEqual(Parker.branch(at: checkout), "fix/worktree")
    }

    func testStoreRoundTrips() throws {
        let store = ParkedStore(file: root.appendingPathComponent("parked.json"))
        let sheet = ParkedProject(name: "app", path: "/code/app", parkedAt: Date(timeIntervalSince1970: 1_000), branch: "main",
                                  commands: [.init(command: "pnpm dev", workingDirectory: "/code/app", ports: [3000])],
                                  simulators: [], envFiles: [], toolVersions: [:])
        try store.save([sheet])
        XCTAssertEqual(store.load(), [sheet])
    }
}

final class BundleIdentifierTests: XCTestCase {
    func testReadsExpoAndXcodeDeclarations() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("overhead-ids-\(UUID().uuidString)")
        let ios = root.appendingPathComponent("ios/App.xcodeproj")
        try FileManager.default.createDirectory(at: ios, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try #"{"expo": {"ios": {"bundleIdentifier": "com.acme.app"}}}"#.write(to: root.appendingPathComponent("app.json"), atomically: true, encoding: .utf8)
        try "ios: { bundleIdentifier: 'com.acme.config' },".write(to: root.appendingPathComponent("app.config.ts"), atomically: true, encoding: .utf8)
        try """
        PRODUCT_BUNDLE_IDENTIFIER = com.acme.app.widget;
        PRODUCT_BUNDLE_IDENTIFIER = "$(PRODUCT_NAME).tests";
        """.write(to: ios.appendingPathComponent("project.pbxproj"), atomically: true, encoding: .utf8)

        XCTAssertEqual(BundleIdentifiers.declared(in: root.path), ["com.acme.app", "com.acme.config", "com.acme.app.widget"])
        XCTAssertTrue(BundleIdentifiers.matches(app: "com.acme.app", declared: ["com.acme.app.widget"]))
        XCTAssertFalse(BundleIdentifiers.matches(app: "com.acme.application", declared: ["com.acme.app"]))
    }
}
