import ServiceCatalog
import SwiftUI

enum ServiceQuestion: String, CaseIterable, Identifiable {
    /// Mojang's EULA for the Java edition — refused without it
    case minecraftJavaEULA
    /// Mojang's EULA for the Bedrock edition — refused without it
    case minecraftBedrockEULA
    /// Home-only services on a machine that could be anywhere
    case machineAtHome

    var id: String { rawValue }

    /// The service that raises the question
    var service: ServiceID {
        switch self {
        case .minecraftJavaEULA: return .minecraftJava
        case .minecraftBedrockEULA: return .minecraftBedrock
        case .machineAtHome: return .homeAssistant
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .minecraftJavaEULA, .minecraftBedrockEULA:
            return "I accept Mojang's End User License Agreement"
        case .machineAtHome:
            return "This machine stands in my home"
        }
    }

    var refusal: LocalizedStringKey {
        switch self {
        case .minecraftJavaEULA, .minecraftBedrockEULA:
            return "Without this the server will not start, so it will not be installed."
        case .machineAtHome:
            return "Home Assistant has to see the lights and sensors on your home network. On a rented server it would find none, so it will not be installed."
        }
    }
}

enum ServiceQuestions {
    static func raised(by services: Set<ServiceID>, topology: Topology,
                       scope: DeploymentScope) -> [ServiceQuestion] {
        ServiceQuestion.allCases.filter { question in
            guard services.contains(question.service) else { return false }
            guard question == .machineAtHome else { return true }
            return HomePlacement.needsAnswer(topology: topology, scope: scope)
        }
    }
}
