import OverheadCore
import SwiftUI

enum Brand {
    static let orange = Color(red: 0.984, green: 0.573, blue: 0.235)
    static let pink = Color(red: 0.925, green: 0.282, blue: 0.600)
    static let gradient = LinearGradient(colors: [orange, pink], startPoint: .leading, endPoint: .trailing)
    static let simulator = Color(red: 0.851, green: 0.275, blue: 0.937)
    /// Segment colours for the projects after the first, which takes the brand gradient.
    static let segments: [Color] = [Color(red: 0.655, green: 0.545, blue: 0.980), Color(red: 0.369, green: 0.918, blue: 0.831)]
}

struct PopoverView: View {
    @ObservedObject var model: OverheadModel
    /// Tallest the lists get before they scroll. Snapshots lift it to show everything.
    var listCap: CGFloat = 520
    @State private var listHeight: CGFloat = 300

    /// Rows shown; the rest are summed into "Other".
    private let visibleProjects = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(16)
                .background(.white.opacity(0.025))
            Divider()
            KeepAwakeRow(model: model)
            Divider()
            // The lists can outgrow the screen on a busy Mac; the header and footer stay put.
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    projectList
                    if !model.simulators.isEmpty {
                        Divider()
                        SimulatorList(model: model)
                    }
                    if !model.ports.ports.isEmpty {
                        Divider()
                        PortList(model: model)
                    }
                    if !model.parked.isEmpty {
                        Divider()
                        ParkedList(model: model)
                    }
                }
                // Preferences do not cross out of a ScrollView on macOS (it is an NSScrollView underneath), so the
                // content reports its height through state instead.
                .background(GeometryReader { proxy in
                    Color.clear
                        .onAppear { listHeight = proxy.size.height }
                        .onChange(of: proxy.size.height) { _, height in listHeight = height }
                })
            }
            .frame(height: min(listHeight, listCap))
            Divider()
            footer
        }
        .frame(width: 440)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                Text("Over").font(.headline)
                Text("head").font(.headline).foregroundStyle(Brand.gradient)
                Spacer()
            }
            if let memory = model.memory {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(ByteFormat.short(memory.used)) in use")
                        .font(.system(size: 26, weight: .bold))
                        .monospacedDigit()
                    PressurePill(pressure: memory.pressure)
                }
                Text("of \(ByteFormat.short(memory.total)) · swap \(ByteFormat.short(memory.swapUsed))")
                    .foregroundStyle(.secondary)
                MemoryBar(memory: memory, projects: Array(model.attribution.projects.prefix(3)), simulators: model.simulators.reduce(UInt64(0)) { $0 + $1.footprint })
                    .padding(.top, 6)
                HStack(alignment: .top, spacing: 8) {
                    Stat(title: "CPU", value: model.cpuLoad.map(ByteFormat.percent) ?? "—")
                    Stat(title: batteryTitle, value: batteryValue)
                    Stat(title: "Swap", value: ByteFormat.short(memory.swapUsed))
                }
                .padding(.top, 8)
            } else if let error = model.lastError {
                Text(error).foregroundStyle(.red)
            } else {
                ProgressView().controlSize(.small)
            }
        }
    }

    private var batteryTitle: String {
        guard let battery = model.battery else { return "Battery" }
        return battery.onExternalPower ? "Battery \(battery.percent)%" : "Battery at this pace"
    }

    private var batteryValue: String {
        guard let battery = model.battery else { return "No battery" }
        if battery.onExternalPower { return battery.isCharging ? "Charging" : "On power" }
        return model.runway.map(ByteFormat.duration) ?? "Measuring…"
    }

    private var projectList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("PROJECTS")
                Spacer()
                Text("MEMORY")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 4)

            if model.attribution.projects.isEmpty {
                Text("No processes are running from a git checkout in your home folder.")
                    .foregroundStyle(.secondary)
                    .padding(16)
            } else {
                ForEach(model.attribution.projects.prefix(visibleProjects), id: \.project.path) { usage in
                    ProjectRow(model: model, usage: usage)
                    if let plan = model.planning, plan.project == usage.project {
                        ParkPlanPanel(model: model, plan: plan)
                    }
                }
                let rest = model.attribution.projects.dropFirst(visibleProjects).reduce(UInt64(0)) { $0 + $1.footprint }
                if rest > 0 {
                    Text("\(model.attribution.projects.count - visibleProjects) more projects · \(ByteFormat.short(rest))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
            }
        }
        .padding(.bottom, 6)
    }

    private var footer: some View {
        HStack {
            Text("Updates every 3 s").font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Quit Overhead") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
                .keyboardShortcut("q")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

struct KeepAwakeRow: View {
    @ObservedObject var model: OverheadModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: model.isHoldingAwake ? "cup.and.saucer.fill" : "moon.zzz")
                .foregroundStyle(model.isHoldingAwake ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(.secondary))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.isHoldingAwake ? "Keeping your Mac awake" : "Your Mac can sleep").font(.body.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Picker("Keep awake", selection: $model.keepAwake) {
                Text("Off").tag(KeepAwakeMode.off)
                Text("Auto").tag(KeepAwakeMode.automatic)
                Text("On").tag(KeepAwakeMode.on)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 130)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var detail: String {
        switch model.keepAwake {
        case .off: "Keep awake is off"
        case .on: "Until you turn it off · the display can still sleep"
        case .automatic: model.awakeReason.map { "\($0) · lets go 2 min after it stops" } ?? "Holds while a build or agent is working"
        }
    }
}

struct SimulatorList: View {
    @ObservedObject var model: OverheadModel
    @State private var armed: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("SIMULATORS")
                Spacer()
                Text("MEMORY")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 4)

            ForEach(model.simulators, id: \.simulator.udid) { usage in
                let simulator = usage.simulator
                HStack(spacing: 10) {
                    Image(systemName: simulator.name.localizedCaseInsensitiveContains("ipad") ? "ipad" : "iphone")
                        .foregroundStyle(.secondary)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(simulator.name).font(.body.weight(.semibold)).lineLimit(1)
                        Text(detail(usage)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Text(ByteFormat.short(usage.footprint)).font(.body.weight(.semibold)).monospacedDigit()
                        .help("Every process this simulator runs, added up as Activity Monitor would. Much of it may be compressed or in swap rather than in RAM.")
                    if model.shuttingDown.contains(simulator.udid) {
                        ProgressView().controlSize(.small).frame(width: 70)
                    } else {
                        Button(armed == simulator.udid ? "Confirm" : "Shut Down") {
                            if armed == simulator.udid {
                                model.shutDown(simulator)
                                armed = nil
                            } else {
                                armed = simulator.udid
                            }
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(armed == simulator.udid ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                        .frame(width: 70, alignment: .trailing)
                        .help("Quits the apps in \(simulator.name) and frees its memory. The simulator and its data stay.")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
        }
        .padding(.bottom, 6)
    }

    private func detail(_ usage: SimulatorUsage) -> String {
        var parts = [usage.simulator.runtime]
        if let booted = usage.simulator.bootedAt { parts.append("up \(ByteFormat.uptime(Date().timeIntervalSince(booted)))") }
        parts.append("\(usage.processCount) processes")
        return parts.joined(separator: " · ")
    }
}

struct PortList: View {
    @ObservedObject var model: OverheadModel
    /// Stop asks twice: the first click arms the button, the second sends SIGTERM.
    @State private var armed: pid_t?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("PORTS")
                Spacer()
                if model.ports.otherCount > 0 { Text("\(model.ports.otherCount) more from other apps") }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 4)

            ForEach(model.ports.ports, id: \.self) { port in
                HStack(spacing: 10) {
                    // Verbatim: Text("…") would format 8081 for the locale, as "8.081" in Greek or German.
                    Text(verbatim: ":\(port.port)").font(.system(.body, design: .monospaced)).frame(width: 64, alignment: .leading)
                    Text(port.process).lineLimit(1)
                    Text(port.project ?? "outside projects").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Button(armed == port.pid ? "Confirm" : "Stop") {
                        if armed == port.pid {
                            model.stop(port)
                            armed = nil
                        } else {
                            armed = port.pid
                        }
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(armed == port.pid ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    .help("Sends \(port.process) (pid \(port.pid)) a polite quit signal (SIGTERM).")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
        }
        .padding(.bottom, 6)
    }
}

struct Stat: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Text(value).font(.system(size: 15, weight: .semibold)).monospacedDigit().lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PressurePill: View {
    let pressure: MemoryPressure

    var body: some View {
        Text(pressure == .normal ? "Pressure normal" : "Pressure \(pressure.label.lowercased())")
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
    }

    private var color: Color {
        switch pressure {
        case .normal: .green
        case .warning: .orange
        case .critical: .red
        }
    }
}

/// Used memory split into the top projects and everything else, against the machine's total.
struct MemoryBar: View {
    let memory: SystemMemory
    let projects: [ProjectUsage]
    let simulators: UInt64

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                HStack(spacing: 0) {
                    ForEach(Array(projects.enumerated()), id: \.offset) { index, usage in
                        segment(index).frame(width: width(usage.footprint, proxy.size.width))
                    }
                    Brand.simulator.frame(width: width(simulators, proxy.size.width))
                    Color.gray.opacity(0.55).frame(width: width(otherUsed, proxy.size.width))
                    Spacer(minLength: 0)
                }
            }
            .frame(height: 8)
            .background(Color.white.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 4))

            // Two columns: five names never fit on one line of a 440 pt popover.
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 4) {
                ForEach(Array(projects.enumerated()), id: \.offset) { index, usage in
                    legend(AnyView(segment(index)), usage.project.name, usage.footprint)
                }
                if simulators > 0 {
                    legend(AnyView(Brand.simulator), "Simulators", simulators)
                }
                legend(AnyView(Color.gray.opacity(0.55)), "Other", otherUsed)
            }
            .font(.caption)
        }
    }

    private func legend(_ swatch: AnyView, _ name: String, _ bytes: UInt64) -> some View {
        HStack(spacing: 5) {
            swatch.frame(width: 7, height: 7).clipShape(Circle())
            Text(name).lineLimit(1).truncationMode(.middle)
            Text(ByteFormat.short(bytes)).foregroundStyle(.secondary).monospacedDigit().fixedSize()
        }
    }

    private var otherUsed: UInt64 {
        let projectTotal = projects.reduce(simulators) { $0 + $1.footprint }
        return memory.used > projectTotal ? memory.used - projectTotal : 0
    }

    /// Per-process figures count compressed memory at its full size, so projects and simulators can add up to more
    /// than "in use". Their segments then share the used part of the bar in proportion instead of overflowing it.
    private var scale: Double {
        let parts = projects.reduce(simulators) { $0 + $1.footprint }
        return parts > memory.used && parts > 0 ? Double(memory.used) / Double(parts) : 1
    }

    private func width(_ bytes: UInt64, _ total: CGFloat) -> CGFloat {
        guard memory.total > 0 else { return 0 }
        return total * CGFloat(Double(bytes) * scale / Double(memory.total))
    }

    @ViewBuilder private func segment(_ index: Int) -> some View {
        if index == 0 {
            Rectangle().fill(Brand.gradient)
        } else {
            Rectangle().fill(Brand.segments[(index - 1) % Brand.segments.count])
        }
    }
}

