import Foundation
import Crypto
import ServiceCatalog
import ServerControl
import ServerControlSSH

struct SmokeError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

var failures: [String] = []

func check(_ ok: Bool, _ what: String) {
    if ok {
        print("✓ \(what)")
    } else {
        print("✗ \(what)")
        failures.append(what)
    }
}

func describe(_ error: Error) -> String {
    (error as? ServerControlError)?.errorDescription ?? String(describing: error)
}

func run() async throws {
    let env = ProcessInfo.processInfo.environment
    guard let host = env["MAILBOX_HOST"], let user = env["MAILBOX_USER"],
          let keyPath = env["MAILBOX_KEY"], let domain = env["MAILBOX_DOMAIN"] else {
        throw SmokeError("set MAILBOX_HOST, MAILBOX_USER, MAILBOX_KEY, MAILBOX_DOMAIN")
    }
    let keyString = try String(contentsOfFile: keyPath, encoding: .utf8)
    let seed = try Curve25519.Signing.PrivateKey(sshEd25519: keyString).rawRepresentation

    let settings = SSHConnectionSettings(vpsHost: host, username: user,
                                         homeHost: "", privateKeySeed: seed)
    let runner = CitadelCommandRunner(settings: settings)
    defer { Task { await runner.disconnect() } }

    let deployment = Deployment(
        name: "mailbox-smoke",
        topology: .singleHost,
        domain: domain,
        entry: HostEndpoint(host: host, user: user),
        services: [.dockerMailserver])
    let mailboxes = MailboxOperations(runner: runner, deployment: deployment)

    let stage = env["MAILBOX_STAGE"] ?? "all"
    let fresh = "smoke.fresh@\(domain)"      // created and removed by this run
    let used = "smoke.used@\(domain)"
    let password = env["MAILBOX_PASSWORD"] ?? "Sm0ke-\(UInt32.random(in: 100_000...999_999))!"

    if try await runSingleStage(stage, mailboxes: mailboxes, domain: domain, used: used,
                                password: password) {
        return
    }
    try await checkLifecycle(mailboxes, fresh: fresh, used: used, password: password)
    try await checkRefusals(mailboxes, runner: runner, domain: domain, password: password)
    try await checkOutsideMailbox(mailboxes, env: env)
}

func runSingleStage(_ stage: String, mailboxes: MailboxOperations, domain: String, used: String,
                    password: String) async throws -> Bool {
    // ---------------------------------------------------------------- 1. empty
    if stage == "empty" {
        let empty = try await mailboxes.list()
        print("  list() → \(empty.count) mailbox(es): \(empty.map(\.address))")
        check(empty.isEmpty, "fresh install lists ZERO mailboxes and does not throw (GOTCHAS defect #8)")
        return true
    }

    if stage == "secret" {
        let scratch = "smoke.secret@\(domain)"
        try await mailboxes.add(address: scratch, password: password)
        check(true, "add(\(scratch)) with the scanned password")
        try await mailboxes.setPassword(address: scratch, password: password)
        check(true, "setPassword(\(scratch)) with the scanned password")
        try await mailboxes.delete(address: scratch)
        check(true, "delete(\(scratch))")
        return true
    }

    if stage == "add-delete" {
        let scratch = "smoke.neverused@\(domain)"
        try await mailboxes.add(address: scratch, password: password)
        check(true, "add(\(scratch))")
        do {
            try await mailboxes.delete(address: scratch)
            check(true, "delete immediately after add succeeds (the wrapper waits out the race)")
        } catch {
            print("  delete(immediately after add) → \(describe(error))")
            check(false, "delete immediately after add should succeed")
        }
        let after = try await mailboxes.list()
        print("  list() after → \(after.map(\.address))")
        check(!after.contains { $0.address == scratch },
              "a mailbox deleted right after being added is really gone")
        return true
    }

    if stage == "add-used" {
        try await mailboxes.add(address: used, password: password)
        print("  added \(used) with password \(password)")
        check(true, "add(\(used))")
        return true
    }
    return false
}

