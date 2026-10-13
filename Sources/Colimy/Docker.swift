import Foundation

// MARK: - Models

/// A container as listed by `docker ps -a`, with the Compose labels we need.
struct Container: Identifiable, Hashable, Decodable {
    let id: String
    let name: String
    let image: String
    let command: String
    let state: String
    let status: String
    let ports: String
    let created: String
    let project: String
    let service: String
    let workingDir: String
    let configFiles: String

    var isRunning: Bool { state == "running" }
    var isPaused: Bool { state == "paused" }
    var stackName: String? { project.isEmpty ? nil : project }

    /// Service name inside a stack, otherwise the container name.
    var displayName: String { service.isEmpty ? name : service }

    enum Health { case healthy, unhealthy, starting }

    var health: Health? {
        if status.contains("(healthy)") { return .healthy }
        if status.contains("(unhealthy)") { return .unhealthy }
        if status.contains("(health: starting)") { return .starting }
        return nil
    }

    /// Published ports, one per host port ("0.0.0.0:8080->80/tcp" and "[::]:8080->80/tcp" count once).
    var publishedPorts: [PortMapping] {
        var seen = Set<String>()
        var result: [PortMapping] = []
        for part in ports.split(separator: ",") {
            let text = part.trimmingCharacters(in: .whitespaces)
            guard let arrow = text.range(of: "->") else { continue }
            let host = text[..<arrow.lowerBound]
            let target = text[arrow.upperBound...]
            guard let colon = host.lastIndex(of: ":") else { continue }
            let hostPort = String(host[host.index(after: colon)...])
            let (containerPort, proto) = Self.splitProto(String(target))
            let key = "\(hostPort)/\(proto)"
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(PortMapping(hostPort: hostPort, containerPort: containerPort, proto: proto))
        }
        return result
    }

    private static func splitProto(_ text: String) -> (String, String) {
        let parts = text.split(separator: "/", maxSplits: 1).map(String.init)
        return (parts.first ?? text, parts.count > 1 ? parts[1] : "tcp")
    }
}

struct PortMapping: Hashable {
    let hostPort: String
    let containerPort: String
    let proto: String

    var label: String { hostPort == containerPort ? hostPort : "\(hostPort)→\(containerPort)" }

    /// Single TCP ports can be opened in the browser.
    var url: URL? {
        guard proto == "tcp", Int(hostPort) != nil else { return nil }
        return URL(string: "http://localhost:\(hostPort)")
    }
}

/// A Compose project, rebuilt from its containers' labels.
struct Stack: Identifiable, Hashable {
    let name: String
    let containers: [Container]
    var id: String { name }

    var workingDir: String { containers.first { !$0.workingDir.isEmpty }?.workingDir ?? "" }

    var configFiles: [String] {
        let joined = containers.first { !$0.configFiles.isEmpty }?.configFiles ?? ""
        return joined.split(separator: ",").map(String.init)
    }

    /// Compose files still on disk; without them only start/stop/restart/down work.
    var hasFiles: Bool {
        let files = configFiles
        return !files.isEmpty && files.allSatisfy { FileManager.default.fileExists(atPath: $0) }
    }

    var runningCount: Int { containers.filter(\.isRunning).count }

    enum Status { case running, partial, stopped }

    var status: Status {
        let running = runningCount
        if running == 0 { return .stopped }
        return running == containers.count ? .running : .partial
    }

    var publishedPorts: [PortMapping] {
        var seen = Set<PortMapping>()
        return containers.flatMap(\.publishedPorts).filter { seen.insert($0).inserted }
    }
}

struct ContainerStats: Hashable {
    let cpu: String
    let memory: String
    let memoryPercent: String
}

/// The parts of `docker inspect` shown in the inspector.
struct ContainerDetail: Decodable {
    struct State: Decodable {
        let status: String
        let startedAt: String?
        let finishedAt: String?
        let exitCode: Int?

        enum CodingKeys: String, CodingKey {
            case status = "Status", startedAt = "StartedAt", finishedAt = "FinishedAt", exitCode = "ExitCode"
        }
    }

    struct Config: Decodable {
        let image: String?
        let env: [String]?
        let cmd: [String]?
        let entrypoint: [String]?
        let workingDir: String?
        let user: String?

        enum CodingKeys: String, CodingKey {
            case image = "Image", env = "Env", cmd = "Cmd", entrypoint = "Entrypoint"
            case workingDir = "WorkingDir", user = "User"
        }
    }

    struct Mount: Decodable, Hashable {
        let type: String?
        let source: String?
        let destination: String?
        let readWrite: Bool?

        enum CodingKeys: String, CodingKey {
            case type = "Type", source = "Source", destination = "Destination", readWrite = "RW"
        }
    }

