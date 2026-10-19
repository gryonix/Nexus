import gryonixNexusCore

/// ConfigRecipe implementation for mail
public struct MailRecipe: ConfigRecipe {
    public typealias Input = MailRecipeInput

    public let identifier = RecipeIdentifier(rawValue: "mail")

    private let renderer: any TemplateRenderer
    private let keyProvider: any WireGuardKeyProvider

    public init(
        renderer: any TemplateRenderer = StringTemplateRenderer(),
        keyProvider: any WireGuardKeyProvider = CryptoKitWireGuardKeyProvider()
    ) {
        self.renderer = renderer
        self.keyProvider = keyProvider
    }

    public func validate(_ input: MailRecipeInput) throws {
        try MailInputValidator().validate(input)
    }

    public func generate(from input: MailRecipeInput) throws -> GeneratedBundle {
        try validate(input)
        let context = MailContext(input: input, renderer: renderer)

        var artifacts = try DNSRecordGenerator().generate(in: context)
        var serviceScripts: [Artifact] = []
        switch input.topology {
        case .singleHost:
            artifacts.append(try SetupScripts.mailServer(context))
            serviceScripts = SetupScripts.serviceScripts(context, ptrIP: context.mailHost?.publicAddress?.value ?? "")
        case .vpsRelayWithHomeBackend:
            let vpsKeys = try keyProvider.makeKeyPair(for: .vps)
            let homeKeys = try keyProvider.makeKeyPair(for: .home)
            artifacts.append(try SetupScripts.vps(context, vpsKeys: vpsKeys, homePublicKey: homeKeys.publicKey))
            artifacts.append(try SetupScripts.homeServer(context, homeKeys: homeKeys, vpsPublicKey: vpsKeys.publicKey))
            let relayIP = context.server(.vpsRelay)?.publicAddress?.value ?? ""
            let tunnel = L10nScripts.tunnelReportLine(context.language,
                                                      endpoint: "\(relayIP):\(WireGuardDefaults.listenPort)")
            serviceScripts = SetupScripts.serviceScripts(context, ptrIP: relayIP, extraLines: [tunnel])
        }

        return GeneratedBundle(
            artifacts: artifacts,
            warnings: warnings(for: context),
            notes: notes(for: context),
            serviceScripts: serviceScripts
        )
    }

    // MARK: - Warnings and application

    private func warnings(for context: MailContext) -> [String] {
        let language = context.language
        var result: [String] = []
        let entryIP = context.entryPoint?.publicAddress?.value ?? "<IP>"
        if context.hasMail {
            result.append(L10nGeneration.ptrWarning(language, ip: entryIP, hostname: context.ptrHostname))
            result.append(L10nGeneration.port25Warning(language))
        }
        if context.input.topology == .vpsRelayWithHomeBackend {
            result.append(L10nGeneration.wireGuardPrivateKeysWarning(language))
            result.append(L10nGeneration.fullTunnelWarning(language))
        }
        return result
    }

    private func notes(for context: MailContext) -> [String] {
        let language = context.language
        let postSteps = L10nGeneration.postStepsServices(language)
        let dnsNotes = context.publishesAddressRecords ? [
            context.input.topology == .singleHost
                ? L10nGeneration.noteSingleHostDNS(language) : L10nGeneration.noteSplitDNS(language),
            L10nGeneration.noteDNSImportFiles(language)
        ] : []
        switch context.input.topology {
        case .singleHost:
            return dnsNotes + [
                L10nGeneration.noteSingleHostRun(language),
                postSteps
            ]
        case .vpsRelayWithHomeBackend:
            return dnsNotes + [
                L10nGeneration.noteSplitVPS(language),
                L10nGeneration.noteSplitHome(language),
                postSteps
            ]
        }
    }
}
