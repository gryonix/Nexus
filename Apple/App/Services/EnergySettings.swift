import Foundation
import ServerControl

/// Electricity price and each server's estimate profile
@MainActor
final class EnergySettings: ObservableObject {
    static let shared = EnergySettings()

    private enum Key {
        static let price = "energy.pricePerKWh"
        static let currency = "energy.currency"
        static let profiles = "energy.profiles"
        static let detected = "energy.detected"
    }

    private let defaults: UserDefaults

    @Published var pricePerKWh: Double {
        didSet { defaults.set(pricePerKWh, forKey: Key.price) }
    }

    @Published var currencyCode: String {
        didSet { defaults.set(currencyCode, forKey: Key.currency) }
    }

    @Published private var profiles: [String: EnergyProfile] {
        didSet {
            if let data = try? JSONEncoder().encode(profiles) { defaults.set(data, forKey: Key.profiles) }
        }
    }

    @Published private var detected: [String: PowerEstimate] {
        didSet {
            if let data = try? JSONEncoder().encode(detected) { defaults.set(data, forKey: Key.detected) }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let currency = defaults.string(forKey: Key.currency)
            ?? Locale.current.currency?.identifier ?? "EUR"
        currencyCode = currency
        pricePerKWh = defaults.object(forKey: Key.price) as? Double
            ?? Self.typicalPrice[currency] ?? 0.30
        profiles = defaults.data(forKey: Key.profiles)
            .flatMap { try? JSONDecoder().decode([String: EnergyProfile].self, from: $0) } ?? [:]
        detected = defaults.data(forKey: Key.detected)
            .flatMap { try? JSONDecoder().decode([String: PowerEstimate].self, from: $0) } ?? [:]
    }

    /// A household price per kWh to start from, by currency
    static let typicalPrice: [String: Double] = [
        "EUR": 0.30, "USD": 0.17, "GBP": 0.25, "CHF": 0.30, "PLN": 1.0, "CZK": 6.0,
        "SEK": 1.5, "DKK": 2.2, "NOK": 1.5, "HUF": 70, "RON": 1.3, "BGN": 0.3,
        "UAH": 4.3, "RUB": 6.5, "JPY": 31, "CNY": 0.6,
    ]

    static func key(_ deploymentID: UUID, _ host: SSHHostID) -> String {
        "\(deploymentID.uuidString)/\(String(describing: host))"
    }

    /// Typed watts, else the parts estimate, else a guess
    func profile(_ deploymentID: UUID, _ host: SSHHostID, cores: Int? = nil) -> EnergyProfile {
        let key = Self.key(deploymentID, host)
        return profiles[key] ?? detected[key]?.profile ?? .guess(cores: cores ?? 4)
    }

    /// History points with power filled in and completed
    func filled(_ points: [MetricsHistoryPoint], _ deploymentID: UUID,
                _ host: SSHHostID) -> [MetricsHistoryPoint] {
        EnergyMath.filled(points, profile: profile(deploymentID, host),
                          estimate: estimate(deploymentID, host))
    }

    func setProfile(_ profile: EnergyProfile, _ deploymentID: UUID, _ host: SSHHostID) {
        profiles[Self.key(deploymentID, host)] = profile
    }

    func isTyped(_ deploymentID: UUID, _ host: SSHHostID) -> Bool {
        profiles[Self.key(deploymentID, host)] != nil
    }

    /// Forgets everything kept for a server that left the app
    func forget(deploymentID: UUID) {
        let prefix = deploymentID.uuidString + "/"
        profiles = profiles.filter { !$0.key.hasPrefix(prefix) }
        detected = detected.filter { !$0.key.hasPrefix(prefix) }
    }

    func clearProfile(_ deploymentID: UUID, _ host: SSHHostID) {
        profiles[Self.key(deploymentID, host)] = nil
    }

    func estimate(_ deploymentID: UUID, _ host: SSHHostID) -> PowerEstimate? {
        detected[Self.key(deploymentID, host)]
    }

    func setEstimate(_ estimate: PowerEstimate, _ deploymentID: UUID, _ host: SSHHostID) {
        detected[Self.key(deploymentID, host)] = estimate
    }

    /// Hardware is read again after a week
    func needsDetection(_ deploymentID: UUID, _ host: SSHHostID, now: Date = Date()) -> Bool {
        guard let found = detected[Self.key(deploymentID, host)] else { return true }
        return now.timeIntervalSince(found.detectedAt) > 7 * 86_400
    }

    /// Reads the host's parts weekly; failures keep the old estimate
    func detect(_ deploymentID: UUID, _ host: SSHHostID, runner: any SSHCommandRunner) async {
        guard needsDetection(deploymentID, host),
              let result = try? await runner.run(PowerHardware.probeCommand, on: host, timeout: .seconds(20)),
              let hardware = PowerHardware.parse(result.stdout)
        else { return }
        setEstimate(PowerEstimate(hardware), deploymentID, host)
    }

    func cost(_ kilowattHours: Double) -> String {
        (kilowattHours * pricePerKWh).formatted(.currency(code: currencyCode))
    }
}

enum EnergyFormat {
    static func watts(_ value: Double) -> String {
        UIL10n.string("%@ W", number(value))
    }

    static func range(_ low: Double, _ high: Double) -> String {
        UIL10n.string("%@–%@ W", number(low), number(high))
    }

    private static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(value < 10 ? 1 : 0)))
    }

    static func kilowattHours(_ value: Double) -> String {
        UIL10n.string("%@ kWh", value.formatted(.number.precision(.fractionLength(value < 10 ? 2 : 1))))
    }
}
