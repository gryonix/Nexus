public struct UpdateSpec: Sendable, Hashable {
    /// How the update is actually applied once one is found
    public enum Flavour: Sendable, Hashable {
        /// `docker compose pull` + `up -d` for the service's own project
        case composePull
        case ownUpdater
        case builtOnServer
    }

    public let images: [String]
    public let flavour: Flavour

    public init(images: [String], flavour: Flavour = .composePull) {
        self.images = images
        self.flavour = flavour
    }

    /// The updater-driven flavour, which names no images by design
    public static let ownUpdater = UpdateSpec(images: [], flavour: .ownUpdater)

    public static func builtOnServer(_ images: [String]) -> UpdateSpec {
        UpdateSpec(images: images, flavour: .builtOnServer)
    }
}

/// What the app knows about one service's updates
public enum ServiceUpdateStatus: Sendable, Hashable {
    case current
    /// At least one image behind this service has moved
    case available(images: [String])
    case selfManaged
    case rebuiltBySetup
    /// The check did not produce an answer
    case unknown
}
