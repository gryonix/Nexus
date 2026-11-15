import ServiceCatalog
import SwiftUI

enum ServiceQuestion: String, CaseIterable, Identifiable {
    /// Mojang's EULA for the Java edition — refused without it
    case minecraftJavaEULA
    /// Mojang's EULA for the Bedrock edition — refused without it
    case minecraftBedrockEULA
    /// Home-only services on a machine that could be anywhere
    case machineAtHome
    /// The home question, for the speaker
    case speakerAtHome
    /// The home question, for the screen
    case screenAtHome
    /// The home question, for the audio hub
    case hubAtHome

    /// Questions about one fact: the machine stands at home
    static let homeKinds: [ServiceQuestion] = [.machineAtHome, .speakerAtHome, .screenAtHome, .hubAtHome]

    var id: String { rawValue }

    /// The service that raises the question
    var service: ServiceID {
        switch self {
        case .minecraftJavaEULA: return .minecraftJava
        case .minecraftBedrockEULA: return .minecraftBedrock
        case .machineAtHome: return .homeAssistant
        case .speakerAtHome: return .shairportSync
        case .screenAtHome: return .uxplay
        case .hubAtHome: return .odio
        }
    }

    /// Every service that raises the question
    var services: Set<ServiceID> {
        guard self == .hubAtHome else { return [service] }
        return [.odio, .snapserver, .snapclient, .upmpdcli, .bluealsa, .raspotify, .mympd]
    }

    var title: LocalizedStringKey {
        switch self {
        case .minecraftJavaEULA, .minecraftBedrockEULA:
            return "I accept Mojang's End User License Agreement"
        case .machineAtHome, .speakerAtHome, .screenAtHome, .hubAtHome:
            return "This machine stands in my home"
        }
    }

    var refusal: LocalizedStringKey {
        switch self {
        case .minecraftJavaEULA, .minecraftBedrockEULA:
            return "Without this the server will not start, so it will not be installed."
        case .machineAtHome:
            return "Home Assistant has to see the lights and sensors on your home network. On a rented server it would find none, so it will not be installed."
        case .speakerAtHome:
            return "The AirPlay speaker plays through the speakers of the room this machine stands in. On a rented server there are none, so it will not be installed."
        case .screenAtHome:
            return "The AirPlay screen shows on the TV this machine is connected to. On a rented server there is none, so it will not be installed."
        case .hubAtHome:
            return "The audio hub plays through the speakers of the room this machine stands in. On a rented server there are none, so it will not be installed."
        }
    }
}

enum ServiceQuestions {
    static func raised(by services: Set<ServiceID>, topology: Topology,
                       scope: DeploymentScope) -> [ServiceQuestion] {
        let asked = ServiceQuestion.allCases.filter { question in
            guard !services.isDisjoint(with: question.services) else { return false }
            guard ServiceQuestion.homeKinds.contains(question) else { return true }
            return HomePlacement.needsAnswer(topology: topology, scope: scope)
        }
        guard let firstHome = ServiceQuestion.homeKinds.first(where: asked.contains) else { return asked }
        return asked.filter { !ServiceQuestion.homeKinds.contains($0) || $0 == firstHome }
    }
}
