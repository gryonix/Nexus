import Foundation

/// Idle and full-load package watts by processor model
public enum ProcessorPower {
    /// What kind of machine a processor usually sits in
    public enum Platform: String, Codable, Sendable { case server, desktop, compact }

    public struct Figures: Sendable, Hashable {
        public let idle: Double
        public let peak: Double
        public let platform: Platform
    }

    private struct Rule {
        let pattern: String
        let figures: (Double) -> Figures

        init(_ pattern: String, _ figures: @escaping (Double) -> Figures) {
            self.pattern = pattern
            self.figures = figures
        }

        init(_ pattern: String, _ idle: Double, _ peak: Double, _ platform: Platform) {
            self.init(pattern) { _ in Figures(idle: idle, peak: peak, platform: platform) }
        }
    }

    /// One package's figures from its model name and cores
    public static func figures(model: String, cores: Int) -> Figures {
        let name = normalized(model)
        let count = Double(max(cores, 1))
        let rule = rules.first { name.range(of: $0.pattern, options: [.regularExpression, .caseInsensitive]) != nil }
        return rule?.figures(count) ?? fallback(count)
    }

    static func normalized(_ model: String) -> String {
        model.replacingOccurrences(of: "(R)", with: "")
            .replacingOccurrences(of: "(TM)", with: "")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    private static func fallback(_ cores: Double) -> Figures {
        let idle = 4 + 0.5 * cores
        return Figures(idle: idle, peak: min(idle + 5 * cores, 250), platform: .desktop)
    }

    private static func manyCore(idle: Double, perCore: Double, base: Double,
                                 floor: Double, ceiling: Double) -> (Double) -> Figures {
        { cores in
            Figures(idle: idle + 0.3 * cores,
                    peak: min(max(base + perCore * cores, floor), ceiling), platform: .server)
        }
    }

    private static let rules: [Rule] = amdRules + intelRules + otherRules

    private static let amdRules: [Rule] = [
        Rule("EPYC 3[0-9]{3}\\b", 10, 50, .compact),
        Rule("EPYC 4[0-9]{3}", 15, 90, .desktop),
        Rule("EPYC", manyCore(idle: 30, perCore: 2.5, base: 120, floor: 120, ceiling: 400)),
        Rule("Threadripper", manyCore(idle: 40, perCore: 5, base: 100, floor: 180, ceiling: 350)),
        Rule("Ryzen.* [0-9]{3,4}(U|C)\\b", 2, 25, .compact),
        Rule("Ryzen.* [0-9]{3,4}(HS|HX|H)\\b", 4, 55, .compact),
        Rule("Ryzen.* [0-9]{4}GE\\b", 4, 35, .desktop),
        Rule("Ryzen.* [0-9]{4}G\\b", 5, 70, .desktop),
        Rule("Ryzen 9 .*[0-9]{4}X", 22, 150, .desktop),
        Rule("Ryzen.* [0-9]{4}X", 18, 105, .desktop),
        Rule("Ryzen AI", 3, 55, .compact),
        Rule("Ryzen", 15, 75, .desktop),
        Rule("Opteron|FX-", 20, 110, .desktop),
    ]

    private static let intelRules: [Rule] = [
        Rule("Xeon.* D-[0-9]{4}", 10, 50, .compact),
        Rule("Xeon.* E3-[0-9]{4}L", 5, 25, .desktop),
        Rule("Xeon.* (E3-[0-9]{4}|E-2[0-9]{3})", 8, 80, .desktop),
        Rule("Xeon", manyCore(idle: 10, perCore: 5.5, base: 35, floor: 45, ceiling: 350)),
        Rule("\\b(N[0-9]{2,3}|[JN][0-9]{4})\\b", 2, 12, .compact),
        Rule("Atom", 5, 20, .compact),
        Rule("Ultra.* [0-9]{3}(U|V)\\b", 2, 25, .compact),
        Rule("Ultra.* [0-9]{3}H", 4, 55, .compact),
        Rule("Ultra.* [0-9]{3}K", 10, 160, .desktop),
        Rule("Ultra", 8, 90, .desktop),
        Rule("i[3579]-[0-9]{3,5}[A-Z]*(U|Y)", 2, 20, .compact),
        Rule("i[3579]-[0-9]{3,5}[A-Z]*G[0-9]", 3, 28, .compact),
        Rule("i[3579]-[0-9]{3,5}HX", 5, 90, .compact),
        Rule("i[3579]-[0-9]{3,5}H", 4, 50, .compact),
        Rule("i[3579]-[0-9]{3,5}P", 3, 35, .compact),
        Rule("i[3579]-[0-9]{3,5}T", 4, 35, .desktop),
        Rule("i[3579]-[0-9]{3,5}K", 10, 150, .desktop),
        Rule("i[3579]-[0-9]{3,5}", 7, 70, .desktop),
        Rule("(Pentium|Celeron).* G[0-9]{4}", 4, 50, .desktop),
        Rule("Pentium|Celeron", 3, 15, .compact),
    ]

    private static let otherRules: [Rule] = [
        Rule("Ampere|Altra|Neoverse", manyCore(idle: 25, perCore: 2.8, base: 0, floor: 40, ceiling: 250)),
    ]
}
