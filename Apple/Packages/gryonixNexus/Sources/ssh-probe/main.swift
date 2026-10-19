import Foundation
import Crypto
import ServerControl
import ServerControlSSH

let env = ProcessInfo.processInfo.environment
if let key = env["PROBE_PRINT_GRANT"] {
    print(AccessGrantCommand.command(publicKey: key))
    exit(0)
}
guard let host = env["PROBE_HOST"], let user = env["PROBE_USER"] else {
    FileHandle.standardError.write(Data("set PROBE_HOST, PROBE_USER and PROBE_KEY or PROBE_PASSWORD (or PROBE_PRINT_GRANT)\n".utf8))
    exit(2)
}
let keyPath = env["PROBE_KEY"]
let password: String? = {
    if let path = env["PROBE_PASSWORD_FILE"] {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            FileHandle.standardError.write(Data("cannot read PROBE_PASSWORD_FILE\n".utf8))
            exit(2)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return env["PROBE_PASSWORD"]
}()
guard keyPath != nil || password != nil else {
    FileHandle.standardError.write(Data("set PROBE_KEY, PROBE_PASSWORD_FILE or PROBE_PASSWORD\n".utf8))
    exit(2)
}
let port = Int(env["PROBE_PORT"] ?? "22") ?? 22

final class PinRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var key: String?
    func record(_ value: String) { lock.lock(); key = value; lock.unlock() }
    var value: String? { lock.lock(); defer { lock.unlock() }; return key }
}

do {
    let seed: Data
    if let keyPath {
        let keyString = try String(contentsOfFile: keyPath, encoding: .utf8)
        seed = try Curve25519.Signing.PrivateKey(sshEd25519: keyString).rawRepresentation
    } else {
        seed = Curve25519.Signing.PrivateKey().rawRepresentation
    }
    var settings = SSHConnectionSettings(vpsHost: host, vpsPort: port, username: user,
                                         homeHost: env["PROBE_HOME"] ?? "", privateKeySeed: seed)
    if let password {
        settings.passwords[.vps] = password
    }
    let thirdNode = UUID()
    if let extra = env["PROBE_NODE"], !extra.isEmpty {
        settings.additionalNodes = [
            .init(id: thirdNode,
                  host: extra,
                  port: Int(env["PROBE_NODE_PORT"] ?? "22") ?? 22,
                  parent: env["PROBE_NODE_VIA"] == "vps" ? .vps : nil)
        ]
    }
    func hop(_ spec: String) throws -> SSHConnectionSettings.Hop {
        let parts = spec.split(separator: ":", maxSplits: 1)
        let hopKeyPath = env["PROBE_BASTION_KEY"] ?? keyPath
        let hopSeed: Data
        if let hopKeyPath {
            let hopKey = try String(contentsOfFile: hopKeyPath, encoding: .utf8)
            hopSeed = try Curve25519.Signing.PrivateKey(sshEd25519: hopKey).rawRepresentation
        } else {
            hopSeed = Curve25519.Signing.PrivateKey().rawRepresentation
        }
        return .init(host: String(parts[0]),
                     port: parts.count > 1 ? Int(parts[1]) ?? 22 : 22,
                     username: env["PROBE_BASTION_USER"] ?? user,
                     privateKeySeed: hopSeed,
                     password: env["PROBE_BASTION_PASSWORD"] ?? (hopKeyPath == nil ? password : nil))
    }
    if let spec = env["PROBE_BASTION"], !spec.isEmpty {
        settings.bastion = try hop(spec)
        print("through bastion \(settings.bastion!.endpoint) as \(settings.bastion!.username)")
    }
    if let spec = env["PROBE_FALLBACK"], !spec.isEmpty {
        let parts = spec.split(separator: ":", maxSplits: 1)
        settings.entryFallback = .init(host: String(parts[0]),
                                       port: parts.count > 1 ? Int(parts[1]) ?? 22 : 22,
                                       bastion: env["PROBE_FALLBACK_VIA_BASTION"] == "1"
                                                ? settings.bastion : nil)
        print("fallback address \(settings.entryFallback!.host):\(settings.entryFallback!.port)")
    }
    if let spec = env["PROBE_PROXY"], !spec.isEmpty {
        guard let url = URL(string: spec), let proxyHost = url.host, let proxyPort = url.port else {
            FileHandle.standardError.write(Data("PROBE_PROXY must look like socks5://host:port\n".utf8))
            exit(2)
        }
        settings.proxy = .init(kind: url.scheme == "http" ? .httpConnect : .socks5,
                               host: proxyHost, port: proxyPort,
                               username: env["PROBE_PROXY_USER"],
                               password: env["PROBE_PROXY_PASSWORD"])
        print("through \(settings.proxy!.kind.rawValue) proxy \(proxyHost):\(proxyPort)")
    }

    let pin = PinRecorder()
    let runner = CitadelCommandRunner(settings: settings,
                                      onPinHostKey: { _, key in pin.record(key) })
    let command = env["PROBE_COMMAND"] ?? "echo GRYONIXNEXUS_PING; id; uname -a"
    let result = try await runner.run(command, on: .vps, timeout: .seconds(60))
    print("stdout: \(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines))")
    print("stderr: \(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
    print("host key: \(pin.value ?? "already pinned")")
    if env["PROBE_COMMAND"] == nil {
        print(result.stdout.contains("GRYONIXNEXUS_PING") ? "✓ PING" : "✗ no ping in stdout")
    }
    if settings.entryFallback != nil {
        print(await runner.isReachedByFallback(.vps)
              ? "✓ FALLBACK: reached through the second address"
              : "· primary address answered; the fallback was not needed")
    }

    if let home = env["PROBE_HOME"], !home.isEmpty {
        let first = try await runner.run("echo GRYONIXNEXUS_JUMP; hostname", on: .home, timeout: .seconds(30))
        print(first.stdout.contains("GRYONIXNEXUS_JUMP")
              ? "✓ JUMP \(first.stdout.split(separator: "\n").last.map(String.init) ?? "")"
              : "✗ no jump output")
        await runner.invalidateHome()
        let again = try await runner.run("echo GRYONIXNEXUS_REJUMP; hostname", on: .home, timeout: .seconds(30))
        print(again.stdout.contains("GRYONIXNEXUS_REJUMP")
              ? "✓ REJUMP after invalidateHome (the parent session survived)"
              : "✗ the home link did not come back")
    }
    if let extra = env["PROBE_NODE"], !extra.isEmpty {
        let via = env["PROBE_NODE_VIA"] == "vps" ? " through the entry host" : " directly"
        let result = try await runner.run("echo GRYONIXNEXUS_NODE; hostname", on: .node(thirdNode),
                                          timeout: .seconds(30))
        print(result.stdout.contains("GRYONIXNEXUS_NODE")
              ? "✓ NODE\(via): \(result.stdout.split(separator: "\n").last.map(String.init) ?? "")"
              : "✗ the third machine did not answer")
    }
    do {
        _ = try await runner.run("echo unreachable", on: .node(UUID()), timeout: .seconds(10))
        print("✗ an undescribed machine was reached — the runner guessed an address")
    } catch {
        print("✓ an undescribed machine is refused: \((error as? ServerControlError)?.errorDescription ?? "\(error)")")
    }
    await runner.disconnect()
    print("✓ disconnected")
} catch {
    print("✗ FAILED: \((error as? ServerControlError)?.errorDescription ?? String(describing: error))")
    print("  raw: \(error)")
    exit(1)
}
