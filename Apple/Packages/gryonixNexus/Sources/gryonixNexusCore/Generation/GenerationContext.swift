/// Shared contract for the generators' execution context.
/// A concrete recipe supplies its own context (e.g. MailContext).
public protocol GenerationContext {
    var renderer: any TemplateRenderer { get }
}
