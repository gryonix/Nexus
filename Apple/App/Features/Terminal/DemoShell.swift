import Foundation

/// Pretend shell of a demo server
struct DemoShell {
    let user: String
    let host: String
    private var line = ""

    init(user: String, host: String) {
        self.user = user.isEmpty ? "server-user" : user
        self.host = host
    }

    var banner: String {
        "Welcome to Debian GNU/Linux 13 (demo)\r\n"
            + "This is an example server: commands are not run anywhere.\r\n"
            + "Try: uptime, df -h, docker ps, free -h, help\r\n\r\n" + prompt
    }

    private var prompt: String { "\(user)@\(host.split(separator: ".").first ?? "demo"):~$ " }

    /// What the screen shows for the typed bytes
    mutating func input(_ bytes: ArraySlice<UInt8>) -> String {
        var shown = ""
        for byte in bytes {
            switch byte {
            case 13, 10:
                shown += "\r\n" + Self.answer(line.trimmingCharacters(in: .whitespaces)) + prompt
                line = ""
            case 127, 8:
                guard !line.isEmpty else { continue }
                line.removeLast()
                shown += "\u{8} \u{8}"
            case 3:
                line = ""
                shown += "^C\r\n" + prompt
            case 32...126:
                let character = String(UnicodeScalar(byte))
                line += character
                shown += character
            default:
                continue
            }
        }
        return shown
    }

    private static func answer(_ command: String) -> String {
        switch command {
        case "": return ""
        case "help": return "uptime  df -h  free -h  docker ps  whoami  ls\r\n"
        case "whoami": return "server-user\r\n"
        case "ls": return "backups  docker-compose  notes.txt\r\n"
        case "uptime": return " 10:42:07 up 47 days,  3:12,  1 user,  load average: 0.31, 0.28, 0.25\r\n"
        case "free -h":
            return "               total        used        free\r\nMem:           7.8Gi       5.0Gi       2.8Gi\r\n"
        case "df -h":
            return "Filesystem      Size  Used Avail Use% Mounted on\r\n/dev/sda1       160G   83G   77G  52% /\r\n"
        case "docker ps":
            return "CONTAINER ID   IMAGE                       STATUS\r\n"
                + "3f2a9c1d0e4b   vaultwarden/server:latest   Up 12 days (healthy)\r\n"
                + "8b7e6d5c4a3f   nextcloud:30-apache         Up 12 days\r\n"
        default:
            return "demo: \(command): runs only on your own server\r\n"
        }
    }
}
