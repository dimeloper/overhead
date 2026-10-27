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
    /// What the last Park did, shown briefly so parking never looks like nothing happened.
    @Published private(set) var parkResult: String?
    @Published var devSweeperHintDismissed: Bool {
        didSet { UserDefaults.standard.set(devSweeperHintDismissed, forKey: Self.devSweeperHintKey) }
    }
    @Published var agentNodHintDismissed: Bool {
        didSet { UserDefaults.standard.set(agentNodHintDismissed, forKey: Self.agentNodHintKey) }
    }

    // MARK: Settings, each saved as it changes

    @Published var showCPU: Bool { didSet { defaults.set(showCPU, forKey: "showCPU") } }
    @Published var showMemory: Bool { didSet { defaults.set(showMemory, forKey: "showMemory") } }
    /// Battery time is only ever shown while unplugged; this turns even that off.
    @Published var showBattery: Bool { didSet { defaults.set(showBattery, forKey: "showBattery") } }
    @Published var showAwakeCup: Bool { didSet { defaults.set(showAwakeCup, forKey: "showAwakeCup") } }
    /// Percent of physical memory by default; gigabytes in use otherwise.
    @Published var memoryAsPercent: Bool { didSet { defaults.set(memoryAsPercent, forKey: "memoryAsPercent") } }
    /// Scanned in addition to the home folder, two levels deep.
    @Published var extraProjectFolders: [String] {
        didSet {
            defaults.set(extraProjectFolders, forKey: "extraProjectFolders")
            projectsScannedAt = .distantPast
            refresh()
        }
    }

    private let defaults = UserDefaults.standard
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
    private static let agentNodHintKey = "agentNodHintDismissed"
    private static let agentNodBundleID = "app.agentnod.mac"
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

    /// Made-up data for screenshots: no sampling, no timers, nothing read from or written to disk.
    let isDemo: Bool

    init(demo: Bool = false) {
        isDemo = demo
        // The demo never reads this Mac's settings, so its screenshots look the same everywhere.
        let stored = demo ? UserDefaults(suiteName: "overhead-demo")! : UserDefaults.standard
        if demo { stored.removePersistentDomain(forName: "overhead-demo") }
        keepAwake = stored.string(forKey: Self.keepAwakeKey).flatMap(KeepAwakeMode.init) ?? .automatic
        devSweeperHintDismissed = stored.bool(forKey: Self.devSweeperHintKey)
        agentNodHintDismissed = stored.bool(forKey: Self.agentNodHintKey)
        func flag(_ key: String, _ fallback: Bool) -> Bool { stored.object(forKey: key) as? Bool ?? fallback }
        showCPU = flag("showCPU", true)
        showMemory = flag("showMemory", true)
        showBattery = flag("showBattery", true)
        showAwakeCup = flag("showAwakeCup", true)
        memoryAsPercent = flag("memoryAsPercent", true)
        extraProjectFolders = stored.stringArray(forKey: "extraProjectFolders") ?? []
        if demo {
            loadDemo()
            return
        }
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
        var columns: [MenuBarReadout.Column] = []
        if showCPU { columns.append(.init(label: "CPU", value: cpuLoad.map(ByteFormat.percent) ?? "–", widest: "100%")) }
        if showMemory { columns.append(.init(label: "MEM", value: menuMemory, widest: memoryAsPercent ? "100%" : "63.9G")) }
        if showBattery, let battery = menuBattery { columns.append(.init(label: "BAT", value: battery, widest: "10:00")) }
        return MenuBarReadout(columns: columns, holdingAwake: showAwakeCup && isHoldingAwake)
    }

    private var menuMemory: String {
        guard let memory else { return "–" }
        guard memoryAsPercent, memory.total > 0 else { return ByteFormat.menu(memory.used) }
        return ByteFormat.percent(Double(memory.used) / Double(memory.total))
    }

    /// What VoiceOver reads for the menu bar image.
    var menuAccessibilityLabel: String {
        let readout = menuReadout
        var parts = ["Overhead"] + readout.columns.map { "\($0.label) \($0.value)" }
        if readout.holdingAwake { parts.append("keeping the Mac awake") }
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
        let extras = extraProjectFolders.map { URL(fileURLWithPath: $0) }
        Task.detached(priority: .utility) {
            let found = rescan ? ProjectDiscovery.discover(home: FileManager.default.homeDirectoryForCurrentUser, extraFolders: extras) : known
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
        if isDemo { planning = Demo.plan(for: project); return }
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
                self.showParkResult(for: plan)
                self.refresh()
            }
        }
    }

    func isParked(_ project: Project) -> Bool {
        parked.contains { $0.path == project.path }
    }

    private func showParkResult(for plan: ParkPlan) {
        var done: [String] = []
        if !plan.servers.isEmpty { done.append("stopped \(plan.servers.count) server\(plan.servers.count == 1 ? "" : "s")") }
        if !plan.simulators.isEmpty { done.append("shut down \(plan.simulators.map(\.name).joined(separator: ", "))") }
        let message = "Parked \(plan.project.name)" + (done.isEmpty ? ": setup sheet saved" : ": " + done.joined(separator: ", "))
        parkResult = message
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(8))
            if self.parkResult == message { self.parkResult = nil }
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

    // MARK: DevSweeper and AgentNod

    /// The demo pretends neither is installed, so its screenshots look the same on every Mac.
    var devSweeperInstalled: Bool { !isDemo && installedApp(Self.devSweeperBundleID) != nil }
    var agentNodInstalled: Bool { !isDemo && installedApp(Self.agentNodBundleID) != nil }

    /// Coding agent sessions running across all projects.
    var agentSessions: Int { attribution.projects.reduce(0) { $0 + $1.agentSessions } }

    /// Opens DevSweeper when it is installed, otherwise its website.
    func openDevSweeper() { open(Self.devSweeperBundleID, site: "https://devsweeper.com/?ref=overhead") }

    /// Opens AgentNod when it is installed, otherwise its website.
    func openAgentNod() { open(Self.agentNodBundleID, site: "https://agentnod.app/?ref=overhead") }

    private func installedApp(_ bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    private func open(_ bundleID: String, site: String) {
        if let app = installedApp(bundleID) {
            NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
        } else if let url = URL(string: site) {
            NSWorkspace.shared.open(url)
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

    private func loadDemo() {
        memory = Demo.memory
        cpuLoad = Demo.cpuLoad
        battery = Demo.battery
        runway = Demo.runway
        attribution = Demo.attribution
        ports = Demo.ports
        simulators = Demo.simulators
        parked = Demo.parked
        awakeReason = Demo.awakeReason
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