struct ProjectRow: View {
    @ObservedObject var model: OverheadModel
    let usage: ProjectUsage

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(usage.project.name).font(.body.weight(.semibold)).lineLimit(1)
                Text(([ByteFormat.percent(usage.cpu) + " CPU"] + usage.processes.prefix(4)).joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(ByteFormat.short(usage.footprint))
                .font(.body.weight(.semibold))
                .monospacedDigit()
            Button("Park") { model.preparePark(usage.project) }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .disabled(model.isPreparingPark || model.planning != nil)
                .help("Shows what parking stops before anything happens.")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .help("\(usage.project.path)\nCPU is this project's share of the whole Mac, and the best guide to its battery use: macOS does not report power per process.")
    }
}

/// What Park will do for one project, with the only button that acts on it.
struct ParkPlanPanel: View {
    @ObservedObject var model: OverheadModel
    let plan: ParkPlan

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Park \(plan.project.name)?").font(.body.weight(.semibold))
            if plan.isEmpty {
                Text("Nothing to stop: no dev servers listening and no simulator running this app. Parking keeps the setup sheet.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(plan.servers, id: \.pid) { server in
                line("stop.circle", "Stop \(server.ports.map { ":\($0)" }.joined(separator: " ")) \(server.process)", server.command)
            }
            ForEach(plan.simulators, id: \.udid) { simulator in
                line("iphone", "Shut down \(simulator.name)", simulator.runtime)
            }
            if !plan.agents.isEmpty {
                line("person.wave.2", "Leaves running: \(plan.agents.count) agent session\(plan.agents.count == 1 ? "" : "s")", "Park never stops coding agents")
            }
            if let changes = plan.uncommittedChanges, changes > 0 {
                line("exclamationmark.triangle", "\(changes) uncommitted change\(changes == 1 ? "" : "s")", "They stay exactly as they are; parking never touches files")
            }
            HStack {
                Spacer()
                Button("Cancel") { model.cancelPark() }
                Button("Park Project") { model.confirmPark() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .padding(12)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    private func line(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon).foregroundStyle(.secondary).frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).lineLimit(1)
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
        }
    }
}

