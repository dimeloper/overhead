import Foundation
import OverheadCore

@MainActor
final class OverheadModel: ObservableObject {
    @Published private(set) var memory: SystemMemory?
    @Published private(set) var attribution = Attribution(projects: [], unattributed: 0)
    @Published private(set) var cpuLoad: Double?
    @Published private(set) var battery: BatteryReading?
    @Published private(set) var runway: TimeInterval?
    @Published private(set) var ports = PortReport(ports: [], otherCount: 0)
    @Published private(set) var awakeReason: String?
    @Published private(set) var lastError: String?
    @Published var keepAwake: KeepAwakeMode {
        didSet {
            UserDefaults.standard.set(keepAwake.rawValue, forKey: Self.keepAwakeKey)
            updateAssertion(busy: nil, now: Date())
        }
    }

    private static let keepAwakeKey = "keepAwakeMode"

    private var projects: [Project] = []
    private var projectsScannedAt = Date.distantPast
    private var tracker = ActivityTracker()
    private var previousTicks: CPUTicks?
    private var power = PowerHistory()
    private var policy = KeepAwakePolicy()
    private let assertion = SleepAssertion()
    private var refreshCount = 0
    private var timer: Timer?

    /// Sampling is cheap (a few ms for ~1,000 processes); finding checkouts walks the disk, so it runs once a minute.
    private let sampleInterval: TimeInterval = 3
    private let projectRescanInterval: TimeInterval = 60
    /// Reading every socket of every process costs more than sampling, and ports change rarely.
    private let portScanEvery = 3

    init() {
        keepAwake = UserDefaults.standard.string(forKey: Self.keepAwakeKey).flatMap(KeepAwakeMode.init) ?? .automatic
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: sampleInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    var menuTitle: String {
        guard let memory else { return "—" }
        let used = ByteFormat.short(memory.used)
        guard let runway, battery?.onExternalPower == false else { return used }
        return "\(used) · \(ByteFormat.clock(runway))"
    }

    var isHoldingAwake: Bool { awakeReason != nil }

    func refresh() {
        let rescan = Date().timeIntervalSince(projectsScannedAt) > projectRescanInterval
        let scanPorts = refreshCount % portScanEvery == 0
        refreshCount += 1
        let known = projects
        Task.detached(priority: .utility) {
            let found = rescan ? ProjectDiscovery.discover(home: FileManager.default.homeDirectoryForCurrentUser) : known
            let samples = ProcessSampler.sampleAll()
            let listeners = scanPorts ? PortScanner.listeners(pids: samples.map(\.pid)) : nil
            let ticks = CPUTicks.read()
            let battery = BatteryReading.read()
            let memory = Result { try SystemMemory.read() }
            await MainActor.run {
                self.apply(found: rescan ? found : nil, samples: samples, listeners: listeners, ticks: ticks, battery: battery, memory: memory)
            }
        }
    }

    /// SIGTERM, so the server can shut down cleanly. Only ever offered for this user's own processes.
    func stop(_ port: PortUsage) {
        kill(port.pid, SIGTERM)
        ports.ports.removeAll { $0.pid == port.pid }
    }

    private func apply(found: [Project]?, samples: [ProcessSample], listeners: [Listener]?, ticks: CPUTicks?, battery: BatteryReading?, memory: Result<SystemMemory, Error>) {
        let now = Date()
        if let found {
            projects = found
            projectsScannedAt = now
        }
        let rates = tracker.update(samples, at: now)
        attribution = ProjectAttribution.attribute(samples, cpu: rates, to: projects)
        if let listeners { ports = PortScanner.report(listeners, samples: samples, projects: projects) }

        if let ticks, let previousTicks { cpuLoad = ticks.load(since: previousTicks) }
        previousTicks = ticks

        self.battery = battery
        if let battery, !battery.onExternalPower, battery.dischargeWatts > 0 {
            power.add(battery.dischargeWatts, at: now)
            runway = power.runway(remainingWattHours: battery.remainingWattHours)
        } else {
            power.reset()
            runway = nil
        }

        let busy = policy.busyReason(samples: samples, rates: rates, projects: attribution.projects, cores: ProcessInfo.processInfo.activeProcessorCount)
        updateAssertion(busy: busy, now: now)

        switch memory {
        case .success(let value):
            self.memory = value
            lastError = nil
        case .failure(let error):
            lastError = "Could not read memory: \(error)"
        }
    }

    private func updateAssertion(busy: String?, now: Date) {
        let reason: String?
        switch keepAwake {
        case .off: reason = nil
        case .on: reason = "kept awake by you"
        case .automatic: reason = policy.evaluate(busy: busy, at: now)
        }
        if let reason { assertion.hold(reason) } else { assertion.release() }
        awakeReason = reason
    }
}
