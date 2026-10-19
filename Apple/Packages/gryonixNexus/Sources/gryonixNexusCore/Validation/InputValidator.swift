/// Validator for a specific recipe's input data.
public protocol InputValidator {
    associatedtype Input

    func validate(_ input: Input) throws
}
