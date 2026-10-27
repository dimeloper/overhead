import Foundation
import XCTest
@testable import OverheadCore

final class ProjectAttributionTests: XCTestCase {
    private let app = Project(name: "app", path: "/Users/dev/code/app")
    private let worktree = Project(name: "app · fix", path: "/Users/dev/code/app/.claude/worktrees/fix")
    private let api = Project(name: "api", path: "/Users/dev/code/api")

    private func sample(_ name: String, _ cwd: String?, _ mb: UInt64) -> ProcessSample {
        ProcessSample(pid: 1, name: name, workingDirectory: cwd, footprint: mb * 1_048_576)
    }

    func testChargesTheDeepestProjectSoAWorktreeGetsItsOwnRow() {
        let result = ProjectAttribution.attribute([
            sample("node", "/Users/dev/code/app", 300),
            sample("node", "/Users/dev/code/app/.claude/worktrees/fix/src", 200),
        ], to: [app, worktree])

        XCTAssertEqual(result.projects.map(\.project), [app, worktree])
        XCTAssertEqual(result.projects.map(\.footprint), [300 * 1_048_576, 200 * 1_048_576])
    }

    func testASiblingWithACommonPrefixIsNotCharged() {
        let result = ProjectAttribution.attribute([sample("python", "/Users/dev/code/app-2", 100)], to: [app])

        XCTAssertTrue(result.projects.isEmpty)
        XCTAssertEqual(result.unattributed, 100 * 1_048_576)
    }

    func testProcessesWithoutAWorkingDirectoryAreUnattributed() {
        let result = ProjectAttribution.attribute([sample("Simulator", nil, 50), sample("uvicorn", "/Users/dev/code/api", 80)], to: [app, api])

        XCTAssertEqual(result.projects.map(\.project), [api])
        XCTAssertEqual(result.unattributed, 50 * 1_048_576)
    }

    func testProcessNamesAreLargestFirstWithoutDuplicates() {
        let result = ProjectAttribution.attribute([
            sample("node", "/Users/dev/code/app", 10),
            sample("xcodebuild", "/Users/dev/code/app", 90),
            sample("node", "/Users/dev/code/app", 40),
        ], to: [app])

        XCTAssertEqual(result.projects.first?.processes, ["xcodebuild", "node"])
    }
}

final class ProjectDiscoveryTests: XCTestCase {
    private var home: URL!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("overhead-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: home)
    }

    private func makeRepo(_ path: String, worktree: Bool = false) throws {
        let url = home.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let git = url.appendingPathComponent(".git")
        if worktree {
            try "gitdir: /elsewhere".write(to: git, atomically: true, encoding: .utf8)
        } else {
            try FileManager.default.createDirectory(at: git, withIntermediateDirectories: true)
        }
    }

    func testFindsReposOneAndTwoLevelsDownAndAgentWorktrees() throws {
        try makeRepo("dotfiles")
        try makeRepo("my-apps/app")
        try makeRepo("my-apps/app/.claude/worktrees/fix", worktree: true)
        try makeRepo("my-apps/app-feature", worktree: true)
        try makeRepo("Library/Caches/thing")
        try makeRepo("a/b/too-deep")

        let names = Set(ProjectDiscovery.discover(home: home).map(\.name))

        XCTAssertEqual(names, ["dotfiles", "app", "app · fix", "app-feature"])
    }

    func testExtraFoldersAreScannedOnceEvenWhenTheyOverlapHome() throws {
        try makeRepo("Library/Work/client/api")
        try makeRepo("my-apps/app")
        let extras = [home.appendingPathComponent("Library/Work"), home.appendingPathComponent("my-apps/app")]

        let projects = ProjectDiscovery.discover(home: home, extraFolders: extras)

        XCTAssertEqual(projects.map(\.name).sorted(), ["api", "app"], "Library is skipped from home but scanned when added; app appears once")
    }
}

final class ProcessNameTests: XCTestCase {
    func testAVersionNamedBinaryTakesTheToolFolderName() {
        XCTAssertTrue(ProcessSampler.isVersion("2.1.311"))
        XCTAssertFalse(ProcessSampler.isVersion("node"))
        XCTAssertEqual(ProcessSampler.displayName(short: "2.1.311", executablePath: "/Users/dev/.local/share/claude/versions/2.1.311"), "claude")
        XCTAssertEqual(ProcessSampler.displayName(short: "1.0", executablePath: "/opt/tool/bin/1.0"), "1.0")
    }
}

final class ByteFormatTests: XCTestCase {
    func testOneDecimalFromAGigabyteUp() {
        XCTAssertEqual(ByteFormat.short(6_550_000_000), "6.1 GB")
        XCTAssertEqual(ByteFormat.short(860_000_000), "820 MB")
    }
}