    private struct HostConfig: Decodable {
        struct Restart: Decodable {
            let name: String?
            enum CodingKeys: String, CodingKey { case name = "Name" }
        }
        let restartPolicy: Restart?
        enum CodingKeys: String, CodingKey { case restartPolicy = "RestartPolicy" }
    }

    private struct NetworkSettings: Decodable {
        struct Network: Decodable {
            let ipAddress: String?
            enum CodingKeys: String, CodingKey { case ipAddress = "IPAddress" }
        }
        let networks: [String: Network]?
        enum CodingKeys: String, CodingKey { case networks = "Networks" }
    }

    let id: String
    let created: String
    let state: State
    let config: Config
    let mounts: [Mount]?
    private let hostConfig: HostConfig?
    private let networkSettings: NetworkSettings?

    enum CodingKeys: String, CodingKey {
        case id = "Id", created = "Created", state = "State", config = "Config", mounts = "Mounts"
        case hostConfig = "HostConfig", networkSettings = "NetworkSettings"
    }

    var restartPolicy: String? { hostConfig?.restartPolicy?.name }

    var commandLine: String {
        let parts: [String] = (config.entrypoint ?? []) + (config.cmd ?? [])
        return parts.joined(separator: " ")
    }

    var networks: [(name: String, ip: String)] {
        let all = networkSettings?.networks ?? [:]
        return all.map { (name: $0.key, ip: $0.value.ipAddress ?? "") }.sorted { $0.name < $1.name }
    }
}

// MARK: - CLI

/// Thin wrapper over the docker CLI, always pointed at the Colima socket.
enum Docker {
    private static let psFormat = """
    {"id":{{json .ID}},"name":{{json .Names}},"image":{{json .Image}},"command":{{json .Command}},\
    "state":{{json .State}},"status":{{json .Status}},"ports":{{json .Ports}},"created":{{json .CreatedAt}},\
    "project":{{json (.Label "com.docker.compose.project")}},\
    "service":{{json (.Label "com.docker.compose.service")}},\
    "workingDir":{{json (.Label "com.docker.compose.project.working_dir")}},\
    "configFiles":{{json (.Label "com.docker.compose.project.config_files")}}}
    """

    static func environment(host: String) -> [String: String] {
        ["DOCKER_HOST": host]
    }

    static func containers(host: String) async throws -> [Container] {
        let lines = try await ToolProcess.lines(.docker, ["ps", "-a", "--format", psFormat],
                                                environment: environment(host: host))
        let decoder = JSONDecoder()
        return lines.compactMap { line in
            guard let data = line.data(using: .utf8) else { return nil }
            guard let container = try? decoder.decode(Container.self, from: data) else { return nil }
            // `Names` can list links too; the first one is the container's own name.
            let name = container.name.split(separator: ",").first.map(String.init) ?? container.name
            return name == container.name ? container : Container(
                id: container.id, name: name, image: container.image, command: container.command,
                state: container.state, status: container.status, ports: container.ports,
                created: container.created, project: container.project, service: container.service,
                workingDir: container.workingDir, configFiles: container.configFiles)
        }
    }

    /// One sample of CPU and memory for running containers, keyed by short ID. Takes ~2 s.
    static func stats(host: String) async throws -> [String: ContainerStats] {
        struct Row: Decodable { let ID: String; let CPUPerc: String; let MemUsage: String; let MemPerc: String }
        let lines = try await ToolProcess.lines(.docker, ["stats", "--no-stream", "--format", "{{json .}}"],
                                                environment: environment(host: host))
        var result: [String: ContainerStats] = [:]
        for line in lines {
            guard let row = try? JSONDecoder().decode(Row.self, from: Data(line.utf8)) else { continue }
            let memory = row.MemUsage.split(separator: "/").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? row.MemUsage
            result[row.ID] = ContainerStats(cpu: row.CPUPerc, memory: memory, memoryPercent: row.MemPerc)
        }
        return result
    }

    static func inspect(_ id: String, host: String) async throws -> ContainerDetail {
        let lines = try await ToolProcess.lines(.docker, ["inspect", id], environment: environment(host: host))
        let details = try JSONDecoder().decode([ContainerDetail].self, from: Data(lines.joined(separator: "\n").utf8))
        guard let detail = details.first else { throw ToolError.failed(tr("No se encontró el contenedor.")) }
        return detail
    }

    /// `docker compose` arguments that target `stack`, with its files when they still exist.
    static func composeArguments(_ stack: Stack) -> [String] {
        var args = ["compose", "-p", stack.name]
        if stack.hasFiles {
            if !stack.workingDir.isEmpty { args += ["--project-directory", stack.workingDir] }
            for file in stack.configFiles { args += ["-f", file] }
        }
        return args
    }
}
