import AppKit
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
    @Published private(set) var simulators: [SimulatorUsage] = []
    /// UDIDs being shut down, so the row can show it until the simulator is gone.
    @Published private(set) var shuttingDown: Set<String> = []
    @Published private(set) var awakeReason: String?
    @Published private(set) var parked: [ParkedProject] = []
    /// The plan shown for confirmation after Park is clicked, before anything stops.
    @Published private(set) var planning: ParkPlan?
    @Published private(set) var isPreparingPark = false
    @Published var devSweeperHintDismissed: Bool {
        didSet { UserDefaults.standard.set(devSweeperHintDismissed, forKey: Self.devSweeperHintKey) }
    }
    @Published private(set) var lastError: String?
    @Published var keepAwake: KeepAwakeMode {
        didSet {
            UserDefaults.standard.set(keepAwake.rawValue, forKey: Self.keepAwakeKey)
            updateAssertion(busy: nil, now: Date())
        }
    }

    private static let keepAwakeKey = "keepAwakeMode"
    private static let devSweeperHintKey = "devSweeperHintDismissed"
    private static let devSweeperBundleID = "com.devsweeper.DevSweeper"
    private let store = ParkedStore()

    private var projects: [Project] = []
    private var projectsScannedAt = Date.distantPast
    private var tracker = ActivityTracker()
    private var previousTicks: CPUTicks?
    private var power = PowerHistory()
    private var policy = KeepAwakePolicy()
    private let assertion = SleepAssertion()
    private var refreshCount = 0
    private var timer: Timer?
    private var fastTimer: Timer?

    /// Machine CPU and memory are two kernel calls, cheap enough for the menu bar to move every second.
    private let fastInterval: TimeInterval = 1
    /// Sampling is cheap (a few ms for ~1,000 processes); finding checkouts walks the disk, so it runs once a minute.
    private let sampleInterval: TimeInterval = 3
    private let projectRescanInterval: TimeInterval = 60
    /// Reading every socket of every process costs more than sampling, and ports change rarely.
    private let portScanEvery = 3

    init() {
        keepAwake = UserDefaults.standard.string(forKey: Self.keepAwakeKey).flatMap(KeepAwakeMode.init) ?? .automatic
        devSweeperHintDismissed = UserDefaults.standard.bool(forKey: Self.devSweeperHintKey)
        parked = store.load()
        tick()
        refresh()
        fastTimer = Timer.scheduledTimer(withTimeInterval: fastInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: sampleInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    var menuReadout: MenuBarReadout {
        MenuBarReadout(
            cpu: cpuLoad.map(ByteFormat.percent) ?? "–",
            memory: memory.map { ByteFormat.menu($0.used) } ?? "–",
            battery: menuBattery,
            holdingAwake: isHoldingAwake
        )
    }

    /// What VoiceOver reads for the menu bar image.
    var menuAccessibilityLabel: String {
        var parts = ["Overhead", "CPU \(menuReadout.cpu)", "memory \(memory.map { ByteFormat.short($0.used) } ?? "unknown")"]
        if let battery = menuBattery { parts.append("battery \(battery)") }
        if isHoldingAwake { parts.append("keeping the Mac awake") }
        return parts.joined(separator: ", ")
    }

    /// Only unplugged: time left at this pace once there is draw to measure, the charge level until then.
    private var menuBattery: String? {
        guard let battery, !battery.onExternalPower else { return nil }
        return runway.map(ByteFormat.clock) ?? "\(battery.percent)%"
    }

    /// The fast path: machine-wide CPU and memory only.
    func tick() {
        if let ticks = CPUTicks.read() {
            if let previousTicks { cpuLoad = ticks.load(since: previousTicks) }
            previousTicks = ticks
        }
        do {
            memory = try SystemMemory.read()
            if lastError?.hasPrefix("Could not read memory") == true { lastError = nil }
        } catch {
            lastError = "Could not read memory: \(error)"
        }
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
            let battery = BatteryReading.read()
            await MainActor.run {
                self.apply(found: rescan ? found : nil, samples: samples, listeners: listeners, battery: battery)
            }
        }
    }

    func shutDown(_ simulator: BootedSimulator) {
        shuttingDown.insert(simulator.udid)
        Task.detached(priority: .userInitiated) {
            let result = Result { try SimulatorScanner.shutDown(simulator.udid) }
            await MainActor.run {
                self.shuttingDown.remove(simulator.udid)
                if case .failure(let error) = result { self.lastError = "Could not shut down \(simulator.name): \(error)" }
                self.refresh()
            }
        }
    }

    // MARK: Park

    /// Gathers a fresh plan for `project` without stopping anything; `confirmPark` acts on it.
    func preparePark(_ project: Project) {
        isPreparingPark = true
        let projects = self.projects
        Task.detached(priority: .userInitiated) {
            let samples = ProcessSampler.sampleAll()
            let ports = PortScanner.report(PortScanner.listeners(pids: samples.map(\.pid)), samples: samples, projects: projects)
            let simulators = SimulatorScanner.booted(in: samples)
            var apps: [String: Set<String>] = [:]
            for simulator in simulators { apps[simulator.udid] = BundleIdentifiers.runningApps(in: simulator, samples: samples) }
            var plan = Parker.plan(
                for: project, projects: projects, samples: samples, ports: ports, simulators: simulators,
                appsBySimulator: apps, bundleIDs: BundleIdentifiers.declared(in: project.path)
            )
            plan.uncommittedChanges = Parker.uncommittedChanges(at: project.path)
            let ready = plan
            await MainActor.run {
                self.planning = ready
                self.isPreparingPark = false
            }
        }
    }

    func cancelPark() {
        planning = nil
    }

    func confirmPark() {
        guard let plan = planning else { return }
        planning = nil
        Task.detached(priority: .userInitiated) {
            let sheet = Parker.park(plan)
            await MainActor.run {
                self.parked.removeAll { $0.path == sheet.path }
                self.parked.insert(sheet, at: 0)
                self.saveParked()
                self.refresh()
            }
        }
    }

    func resume(_ project: ParkedProject) {
        Task.detached(priority: .userInitiated) { Parker.resume(project) }
        NSWorkspace.shared.open([URL(fileURLWithPath: project.path)], withApplicationAt: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"), configuration: NSWorkspace.OpenConfiguration())
        forget(project)
    }

    func forget(_ project: ParkedProject) {
        parked.removeAll { $0.path == project.path }
        saveParked()
    }

    func copy(_ command: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
    }

    private func saveParked() {
        do { try store.save(parked) } catch { lastError = "Could not save parked projects: \(error)" }
    }

    // MARK: DevSweeper

    var devSweeperInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.devSweeperBundleID) != nil
    }

    /// Opens DevSweeper when it is installed, otherwise its website.
    func openDevSweeper() {
        if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.devSweeperBundleID) {
            NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
        } else if let site = URL(string: "https://devsweeper.com/?ref=overhead") {
            NSWorkspace.shared.open(site)
        }
    }

    /// SIGTERM, so the server can shut down cleanly. Only ever offered for this user's own processes.
    func stop(_ port: PortUsage) {
        kill(port.pid, SIGTERM)
        ports.ports.removeAll { $0.pid == port.pid }
    }

    private func apply(found: [Project]?, samples: [ProcessSample], listeners: [Listener]?, battery: BatteryReading?) {
        let now = Date()
        if let found {
            projects = found
            projectsScannedAt = now
        }
        let rates = tracker.update(samples, at: now)
        attribution = ProjectAttribution.attribute(samples, cpu: rates, to: projects)
        if let listeners { ports = PortScanner.report(listeners, samples: samples, projects: projects) }
        simulators = SimulatorScanner.usage(of: SimulatorScanner.booted(in: samples), samples: samples, cpu: rates)

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