struct ParkedList: View {
    @ObservedObject var model: OverheadModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("PARKED")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 4)

            ForEach(model.parked, id: \.path) { project in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(project.name).font(.body.weight(.semibold)).lineLimit(1)
                            Text(summary(project)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Button("Resume") { model.resume(project) }
                            .buttonStyle(.borderless)
                            .help("Boots its simulators and opens the folder in Terminal. Paste the commands below to start the servers.")
                        Button("Forget") { model.forget(project) }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(project.commands, id: \.command) { command in
                        HStack(spacing: 6) {
                            Text(command.command)
                                .font(.system(.caption, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button {
                                model.copy("cd \(Parker.quoted(command.workingDirectory)) && \(command.command)")
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            .buttonStyle(.borderless)
                            .help("Copy, including the cd into its folder")
                            .accessibilityLabel("Copy command")
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }

            if !model.devSweeperHintDismissed {
                HStack(spacing: 8) {
                    Text("Parked projects still keep their node_modules, Pods and build output on disk.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(model.devSweeperInstalled ? "Open DevSweeper" : "Get DevSweeper") { model.openDevSweeper() }
                        .buttonStyle(.borderless)
                    Button {
                        model.devSweeperHintDismissed = true
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Don't show again")
                    .help("Don't show again")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
        .padding(.bottom, 6)
    }

    private func summary(_ project: ParkedProject) -> String {
        var parts = ["parked \(project.parkedAt.formatted(.relative(presentation: .named)))"]
        if let branch = project.branch { parts.append(branch) }
        if !project.simulators.isEmpty { parts.append(project.simulators.map(\.name).joined(separator: ", ")) }
        if !project.envFiles.isEmpty { parts.append(project.envFiles.joined(separator: " ")) }
        return parts.joined(separator: " · ")
    }
}
