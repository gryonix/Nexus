/// Base generator for a single kind of artifact. The recipe supplies the context,
/// so the same generator is reused across different scenarios.
public protocol ArtifactGenerator {
    associatedtype Context: GenerationContext

    func generate(in context: Context) throws -> [Artifact]
}
