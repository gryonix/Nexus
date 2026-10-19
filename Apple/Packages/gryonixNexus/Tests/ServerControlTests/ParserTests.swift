import XCTest
@testable import ServerControl

final class SysctlParserTests: XCTestCase {
    func testEnabled() throws {
        XCTAssertTrue(try SysctlParser.parseIPForwarding("net.ipv4.ip_forward = 1\n"))
    }

    func testDisabled() throws {
        XCTAssertFalse(try SysctlParser.parseIPForwarding("net.ipv4.ip_forward = 0"))
    }

    func testGarbageThrows() {
        XCTAssertThrowsError(try SysctlParser.parseIPForwarding("permission denied")) { error in
            guard case ServerControlError.parseFailure = error else {
                return XCTFail("expected parseFailure, got \(error)")
            }
        }
    }
}

final class PingParserTests: XCTestCase {
    func testAllReceived() throws {
        let output = """
        PING 1.2.3.4 (1.2.3.4) 56(84) bytes of data.
        64 bytes from 1.2.3.4: icmp_seq=1 ttl=64 time=0.3 ms

        --- 1.2.3.4 ping statistics ---
        4 packets transmitted, 4 received, 0% packet loss, time 3004ms
        """
        let result = try PingParser.parse(output)
        XCTAssertEqual(result.transmitted, 4)
        XCTAssertEqual(result.received, 4)
        XCTAssertTrue(result.isAlive)
    }

    func testNoneReceived() throws {
        let output = "1 packets transmitted, 0 received, 100% packet loss, time 0ms"
        let result = try PingParser.parse(output)
        XCTAssertEqual(result.received, 0)
        XCTAssertFalse(result.isAlive)
    }

    func testBusyboxVariant() throws {
        let output = "1 packets transmitted, 1 packets received, 0% packet loss"
        let result = try PingParser.parse(output)
        XCTAssertEqual(result.received, 1)
    }

    func testMissingStatsThrows() {
        XCTAssertThrowsError(try PingParser.parse("ping: unknown host"))
    }
}

final class WGShowParserTests: XCTestCase {
    private let sample = """
    interface: wg0
      public key: IFpUB1t5eqcpF4aYKsRhwc0vJnDPzM0hE2NGZ0i+HFY=
      private key: (hidden)
      listening port: 51820

    peer: cyfBMbaJ6kgnDYjio6xqWikJTEQAbnHnLEwGFdBpp0Q=
      endpoint: 203.0.113.4:51820
      allowed ips: 10.8.0.2/32
      latest handshake: 1 minute, 12 seconds ago
      transfer: 1.21 MiB received, 3.45 MiB sent
    """

    func testInterfaceBlock() throws {
        let status = try WGShowParser.parse(sample)
        XCTAssertEqual(status.interface.name, "wg0")
        XCTAssertEqual(status.interface.publicKey, "IFpUB1t5eqcpF4aYKsRhwc0vJnDPzM0hE2NGZ0i+HFY=")
        XCTAssertEqual(status.interface.listeningPort, 51820)
    }

    func testFreshPeer() throws {
        let status = try WGShowParser.parse(sample)
        XCTAssertEqual(status.peers.count, 1)
        let peer = try XCTUnwrap(status.peers.first)
        XCTAssertEqual(peer.endpoint, "203.0.113.4:51820")
        XCTAssertEqual(peer.allowedIPs, ["10.8.0.2/32"])
        XCTAssertEqual(peer.freshness, .ok)
    }

    func testStalePeerIsWarning() throws {
        let stale = sample.replacingOccurrences(
            of: "1 minute, 12 seconds ago", with: "3 hours, 2 minutes ago"
        )
        XCTAssertEqual(try WGShowParser.parse(stale).peers.first?.freshness, .warning)
    }

    func testPeerWithoutHandshakeIsCritical() throws {
        let never = """
        interface: wg0
          listening port: 51820

        peer: abc=
          allowed ips: 10.8.0.2/32
        """
        XCTAssertEqual(try WGShowParser.parse(never).peers.first?.freshness, .critical)
    }

    func testMultiplePeersFieldsDoNotLeak() throws {
        let two = sample + """


        peer: second+key=
          allowed ips: 10.8.0.3/32
        """
        let status = try WGShowParser.parse(two)
        XCTAssertEqual(status.peers.count, 2)
        XCTAssertNil(status.peers[1].endpoint)
        XCTAssertNil(status.peers[1].latestHandshake)
        XCTAssertEqual(status.peers[1].freshness, .critical)
    }

    func testNoInterfaceThrows() {
        XCTAssertThrowsError(try WGShowParser.parse(""))
    }
}

final class DFParserTests: XCTestCase {
    func testParsesMounts() throws {
        let output = """
        Mounted on     1B-blocks        Used Use%
        /            41678012416 12345678901  30%
        /boot          503316480    52428800  11%
        """
        let mounts = try DFParser.parse(output)
        XCTAssertEqual(mounts.count, 2)
        XCTAssertEqual(mounts[0].target, "/")
        XCTAssertEqual(mounts[0].sizeBytes, 41_678_012_416)
        XCTAssertEqual(mounts[0].usedBytes, 12_345_678_901)
        XCTAssertEqual(mounts[0].usedPercent, 30)
        XCTAssertEqual(mounts[1].target, "/boot")
        XCTAssertEqual(mounts[1].usedFraction, 52_428_800.0 / 503_316_480.0, accuracy: 0.0001)
    }

