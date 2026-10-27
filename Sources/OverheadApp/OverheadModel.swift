import Foundation
import OverheadCore

@MainActor
final class OverheadModel: ObservableObject {
    @Published private(set) var memory: SystemMemory?
    @Published private(set) var attribution = Attribution(projects: [], unattributed: 0)
    @Published private(set) var lastError: String?

    private var projects: [Project] = []
    private var projectsScannedAt = Date.distantPast
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
        return ByteFormat.short(memory.used)
    }

    func refresh() {
        let rescan = Date().timeIntervalSince(projectsScannedAt) > projectRescanInterval
        let known = projects
        Task.detached(priority: .utility) {
            let found = rescan ? ProjectDiscovery.discover(home: FileManager.default.homeDirectoryForCurrentUser) : known
            let samples = ProcessSampler.sampleAll()
            let attribution = ProjectAttribution.attribute(samples, to: found)
            let memory = Result { try SystemMemory.read() }
            await MainActor.run {
                if rescan {
                    self.projects = found
                    self.projectsScannedAt = Date()
                }
                self.attribution = attribution
                switch memory {
                case .success(let value):
                    self.memory = value
                    self.lastError = nil
                case .failure(let error):
                    self.lastError = "Could not read memory: \(error)"
                }
            }
        }
    }
}
