/// Renders text templates into a finished config.
///
/// Design decision: templates are passed as strings (assembled in Swift code)
/// rather than loaded from resources — generation is fully self-contained,
/// nothing is read from disk while the app runs.
public protocol TemplateRenderer: Sendable {
    func render(template: String, with values: [String: String]) throws -> String
}

public enum TemplateError: Error, Sendable, Hashable {
    case unresolvedPlaceholder(String)
}
