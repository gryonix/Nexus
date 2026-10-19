/// The Docker network the AI services reach each other on
public enum AIServicesNetwork {
    /// External, so removing one service leaves it to the rest
    public static let name = "gryonixnexus-ai"

    /// A neighbour's address on the shared network
    public static func url(_ container: String, _ port: Int) -> String {
        "http://\(container):\(port)"
    }

    /// Joins a service to the network; ends its compose file
    public static let composeTail =
        "\n    networks:\n      - \(name)\nnetworks:\n  \(name):\n    external: true"

    /// Creates the network once; later runs find it there
    public static let createStep = "docker network create \(name) >/dev/null 2>&1 || true"
}
