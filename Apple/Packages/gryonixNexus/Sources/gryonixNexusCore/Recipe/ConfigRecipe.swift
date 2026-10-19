/// The unified "recipe" contract for generation. The core doesn't know about mail —
/// mail is just one implementation. Future recipes plug in here too.
public protocol ConfigRecipe {
    associatedtype Input: RecipeInput

    var identifier: RecipeIdentifier { get }

    func validate(_ input: Input) throws
    func generate(from input: Input) throws -> GeneratedBundle
}
