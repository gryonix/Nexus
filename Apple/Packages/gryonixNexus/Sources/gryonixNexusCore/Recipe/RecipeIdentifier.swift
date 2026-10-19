/// Recipe identifier (for the registry / UI selection). E.g. "mail".
public struct RecipeIdentifier: Hashable, Sendable, RawRepresentable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}