func checkLifecycle(_ mailboxes: MailboxOperations, fresh: String, used: String,
                    password: String) async throws {
    // ------------------------------------------------------------------ 2. add
    let before = try await mailboxes.list()
    print("  list() before → \(before.map(\.address))")

    try await mailboxes.add(address: fresh, password: password)
    check(true, "add(\(fresh))")

    let afterAdd = try await mailboxes.list()
    print("  list() after add → "
          + afterAdd.map { "\($0.address) | detail=\($0.detail ?? "nil")" }.joined(separator: "  ·  "))
    guard let added = afterAdd.first(where: { $0.address == fresh }) else {
        throw SmokeError("the mailbox just added is not in the listing")
    }
    check(added.isManageable, "the new mailbox is manageable (both validators agree)")
    print("  detail of a freshly added mailbox: \(added.detail.map { "'\($0)'" } ?? "nil")")

    // ------------------------------------------------------------- 3. password
    try await mailboxes.setPassword(address: fresh, password: password + "x")
    check(true, "setPassword(\(fresh))")

    try await mailboxes.delete(address: fresh)
    check(true, "delete(\(fresh))")
    let afterDeleteFresh = try await mailboxes.list()
    print("  list() after delete → \(afterDeleteFresh.map(\.address))")
    check(!afterDeleteFresh.contains { $0.address == fresh }, "it is gone from the listing")

    do {
        try await mailboxes.delete(address: fresh)
        check(false, "deleting an address that is gone must NOT report success")
    } catch {
        print("  delete(already gone) → \(describe(error))")
        check(!describe(error).contains("\u{1B}"), "the engine's failure carries no ANSI escapes")
        check(true, "deleting an address that is gone surfaces the engine's own message")
    }

    // ------------------------------------------ 5. delete a box with real mail
    if afterDeleteFresh.contains(where: { $0.address == used }) {
        try await mailboxes.delete(address: used)
        check(true, "delete(\(used)) — a mailbox holding a delivered message")
        let afterDelete = try await mailboxes.list()
        print("  list() after delete → \(afterDelete.map(\.address))")
        check(!afterDelete.contains { $0.address == used }, "the used mailbox is gone from the listing")
    } else {
        print("  (skipped: \(used) is not on the server — create and deliver to it first)")
    }
}

func checkRefusals(_ mailboxes: MailboxOperations, runner: CitadelCommandRunner, domain: String,
                   password: String) async throws {
    // ------------------------------------------- 6. an address the app refuses
    for bad in ["a b@\(domain)", "a@b@\(domain)", "-flag@\(domain)", "x;id@\(domain)",
                "$(id)@\(domain)", "no-at-sign", "x'y@\(domain)"] {
        do {
            try await mailboxes.add(address: bad, password: password)
            check(false, "add(\(bad.debugDescription)) must be refused")
        } catch {
            print("  add(\(bad.debugDescription)) → \(describe(error))")
            check(true, "refused \(bad.debugDescription)")
        }
    }

    for hostile in ["x;id@\(domain)", "x$(id)@\(domain)", "x`id`@\(domain)",
                    "x|id@\(domain)", "../../etc/passwd", "-y", "a@b@c",
                    "x y@\(domain)", "x'y@\(domain)"] {
        let line = CommandCatalog.DockerMailserver.addMailbox(address: hostile)
        let result = try await runner.run(line, feeding: password, on: .vps, timeout: .seconds(30))
        let refused = !result.succeeded
            && !result.stdout.contains(CommandCatalog.DockerMailserver.mailboxDoneMarker)
        print("  wrapper add(\(hostile.debugDescription)) → exit=\(result.exitCode.map(String.init) ?? "nil") "
              + "stderr=\(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines).debugDescription)")
        check(refused, "the wrapper itself refuses \(hostile.debugDescription)")
    }
}

func checkOutsideMailbox(_ mailboxes: MailboxOperations, env: [String: String]) async throws {
    // ---------------- 7. a mailbox created OUTSIDE the app: listed, not usable
    let outside = env["MAILBOX_OUTSIDE"] ?? ""
    if !outside.isEmpty {
        let listed = try await mailboxes.list()
        if let box = listed.first(where: { $0.address == outside }) {
            check(true, "the out-of-band mailbox \(outside) is LISTED")
            check(!box.isManageable, "…and is not manageable (buttons disabled, no failed command)")
        } else {
            check(false, "the out-of-band mailbox \(outside) is missing from the listing")
        }
    }
}

let done = DispatchSemaphore(value: 0)
Task {
    do {
        try await run()
    } catch {
        FileHandle.standardError.write(Data("mailbox-smoke: \(describe(error))\n".utf8))
        failures.append("threw: \(describe(error))")
    }
    done.signal()
}
done.wait()

if failures.isEmpty {
    print("── all checks passed")
} else {
    print("── \(failures.count) FAILED: \(failures.joined(separator: "; "))")
    exit(1)
}
