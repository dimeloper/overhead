import Foundation
import OverheadCore

@MainActor
final class OverheadModel: ObservableObject {
    @Published private(set) var memory: SystemMemory?
    @Published private(set) var attribution = Attribution(projects: [], unattributed: 0)
    @Published private(set) var cpuLoad: Double?
    @Published private(set) var battery: BatteryReading?
    @Published private(set) var runway: TimeInterval?
    @Published private(set) var lastError: String?

    private var projects: [Project] = []
    private var projectsScannedAt = Date.distantPast
    private var tracker = ActivityTracker()
    private var previousTicks: CPUTicks?
    private var power = PowerHistory()
    private var timer: Timer?

    /// Sampling is cheap (a few ms for ~1,000 processes); finding checkouts walks the disk, so it runs once a minute.
    private let sampleInterval: TimeInterval = 3
    private let projectRescanInterval: TimeInterval = 60

    init() {
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

    func refresh() {
        let rescan = Date().timeIntervalSince(projectsScannedAt) > projectRescanInterval
        let known = projects
        Task.detached(priority: .utility) {
            let found = rescan ? ProjectDiscovery.discover(home: FileManager.default.homeDirectoryForCurrentUser) : known
            let samples = ProcessSampler.sampleAll()
            let ticks = CPUTicks.read()
            let battery = BatteryReading.read()
            let memory = Result { try SystemMemory.read() }
            await MainActor.run {
                self.apply(found: rescan ? found : nil, samples: samples, ticks: ticks, battery: battery, memory: memory)
            }
        }
    }

    private func apply(found: [Project]?, samples: [ProcessSample], ticks: CPUTicks?, battery: BatteryReading?, memory: Result<SystemMemory, Error>) {
        let now = Date()
        if let found {
            projects = found
            projectsScannedAt = now
        }
        let rates = tracker.update(samples, at: now)
        attribution = ProjectAttribution.attribute(samples, cpu: rates, to: projects)

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

        switch memory {
        case .success(let value):
            self.memory = value
            lastError = nil
        case .failure(let error):
            lastError = "Could not read memory: \(error)"
        }
    }
}
