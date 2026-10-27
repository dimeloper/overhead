import Darwin
import Foundation

/// A TCP port a process is listening on.
public struct Listener: Sendable, Hashable {
    public var port: UInt16
    public var pid: pid_t

    public init(port: UInt16, pid: pid_t) {
        self.port = port
        self.pid = pid
    }
}

/// A listener as the popover shows it: who owns it and which project it belongs to.
public struct PortUsage: Sendable, Hashable {
    public var port: UInt16
    public var pid: pid_t
    public var process: String
    /// Nil for a known dev server running outside any project (Homebrew postgres, Docker).
    public var project: String?

    public init(port: UInt16, pid: pid_t, process: String, project: String?) {
        self.port = port
        self.pid = pid
        self.process = process
        self.project = project
    }
}

public struct PortReport: Sendable, Equatable {
    public var ports: [PortUsage]
    /// Listeners that are neither in a project nor a known dev server: AirPlay, Spotify, browsers.
    public var otherCount: Int

    public init(ports: [PortUsage], otherCount: Int) {
        self.ports = ports
        self.otherCount = otherCount
    }
}

public enum PortScanner {
    /// TCP listeners owned by the given processes. Matches `lsof -a -iTCP -sTCP:LISTEN -u $(id -u)` without
    /// spawning it.
    public static func listeners(pids: [pid_t]) -> [Listener] {
        var found = Set<Listener>()
        for pid in pids {
            let size = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
            guard size > 0 else { continue }
            var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(size) / MemoryLayout<proc_fdinfo>.stride)
            let used = fds.withUnsafeMutableBytes { proc_pidinfo(pid, PROC_PIDLISTFDS, 0, $0.baseAddress, Int32($0.count)) }
            guard used > 0 else { continue }
            for fd in fds.prefix(Int(used) / MemoryLayout<proc_fdinfo>.stride) where fd.proc_fdtype == UInt32(PROX_FDTYPE_SOCKET) {
                var info = socket_fdinfo()
                let read = proc_pidfdinfo(pid, fd.proc_fd, PROC_PIDFDSOCKETINFO, &info, Int32(MemoryLayout<socket_fdinfo>.size))
                guard read == MemoryLayout<socket_fdinfo>.size, info.psi.soi_kind == Int32(SOCKINFO_TCP) else { continue }
                let tcp = info.psi.soi_proto.pri_tcp
                guard tcp.tcpsi_state == Int32(TSI_S_LISTEN) else { continue }
                // insi_lport holds the port in network byte order in its low 16 bits.
                found.insert(Listener(port: UInt16(bigEndian: UInt16(truncatingIfNeeded: tcp.tcpsi_ini.insi_lport)), pid: pid))
            }
        }
        return found.sorted { ($0.port, $0.pid) < ($1.port, $1.pid) }
    }

    /// Servers developers run outside a project folder, matched on the start of the process name.
    static let devServers = ["postgres", "redis-server", "mongod", "mysqld", "mariadbd", "com.docker.backend", "ollama", "nginx", "caddy", "adb", "memcached", "rabbitmq", "elasticsearch", "minio"]

    public static func report(_ listeners: [Listener], samples: [ProcessSample], projects: [Project]) -> PortReport {
        let byPid = Dictionary(samples.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        var ports: [PortUsage] = []
        var other = 0
        for listener in listeners {
            guard let sample = byPid[listener.pid] else { other += 1; continue }
            let project = sample.workingDirectory.flatMap { ProjectAttribution.project(containing: $0, in: projects) }
            if project != nil || devServers.contains(where: { sample.name.hasPrefix($0) }) {
                let name = sample.name.hasPrefix("com.docker.") ? "Docker" : sample.name
                ports.append(PortUsage(port: listener.port, pid: listener.pid, process: name, project: project?.name))
            } else {
                other += 1
            }
        }
        return PortReport(ports: ports, otherCount: other)
    }
}