    func testEmptyThrows() {
        XCTAssertThrowsError(try DFParser.parse(""))
    }
}

final class FreeParserTests: XCTestCase {
    func testParsesMemAndSwap() throws {
        let output = """
                       total        used        free      shared  buff/cache   available
        Mem:      8201928704  1234567890  5000000000    10000000  1967360814  6600000000
        Swap:      104853504    12345678    92507826
        """
        let usage = try FreeParser.parse(output)
        XCTAssertEqual(usage.memTotalBytes, 8_201_928_704)
        XCTAssertEqual(usage.memUsedBytes, 1_234_567_890)
        XCTAssertEqual(usage.swapTotalBytes, 104_853_504)
        XCTAssertEqual(usage.swapUsedBytes, 12_345_678)
    }

    func testNoMemRowThrows() {
        XCTAssertThrowsError(try FreeParser.parse("total used free"))
    }
}

final class DockerComposePSParserTests: XCTestCase {
    func testParsesStatuses() throws {
        let output = """
        NAME                                  IMAGE                       COMMAND                  SERVICE          CREATED       STATUS                 PORTS
        mailcowdockerized-nginx-mailcow-1     nginx:mainline-alpine       "/docker-entrypoint.…"   nginx-mailcow    2 weeks ago   Up 2 hours (healthy)   0.0.0.0:443->443/tcp
        mailcowdockerized-postfix-mailcow-1   mailcow/postfix:1.77        "/docker-entrypoint.…"   postfix-mailcow  2 weeks ago   Exited (1) 3 days ago
        mailcowdockerized-watchdog-mailcow-1  mailcow/watchdog:2.05       "/watchdog.sh"           watchdog-mailcow 2 weeks ago   Restarting (1) 5 seconds ago
        """
        let statuses = try DockerComposePSParser.parse(output)
        XCTAssertEqual(statuses.count, 3)
        XCTAssertEqual(statuses[0].name, "mailcowdockerized-nginx-mailcow-1")
        XCTAssertEqual(statuses[0].health, .ok)
        XCTAssertEqual(statuses[1].health, .critical)
        XCTAssertEqual(statuses[2].health, .warning)
    }
}

final class DockerPSParserTests: XCTestCase {
    private let output = """
    CONTAINER ID   IMAGE                        COMMAND            CREATED       STATUS                  PORTS                    NAMES
    1a2b3c4d5e6f   vaultwarden/server:latest    "/start.sh"        3 weeks ago   Up 3 days (healthy)     127.0.0.1:8080->80/tcp   vaultwarden
    9f8e7d6c5b4a   nginx:alpine                 "/entrypoint.sh"   4 weeks ago   Exited (0) 2 days ago                            web,web-alias
    """

    func testFindsContainerByName() throws {
        let statuses = try DockerPSParser.parse(output)
        let vw = try XCTUnwrap(DockerPSParser.find(container: "vaultwarden", in: statuses))
        XCTAssertEqual(vw.health, .ok)
        XCTAssertTrue(vw.status.hasPrefix("Up 3 days"))
    }

    func testFindsAmongCommaSeparatedNames() throws {
        let statuses = try DockerPSParser.parse(output)
        let web = try XCTUnwrap(DockerPSParser.find(container: "web-alias", in: statuses))
        XCTAssertEqual(web.health, .critical)
    }

    func testMissingContainerIsNil() throws {
        let statuses = try DockerPSParser.parse(output)
        XCTAssertNil(DockerPSParser.find(container: "mailcow", in: statuses))
    }
}

