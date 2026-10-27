import OverheadCore
import SwiftUI

enum Brand {
    static let orange = Color(red: 0.984, green: 0.573, blue: 0.235)
    static let pink = Color(red: 0.925, green: 0.282, blue: 0.600)
    static let gradient = LinearGradient(colors: [orange, pink], startPoint: .leading, endPoint: .trailing)
    /// Segment colours for the projects after the first, which takes the brand gradient.
    static let segments: [Color] = [Color(red: 0.655, green: 0.545, blue: 0.980), Color(red: 0.369, green: 0.918, blue: 0.831)]
}

struct PopoverView: View {
    @ObservedObject var model: OverheadModel

    /// Rows shown; the rest are summed into "Other".
    private let visibleProjects = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(16)
                .background(.white.opacity(0.025))
            Divider()
            projectList
            Divider()
            footer
        }
        .frame(width: 420)
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
                MemoryBar(memory: memory, projects: Array(model.attribution.projects.prefix(3)))
                    .padding(.top, 6)
            } else if let error = model.lastError {
                Text(error).foregroundStyle(.red)
            } else {
                ProgressView().controlSize(.small)
            }
        }
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
                    ProjectRow(usage: usage)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                HStack(spacing: 0) {
                    ForEach(Array(projects.enumerated()), id: \.offset) { index, usage in
                        segment(index).frame(width: width(usage.footprint, proxy.size.width))
                    }
                    Color.gray.opacity(0.55).frame(width: width(otherUsed, proxy.size.width))
                    Spacer(minLength: 0)
                }
            }
            .frame(height: 8)
            .background(Color.white.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 4))

            HStack(spacing: 12) {
                ForEach(Array(projects.enumerated()), id: \.offset) { index, usage in
                    HStack(spacing: 4) {
                        segment(index).frame(width: 7, height: 7).clipShape(Circle())
                        Text("\(usage.project.name) \(ByteFormat.short(usage.footprint))").lineLimit(1)
                    }
                }
                Text("Other \(ByteFormat.short(otherUsed))").foregroundStyle(.secondary)
            }
            .font(.caption)
        }
    }

    private var otherUsed: UInt64 {
        let projectTotal = projects.reduce(UInt64(0)) { $0 + $1.footprint }
        return memory.used > projectTotal ? memory.used - projectTotal : 0
    }

    private func width(_ bytes: UInt64, _ total: CGFloat) -> CGFloat {
        guard memory.total > 0 else { return 0 }
        return total * CGFloat(Double(bytes) / Double(memory.total))
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
    let usage: ProjectUsage

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(usage.project.name).font(.body.weight(.semibold)).lineLimit(1)
                Text(usage.processes.prefix(4).joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(ByteFormat.short(usage.footprint))
                .font(.body.weight(.semibold))
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .help(usage.project.path)
    }
}
