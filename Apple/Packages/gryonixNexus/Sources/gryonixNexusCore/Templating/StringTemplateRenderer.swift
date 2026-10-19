import Foundation

/// A simple built-in renderer with no external dependencies
public struct StringTemplateRenderer: TemplateRenderer {
    public init() {}

    public func render(template: String, with values: [String: String]) throws -> String {
        var result = template
        for (key, value) in values {
            result = result.replacingOccurrences(of: "{{\(key)}}", with: value)
        }
        if let range = result.range(of: #"\{\{[A-Za-z0-9_.-]+\}\}"#, options: .regularExpression) {
            throw TemplateError.unresolvedPlaceholder(String(result[range]))
        }
        return result
    }
}
