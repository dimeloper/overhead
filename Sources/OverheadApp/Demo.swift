import Foundation
import OverheadCore

/// Made-up projects for `--demo`, so screenshots for the README never show anyone's real work.
enum Demo {
    static let home = "/Users/you/code"
    private static let gb: UInt64 = 1 << 30
    private static let mb: UInt64 = 1 << 20

    static let storefront = Project(name: "storefront", path: "\(home)/storefront")
    static let redesign = Project(name: "storefront · checkout-redesign", path: "\(home)/storefront/.claude/worktrees/checkout-redesign")
    static let trailApp = Project(name: "trail-app", path: "\(home)/trail-app")
    static let api = Project(name: "billing-api", path: "\(home)/billing-api")
    static let docs = Project(name: "docs", path: "\(home)/docs")

    static let memory = SystemMemory(total: 36 * gb, used: 27 * gb + 410 * mb, swapUsed: 1 * gb + 200 * mb, pressure: .normal)
    static let cpuLoad = 0.34
    static let battery = BatteryReading(percent: 72, remainingWattHours: 49.6, dischargeWatts: 11.2, onExternalPower: false, isCharging: false)
    static let runway: TimeInterval = 4 * 3600 + 25 * 60
    static let awakeReason = "trail-app is running xcodebuild"

    static let attribution = Attribution(projects: [
        ProjectUsage(project: trailApp, footprint: 4 * gb + 300 * mb, cpu: 0.21, processes: ["xcodebuild", "node", "watchman"]),
        ProjectUsage(project: storefront, footprint: 3 * gb + 100 * mb, cpu: 0.06, processes: ["node", "claude", "pnpm"], agentSessions: 1, agentTools: 5),
        ProjectUsage(project: redesign, footprint: 1 * gb + 600 * mb, cpu: 0.04, processes: ["claude", "node"], agentSessions: 2, agentTools: 7),
        ProjectUsage(project: api, footprint: 820 * mb, cpu: 0.01, processes: ["python3.13", "celery", "zsh"]),
        ProjectUsage(project: docs, footprint: 240 * mb, cpu: 0.004, processes: ["node"]),
    ], unattributed: 9 * gb)

    static let ports = PortReport(ports: [
        PortUsage(port: 3000, pid: 501, process: "node", project: storefront.name),
        PortUsage(port: 4321, pid: 502, process: "node", project: docs.name),
        PortUsage(port: 5432, pid: 503, process: "postgres", project: nil),
        PortUsage(port: 8000, pid: 504, process: "python3.13", project: api.name),
        PortUsage(port: 8081, pid: 505, process: "node", project: trailApp.name),
    ], otherCount: 6)

    static let iPhone = BootedSimulator(udid: "DEMO-IPHONE", name: "iPhone 17 Pro", runtime: "iOS 27.0", launchdPid: 600,
                                        bootedAt: Date().addingTimeInterval(-3 * 3600))
    static let simulators = [SimulatorUsage(simulator: iPhone, footprint: 6 * gb + 400 * mb, cpu: 0.02, processCount: 288)]

    static let parked = [
        ParkedProject(
            name: "landing-page", path: "\(home)/landing-page", parkedAt: Date().addingTimeInterval(-26 * 3600), branch: "main",
            commands: [.init(command: "pnpm dev", workingDirectory: "\(home)/landing-page", ports: [5173])],
            simulators: [], envFiles: [".env.local"], toolVersions: [".nvmrc": "22"]
        ),
    ]

    /// What Park would do for `project`: the demo's servers and, for the mobile app, its simulator.
    static func plan(for project: Project) -> ParkPlan {
        let servers = ports.ports.filter { $0.project == project.name }.map { port in
            ServerToStop(pid: port.pid, ports: [port.port], process: port.process, processGroup: port.pid,
                         command: project == trailApp ? "npx expo start" : "pnpm dev", workingDirectory: project.path)
        }
        let usage = attribution.projects.first { $0.project == project }
        return ParkPlan(project: project, servers: servers, simulators: project == trailApp ? [iPhone] : [],
                        agents: (usage?.agentSessions ?? 0) > 0 ? ["claude"] : [], uncommittedChanges: project == trailApp ? 3 : 0)
    }
}
