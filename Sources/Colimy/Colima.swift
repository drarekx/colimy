import Foundation
import SystemConfiguration

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
    /// Stop (if running) and start again with new network settings.
    case network

    var title: String {
        switch self {
        case .start: return tr("Arrancando Colima…")
        case .stop: return tr("Parando Colima…")
        case .restart: return tr("Reiniciando Colima…")
        case .network: return tr("Aplicando la configuración de red…")
        }
    }
}

/// Network settings of a profile (`network:` in `colima.yaml`).
struct ColimaNetwork: Equatable {
    enum Mode: String { case shared, bridged }

    /// The VM gets its own IP address (reachable from the Mac; from the LAN in bridged mode).
    var address = false
    var mode: Mode = .shared
    /// Host interface the VM is bridged to (bridged mode only).
    var interface = "en0"

    /// Bridged mode needs an address; normalise so comparisons and flags agree.
    var normalized: ColimaNetwork {
        var copy = self
        if copy.mode == .bridged { copy.address = true }
        return copy
    }

    /// `key: value` lines for the `network:` section of `colima.yaml`.
    var yamlValues: [(String, String)] {
        let net = normalized
        return [("address", net.address ? "true" : "false"), ("mode", net.mode.rawValue), ("interface", net.interface)]
    }
}

/// A host network interface that can be used for bridged mode.
struct HostInterface: Identifiable, Hashable {
    let name: String
    let displayName: String
    var id: String { name }

    /// Wi-Fi and Ethernet interfaces, e.g. `en0` "Wi-Fi".
    static func all() -> [HostInterface] {
        guard let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else { return [] }
        let types: Set<String> = [kSCNetworkInterfaceTypeEthernet as String, kSCNetworkInterfaceTypeIEEE80211 as String]
        return interfaces.compactMap { interface in
            guard let type = SCNetworkInterfaceGetInterfaceType(interface) as String?, types.contains(type),
                  let name = SCNetworkInterfaceGetBSDName(interface) as String? else { return nil }
            let display = SCNetworkInterfaceGetLocalizedDisplayName(interface) as String? ?? name
            return HostInterface(name: name, displayName: display)
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
        return "unix://\(home)/\(profile)/docker.sock"
    }

    static var home: String {
        ProcessInfo.processInfo.environment["COLIMA_HOME"] ?? NSHomeDirectory() + "/.colima"
    }

    /// Reads the `network:` section and `vmType` of `<home>/<profile>/colima.yaml`.
    /// Missing file or keys fall back to Colima's defaults.
    static func configuration(profile: String) -> (network: ColimaNetwork, vmType: String?) {
        var network = ColimaNetwork()
        var vmType: String?
        guard let text = try? String(contentsOfFile: "\(home)/\(profile)/colima.yaml", encoding: .utf8) else {
            return (network, vmType)
        }
        var inNetwork = false
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let topLevel = !line.hasPrefix(" ") && !line.hasPrefix("\t")
            guard let colon = trimmed.firstIndex(of: ":") else { continue }
            let key = String(trimmed[..<colon])
            var value = trimmed[trimmed.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if let comment = value.range(of: " #") { value = String(value[..<comment.lowerBound]) }
            value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
            if topLevel {
                inNetwork = key == "network"
                if key == "vmType", !value.isEmpty { vmType = value }
                continue
            }
            // Only direct children of `network:` (two-space indent).
            guard inNetwork, line.hasPrefix("  "), !line.hasPrefix("   ") else { continue }
            switch key {
            case "address": network.address = value == "true"
            case "mode": network.mode = ColimaNetwork.Mode(rawValue: value) ?? .shared
            case "interface": if !value.isEmpty { network.interface = value }
            default: break
            }
        }
        return (network, vmType)
    }

    /// Bridged networking (and a reachable address on QEMU) runs `socket_vmnet` as root.
    /// The first time, `colima` installs it and a sudoers rule, which asks for the
    /// admin password: that only works from a terminal.
    static func needsSudoSetup(for network: ColimaNetwork, vmType: String?) -> Bool {
        let net = network.normalized
        let usesVmnet = net.mode == .bridged || (net.address && vmType != "vz")
        guard usesVmnet else { return false }
        let files = ["/etc/sudoers.d/colima", "/opt/colima/bin/socket_vmnet"]
        return !files.allSatisfy { FileManager.default.fileExists(atPath: $0) }
    }

    /// Writes `network` into the profile's `colima.yaml`, keeping everything else
    /// (comments included). `colima start` ignores network flags on an existing
    /// profile, so the file is the only way to change them.
    static func saveNetwork(_ network: ColimaNetwork, profile: String) throws {
        let path = "\(home)/\(profile)/colima.yaml"
        let text = try String(contentsOfFile: path, encoding: .utf8)
        var lines = text.components(separatedBy: "\n")
        let isTopLevel = { (line: String) -> Bool in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return !trimmed.isEmpty && !trimmed.hasPrefix("#") && !line.hasPrefix(" ") && !line.hasPrefix("\t")
        }
        guard let start = lines.firstIndex(where: { isTopLevel($0) && $0.hasPrefix("network:") }) else {
            if lines.last == "" { lines.removeLast() }
            lines.append("network:")
            lines += network.yamlValues.map { "  \($0.0): \($0.1)" }
            lines.append("")
            try lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
            return
        }
        lines[start] = "network:"
        var end = lines[(start + 1)...].firstIndex(where: isTopLevel) ?? lines.count
        for (key, value) in network.yamlValues {
            let entry = "  \(key): \(value)"
            if let index = lines[(start + 1)..<end].firstIndex(where: {
                $0.hasPrefix("  \(key):") && !$0.hasPrefix("   ")
            }) {
                lines[index] = entry
            } else {
                lines.insert(entry, at: start + 1)
                end += 1
            }
        }
        try lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
    }

    /// Runs `colima <action> -p <profile>`, streaming its output.
    static func run(_ action: ColimaAction, profile: String,
                    onLine: @escaping @Sendable (String) -> Void) async throws {
        try await ToolProcess.run(.colima, [action.rawValue, "-p", profile], includeErrors: true, onLine: onLine)
    }

    /// Saves `network` and restarts `profile` (or starts it, if stopped) so it takes effect.
    static func applyNetwork(_ network: ColimaNetwork, profile: String, running: Bool,
                             onLine: @escaping @Sendable (String) -> Void) async throws {
        try saveNetwork(network, profile: profile)
        try await ToolProcess.run(.colima, [running ? "restart" : "start", "-p", profile],
                                  includeErrors: true, onLine: onLine)
    }
}
