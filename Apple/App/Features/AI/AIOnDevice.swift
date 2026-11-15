import AIAssistant
import Foundation
#if canImport(FoundationModels) && !os(tvOS)
import FoundationModels
#endif

/// Apple's on-device model, where the system offers it
enum AIOnDevice {
    enum Status: Equatable {
        case ready, needsNewerSystem, deviceNotEligible, intelligenceOff, downloading, unavailable
    }

    static var status: Status {
        #if canImport(FoundationModels) && !os(tvOS)
        if #available(iOS 26.0, macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return .ready
            case .unavailable(.deviceNotEligible): return .deviceNotEligible
            case .unavailable(.appleIntelligenceNotEnabled): return .intelligenceOff
            case .unavailable(.modelNotReady): return .downloading
            case .unavailable: return .unavailable
            }
        }
        #endif
        return .needsNewerSystem
    }

    /// Streams the answer as text pieces
    static func stream(system: String, messages: [AIMessage]) -> AsyncThrowingStream<AIStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await run(system: system, prompt: AIOnDevicePrompt.build(messages), continuation: continuation)
                    continuation.yield(.done)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func run(system: String, prompt: String,
                            continuation: AsyncThrowingStream<AIStreamEvent, Error>.Continuation) async throws {
        #if canImport(FoundationModels) && !os(tvOS)
        if #available(iOS 26.0, macOS 26.0, *), status == .ready {
            let session = LanguageModelSession(instructions: system)
            var sent = 0
            for try await snapshot in session.streamResponse(to: prompt) {
                let text = snapshot.content
                if text.count > sent {
                    continuation.yield(.text(String(text.dropFirst(sent))))
                    sent = text.count
                }
            }
            return
        }
        #endif
        throw AIChatFailure(message: UIL10n.string("The on-device model is not available on this device."))
    }
}