final class BackupListParserTests: XCTestCase {
    func testParsesFilesAndDirectoriesSkipsTotalAndLinks() {
        let output = """
        total 1.5G
        -rw-r--r-- 1 root root 512M Jul 10 03:00 mailcow-2026-07-10.tar.gz
        drwxr-xr-x 2 root root 4.0K Jul  9 03:00 mailcow-2026-07-09-03-00-00
        lrwxrwxrwx 1 root root   24 Jul  8 03:00 latest -> mailcow-2026-07-09
        -rw-r--r-- 1 user user  48M Jul  9 03:05 vw-backup with space.tar.gz.gpg
        """
        let entries = BackupListParser.parse(output)
        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries[0].name, "mailcow-2026-07-10.tar.gz")
        XCTAssertEqual(entries[0].sizeText, "512M")
        XCTAssertEqual(entries[0].dateText, "Jul 10 03:00")
        XCTAssertEqual(entries[1].name, "mailcow-2026-07-09-03-00-00")
        XCTAssertEqual(entries[2].name, "vw-backup with space.tar.gz.gpg")
    }

    func testConsecutiveSpacesInNameSurvive() {
        let output = """
        -rw-r--r-- 1 user user 48M Jul  9 03:05 my  backup   v2.tar.gz.gpg
        """
        let entries = BackupListParser.parse(output)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].name, "my  backup   v2.tar.gz.gpg")
    }

    func testNameRepeatingAnEarlierColumnIsNotTruncated() {
        let output = """
        -rw-r--r-- 1 root root 4.0K Jul  9 03:05 root-4.0K.tar.gz
        """
        let entries = BackupListParser.parse(output)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].name, "root-4.0K.tar.gz")
    }

    func testGlobListingKeepsFullPathAndStripsItForDisplay() {
        let output = """
        -rw-r--r-- 1 user user 48M Jul  9 03:05 /opt/backups/vaultwarden/vault-20260709.tar.gz.gpg
        """
        let entries = BackupListParser.parse(output)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].name, "/opt/backups/vaultwarden/vault-20260709.tar.gz.gpg")
        XCTAssertEqual(entries[0].displayName, "vault-20260709.tar.gz.gpg")

        let plain = BackupListParser.parse(
            "-rw-r--r-- 1 user user 48M Jul  9 03:05 vault-20260709.tar.gz.gpg")
        XCTAssertEqual(plain[0].displayName, "vault-20260709.tar.gz.gpg")
    }

    func testLimit() {
        let line = "-rw-r--r-- 1 root root 1M Jul 10 03:00 file-%d.gz"
        let output = (0..<15).map { String(format: line, $0) }.joined(separator: "\n")
        XCTAssertEqual(BackupListParser.parse(output).count, 10)
    }
}

final class UtilityTests: XCTestCase {
    func testANSIStripping() {
        let colored = "\u{1B}[1;32mOK\u{1B}[0m done \u{1B}[2K\u{1B}[1Gend"
        XCTAssertEqual(ANSIStripper.strip(colored), "OK done end")
    }

    func testCarriageReturnProgressCollapsed() {
        let progress = "Downloading 10%\rDownloading 50%\rDownloading 100%\nDone"
        XCTAssertEqual(ANSIStripper.strip(progress), "Downloading 100%\nDone")
    }

    func testOutputTail() {
        let long = String(repeating: "a", count: 5000) + "END"
        let tail = OutputTail.tail(long)
        XCTAssertEqual(tail.count, 3001) // ellipsis + 3000 chars
        XCTAssertTrue(tail.hasSuffix("END"))
        XCTAssertTrue(tail.hasPrefix("…"))
        XCTAssertEqual(OutputTail.tail("short"), "short")
    }

    func testShellSingleQuoting() {
        XCTAssertEqual(ShellQuoting.singleQuoted("plain"), "'plain'")
        XCTAssertEqual(ShellQuoting.singleQuoted("pa's$w`d"), #"'pa'\''s$w`d'"#)
    }
}

final class DKIMRecordParserTests: XCTestCase {
    private let report = """
    Mailcow:      https://mail.example.com  (directory: /opt/mailcow-dockerized)
      Administrator: admin
      DKIM record dkim._domainkey.example.com:
      v=DKIM1;k=rsa;p=MIIBIjANBg
    GRYONIXNEXUS_DKIM dkim._domainkey.example.com v=DKIM1;k=rsa;p=MIIBIjANBg
    """

    func testParsesMarkerLine() {
        let records = DKIMRecordParser.parse(report)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.name, "dkim._domainkey.example.com")
        XCTAssertEqual(records.first?.value, "v=DKIM1;k=rsa;p=MIIBIjANBg")
        XCTAssertEqual(records.first?.type, "TXT")
    }

    /// Multi-domain setups print one line per mail domain
    func testParsesEveryDomain() {
        let records = DKIMRecordParser.parse("""
        GRYONIXNEXUS_DKIM dkim._domainkey.a.com v=DKIM1;p=AAA
        GRYONIXNEXUS_DKIM dkim._domainkey.b.com v=DKIM1;p=BBB
        """)
        XCTAssertEqual(records.map(\.name), ["dkim._domainkey.a.com", "dkim._domainkey.b.com"])
        XCTAssertEqual(records.map(\.value), ["v=DKIM1;p=AAA", "v=DKIM1;p=BBB"])
    }

    func testValueMayContainSpaces() {
        let records = DKIMRecordParser.parse("GRYONIXNEXUS_DKIM dkim._domainkey.x.com v=DKIM1; k=rsa; p=AAA")
        XCTAssertEqual(records.first?.value, "v=DKIM1; k=rsa; p=AAA")
    }

    func testNoMarkerMeansNoRecords() {
        XCTAssertTrue(DKIMRecordParser.parse("  DKIM is not ready yet\n").isEmpty)
    }

    func testStripMarkersLeavesTheHumanReport() {
        let readable = DKIMRecordParser.stripMarkers(from: report)
        XCTAssertFalse(readable.contains("GRYONIXNEXUS_DKIM"))
        XCTAssertTrue(readable.contains("DKIM record dkim._domainkey.example.com:"))
        XCTAssertTrue(readable.contains("Administrator: admin"))
    }
}
