import Foundation

/// A Colima profile (VM) as listed by `colima list --json`.
struct ColimaProfile: Identifiable, Hashable, Decodable {
    let name: String
    let status: String
    let arch: String?
    let cpus: Int?
    let memory: Int64?
    let disk: Int64?
    let runtime: String?
    let address: String?

    var id: String { name }
    var isRunning: Bool { status.lowercased() == "running" }

    var memoryLabel: String { memory.map(Self.bytes) ?? "–" }
    var diskLabel: String { disk.map(Self.bytes) ?? "–" }

    private static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .binary)
    }
}

enum ColimaAction: String {
    case start, stop, restart

    var title: String {
        switch self {
        case .start: return tr("Arrancando Colima…")
        case .stop: return tr("Parando Colima…")
        case .restart: return tr("Reiniciando Colima…")
        }
    }
}

enum Colima {
    static func profiles() async throws -> [ColimaProfile] {
        let lines = try await ToolProcess.lines(.colima, ["list", "--json"])
        let decoder = JSONDecoder()
        return lines.compactMap { try? decoder.decode(ColimaProfile.self, from: Data($0.utf8)) }
    }

    /// Docker socket of a running profile, e.g. `unix:///Users/me/.colima/default/docker.sock`.
    static func dockerSocket(profile: String) async -> String {
        struct Status: Decodable { let docker_socket: String? }
        if let lines = try? await ToolProcess.lines(.colima, ["status", "-p", profile, "--json"]),
           let status = try? JSONDecoder().decode(Status.self, from: Data(lines.joined().utf8)),
           let socket = status.docker_socket, !socket.isEmpty {
            return socket
        }
        let home = ProcessInfo.processInfo.environment["COLIMA_HOME"] ?? NSHomeDirectory() + "/.colima"
        return "unix://\(home)/\(profile)/docker.sock"
    }

    /// Runs `colima <action> -p <profile>`, streaming its output.
    static func run(_ action: ColimaAction, profile: String,
                    onLine: @escaping @Sendable (String) -> Void) async throws {
        try await ToolProcess.run(.colima, [action.rawValue, "-p", profile], includeErrors: true, onLine: onLine)
    }
}
