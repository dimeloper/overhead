import Foundation
import XCTest
@testable import OverheadCore

final class SimulatorTests: XCTestCase {
    func testReadsTheUDIDFromTheBootstrapPlistArgument() {
        let argument = "/Users/dev/Library/Developer/CoreSimulator/Devices/CB7E166C-4F22-48FD-B7AA-00E52626B728/data/var/run/launchd_bootstrap.plist"
        XCTAssertEqual(SimulatorScanner.udid(in: argument), "CB7E166C-4F22-48FD-B7AA-00E52626B728")
        XCTAssertNil(SimulatorScanner.udid(in: "/Devices/not-a-uuid/data"))
        XCTAssertNil(SimulatorScanner.udid(in: "launchd_sim"))
    }

    func testRuntimeLabels() {
        XCTAssertEqual(SimulatorScanner.runtimeLabel("com.apple.CoreSimulator.SimRuntime.iOS-27-0"), "iOS 27.0")
        XCTAssertEqual(SimulatorScanner.runtimeLabel("com.apple.CoreSimulator.SimRuntime.watchOS-11-2"), "watchOS 11.2")
    }

    func testSumsTheWholeProcessTreeUnderLaunchdSim() {
        let simulator = BootedSimulator(udid: "A", name: "iPhone", runtime: "iOS 27.0", launchdPid: 100, bootedAt: nil)
        let mb: UInt64 = 1_048_576
        let samples = [
            ProcessSample(pid: 100, name: "launchd_sim", workingDirectory: nil, footprint: 10 * mb, parentPid: 1),
            ProcessSample(pid: 101, name: "SpringBoard", workingDirectory: nil, footprint: 200 * mb, parentPid: 100),
            ProcessSample(pid: 102, name: "MyApp", workingDirectory: nil, footprint: 300 * mb, parentPid: 101),
            ProcessSample(pid: 200, name: "node", workingDirectory: nil, footprint: 999 * mb, parentPid: 1),
        ]

        let usage = SimulatorScanner.usage(of: [simulator], samples: samples, cpu: [101: 0.02, 102: 0.03])

        XCTAssertEqual(usage.first?.footprint, 510 * mb)
        XCTAssertEqual(usage.first?.processCount, 3)
        XCTAssertEqual(usage.first?.cpu ?? 0, 0.05, accuracy: 0.0001)
    }

    func testReadsTheArgumentsOfARealProcess() {
        let arguments = ProcessSampler.arguments(getpid())
        XCTAssertEqual(arguments, CommandLine.arguments)
    }
}
