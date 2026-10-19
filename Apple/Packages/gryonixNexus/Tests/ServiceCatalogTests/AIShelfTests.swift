import XCTest
@testable import ServiceCatalog

private let base = ServiceContext(domain: "example.com", sshUser: "admin")

final class AIShelfTests: XCTestCase {
    // MARK: - Which services a selection actually installs

    func testTheEngineIsImpliedOnlyByTheShelfAndOnlyWhenItIsLocal() {
        let local = ServiceRegistry.expanded([.openWebUI], scope: .publicInternet,
                                             modelBackend: .here)
        XCTAssertTrue(local.contains(.ollama),
                      "a chat with models running here has to get an engine")

        let athome = ServiceRegistry.expanded([.openWebUI], scope: .publicInternet,
                                              modelBackend: .home)
        XCTAssertTrue(athome.contains(.ollama),
                      "the home half runs the same engine — WHICH machine is placement, not catalog")

        let remote = ServiceRegistry.expanded([.openWebUI], scope: .publicInternet,
                                              modelBackend: .external)
        XCTAssertFalse(remote.contains(.ollama),
                       "nothing local was asked for, so nothing local may be installed")

        let unrelated = ServiceRegistry.expanded([.vaultwarden], scope: .publicInternet,
                                                 modelBackend: .here)
        XCTAssertFalse(unrelated.contains(.ollama))
    }

    func testTheEngineAloneImpliesNoChat() {
        let expanded = ServiceRegistry.expanded([.ollama], scope: .publicInternet,
                                                modelBackend: .here)
        XCTAssertEqual(expanded, [.ollama])
    }

    func testTheShelfLeadsWithTheThingAPersonOpens() {
        XCTAssertEqual(ServiceRegistry.services(in: .ai).map(\.id),
                       [.openWebUI, .ollama, .anythingLLM, .liteLLM, .qdrant, .searxng, .openclaw])
    }

    // MARK: - The engine

    /// The API has no authentication of any kind
    func testTheEngineIsNotPublishedAnywhere() {
        let ollama = OllamaService()
        XCTAssertNil(ollama.webIngress(base))
        XCTAssertEqual(ollama.dnsHostnames(base), [])
        XCTAssertEqual(ollama.firewallPorts(base).count, 0)

        let published = ollama.publishedHostPorts(base)
        XCTAssertEqual(published.count, 1)
        XCTAssertEqual(published.first?.address, "127.0.0.1")
        XCTAssertEqual(published.first?.port, OllamaService.apiPort)
    }

    func testInstallingTheEngineFetchesNoModel() {
        let steps = OllamaService().setupSteps(base).joined(separator: "\n")
        for line in steps.split(separator: "\n") {
            XCTAssertFalse(line.contains("docker exec"),
                           "the install must not run the engine's CLI: '\(line)'")
            if line.contains(" pull") {
                XCTAssertTrue(line.contains("docker compose"),
                              "the only pull here is docker's, for the image: '\(line)'")
            }
        }
        XCTAssertFalse(steps.contains("ollama run"),
                       "and must not fetch a model by starting one either")
    }

    func testTheReportSaysTheShelfIsEmptyAndHowToFillIt() {
        let report = OllamaService().reportSteps(base).joined(separator: "\n")
        XCTAssertTrue(report.contains(L10nServices.ollamaNoModelsNote(.en)))
        XCTAssertTrue(report.contains("ollama pull"),
                      "the report is the one place the command belongs")
        XCTAssertTrue(report.contains(L10nServices.ollamaModelSizeNote(.en)),
                      "the size is said where the disk is about to be spent")
    }

    func testTheEngineHasNoBackup() {
        let actions = OllamaService().actions(base)
        XCTAssertNil(actions.backup)
        XCTAssertNil(actions.restore)
    }

    // MARK: - The chat

    func testTheChatIsPublishedUnderTheDefaultNameAndIsGuarded() {
        let ingress = OpenWebUIService().webIngress(base)
        XCTAssertEqual(ingress?.hostname, "ai.example.com")
        XCTAssertEqual(ingress?.upstreamPort, OpenWebUIService.webUIPort)
        XCTAssertTrue(ingress?.adminGuard ?? false,
                      "this page holds every conversation and every uploaded document")
    }

    func testTheChatIsPointedAtTheEngineOnlyWhenTheEngineIsInstalled() throws {
        let chat = OpenWebUIService()

        var withEngine = base
        withEngine.installedServices = [.openWebUI, .ollama]
        let wired = try XCTUnwrap(chat.composeFile(withEngine)).composeContents
        XCTAssertTrue(wired.contains("OLLAMA_BASE_URL"))
        XCTAssertTrue(wired.contains(":\(OllamaService.apiPort)"))
        XCTAssertFalse(chat.reportSteps(withEngine).joined().contains(
            L10nServices.openWebUINoEngineNote(.en)))

        var alone = base
        alone.installedServices = [.openWebUI]
        let bare = try XCTUnwrap(chat.composeFile(alone)).composeContents
        XCTAssertFalse(bare.contains("OLLAMA_BASE_URL"),
                       "a URL pointing at a container that is not there is worse than none")
        XCTAssertTrue(chat.reportSteps(alone).joined().contains(
            L10nServices.openWebUINoEngineNote(.en)),
                      "an empty model list with no explanation reads as a broken install")
    }

    func testRegistrationIsClosedByDefaultAndOpeningItIsExplained() throws {
        XCTAssertFalse(ServiceSettings().openWebUIAllowSignups)
        let shut = try XCTUnwrap(OpenWebUIService().composeFile(base)).composeContents
        XCTAssertTrue(shut.contains(#"ENABLE_SIGNUP: "false""#))

        var open = base
        open.settings.openWebUIAllowSignups = true
        let compose = try XCTUnwrap(OpenWebUIService().composeFile(open)).composeContents
        XCTAssertTrue(compose.contains(#"ENABLE_SIGNUP: "true""#))
        XCTAssertTrue(OpenWebUIService().reportSteps(open).joined()
            .contains(L10nServices.openWebUIAdminWarning(.en)))
    }

    /// The session key signs every login
    func testTheSessionKeyIsServerGenerated() throws {
        let env = try XCTUnwrap(OpenWebUIService().composeFile(base)?.envTemplate)
        XCTAssertEqual(env.trimmingCharacters(in: .whitespacesAndNewlines),
                       "WEBUI_SECRET_KEY=__RANDOM__")
    }

    func testOnlyTheChatHasAHostnameToName() {
        XCTAssertNotNil(ServiceSettings.hostnameSettings[.openWebUI])
        XCTAssertNil(ServiceSettings.hostnameSettings[.ollama])
        XCTAssertFalse(ServiceSettings.fixedHostnameServices.contains(.ollama))
    }

    // MARK: - The gateway

    func testTheGatewayIsImpliedByModelsThatRunSomewhereElse() {
        let remote = ServiceRegistry.expanded([.openWebUI], scope: .publicInternet,
                                              modelBackend: .external)
        XCTAssertTrue(remote.contains(.liteLLM))
        XCTAssertFalse(remote.contains(.ollama))

        let local = ServiceRegistry.expanded([.openWebUI], scope: .publicInternet,
                                             modelBackend: .here)
        XCTAssertFalse(local.contains(.liteLLM),
                       "a local deployment needs no gateway to hold keys it has none of")

        XCTAssertFalse(ServiceRegistry.expanded([.vaultwarden], scope: .publicInternet,
                                                modelBackend: .external)
            .contains(.liteLLM))
    }

    func testTheProviderKeysAreNotInAnythingThisAppWrites() throws {
        var custom = base
        custom.settings.liteLLMPath = "/srv/litellm"
        let compose = try XCTUnwrap(LiteLLMService().composeFile(custom))
        XCTAssertTrue(compose.composeContents.contains(LiteLLMService.keysEnvPath))
        XCTAssertFalse(compose.composeContents.contains("/srv/litellm/keys"))
        XCTAssertNil(compose.envTemplate,
                     "the only value in this service's .env is the shared gateway key")
        for provider in LLMProvider.all {
            XCTAssertFalse(compose.composeContents.contains(provider.environmentKey),
                           "\(provider.id): a provider key is named in a file this app writes")
        }
    }

    func testEveryProviderTheGatewayAcceptsAKeyForIsRouted() {
        let yaml = LiteLLMService().configYAML(base)
        for provider in LLMProvider.all {
            XCTAssertTrue(yaml.contains("model_name: \"\(provider.id)/*\""), provider.id)
            XCTAssertTrue(yaml.contains("os.environ/\(provider.environmentKey)"), provider.id)
        }
    }

    func testTheProviderTableMatchesTheAgentsOwnAllowlist() {
        let agents: [(String, String)] = [
            ("openai", "OPENAI_API_KEY"),
            ("anthropic", "ANTHROPIC_API_KEY"),
            ("deepseek", "DEEPSEEK_API_KEY"),
            ("gemini", "GEMINI_API_KEY"),
            ("groq", "GROQ_API_KEY"),
            ("mistral", "MISTRAL_API_KEY"),
            ("openrouter", "OPENROUTER_API_KEY"),
            ("xai", "XAI_API_KEY")
        ]
        XCTAssertEqual(LLMProvider.all.map { ($0.id, $0.environmentKey) }.map { "\($0.0)=\($0.1)" },
                       agents.map { "\($0.0)=\($0.1)" },
                       "the catalog and Agent/…/install/llm_keys.rs disagree about which "
                       + "providers a key may be stored for — a name here that is not there "
                       + "is a key the agent drops, and one there that is not here is a "
                       + "variable nothing routes")
    }

    func testTheVaultSecretIDNamesTheServiceAndTheProvider() {
        XCTAssertEqual(LLMProvider.provider(id: "openai")?.vaultSecretID, "litellm/openai")
        XCTAssertEqual(LLMProvider.provider(vaultSecretID: "litellm/openai")?.id, "openai")
        XCTAssertNil(LLMProvider.provider(vaultSecretID: "litellm/not-a-provider"))
        XCTAssertNil(LLMProvider.provider(vaultSecretID: "vaultwarden/openai"))
    }

    func testTheGatewayIsPublishedAndTheEngineIsNot() {
        XCTAssertEqual(LiteLLMService().webIngress(base)?.hostname, "ai.example.com")
        XCTAssertTrue(LiteLLMService().webIngress(base)?.adminGuard ?? false)
        XCTAssertNil(OllamaService().webIngress(base))
    }

    func testTheChatPresentsItsOwnKeyAndTheGatewayRegistersIt() throws {
        let chat = OpenWebUIService()
        var withGateway = base
        withGateway.installedServices = [.openWebUI, .liteLLM]

        let compose = try XCTUnwrap(chat.composeFile(withGateway)).composeContents
        XCTAssertTrue(compose.contains("OPENAI_API_BASE_URL"))
        XCTAssertTrue(compose.contains("http://litellm:\(LiteLLMService.containerPort)/v1"))
        XCTAssertTrue(compose.contains("OPENAI_API_KEY: ${LLM_GATEWAY_KEY}"))

        let chatKey = LiteLLMService.appKeyPath(.openWebUI)
        let chatSteps = chat.setupSteps(withGateway).joined(separator: "\n")
        let gatewaySteps = LiteLLMService().setupSteps(withGateway).joined(separator: "\n")
        XCTAssertTrue(chatSteps.contains("LLM_GATEWAY_KEY=$(cat '\(chatKey)')"))
        XCTAssertTrue(gatewaySteps.contains("[ ! -s '\(LiteLLMService.gatewayKeyPath)' ]"),
                      "an existing key must be left alone, not rotated on every run")
        for steps in [chatSteps, gatewaySteps] {
            XCTAssertTrue(steps.contains("[ ! -s '\(chatKey)' ]"))
            XCTAssertTrue(steps.contains("key_alias"))
        }

        // …and a chat with no gateway carries none of it.
        var alone = base
        alone.installedServices = [.openWebUI]
        XCTAssertFalse(try XCTUnwrap(chat.composeFile(alone)).composeContents
            .contains("OPENAI_API_BASE_URL"))
        XCTAssertFalse(chat.setupSteps(alone).joined().contains(LiteLLMService.appKeysDirectory))
        XCTAssertFalse(LiteLLMService().setupSteps(base).joined().contains(chatKey))
    }

    func testTheKeysFileIsCreatedEvenWhenNothingWillFillIt() {
        let steps = LiteLLMService().setupSteps(base).joined(separator: "\n")
        XCTAssertTrue(steps.contains("[ ! -f '\(LiteLLMService.keysEnvPath)' ]"))
        XCTAssertTrue(steps.contains("chmod 600 '\(LiteLLMService.keysEnvPath)'"))
    }

    // MARK: - Storage

    func testModelsAndConversationsLiveApart() {
        let settings = ServiceSettings()
        XCTAssertNotEqual(settings.ollamaPath, settings.openWebUIPath)

        let plan = OpenWebUIService().actions(base).backup
        XCTAssertNotNil(plan, "the conversations have to be backed up")
        let uninstall = OllamaService().uninstallSpec(base)
        XCTAssertEqual(uninstall.configDirectory, settings.ollamaPath,
                       "the models go only under an explicit purge")
    }

    func testDeploymentsStoredBeforeTheShelfKeepDecoding() throws {
        let stored = Data(#"{"domain":"example.com","sshUser":"admin","settings":{}}"#.utf8)
        let context = try JSONDecoder().decode(ServiceContext.self, from: stored)
        XCTAssertEqual(context.settings.modelBackend, .here)
        XCTAssertEqual(context.settings.ollamaPath, ServiceSettings().ollamaPath)
        XCTAssertEqual(ServiceRegistry.expanded([.nextcloud], scope: .publicInternet,
                                                modelBackend: context.settings.modelBackend),
                       [.nextcloud])
    }

    // MARK: - Retrieval: the documents chat and the vector store

    /// The store is a MEMBER, not a companion
    func testTheVectorStoreIsPickedRatherThanImplied() {
        let alone = ServiceRegistry.expanded([.anythingLLM], scope: .publicInternet,
                                             modelBackend: .external)
        XCTAssertFalse(alone.contains(.qdrant),
                       "a store nobody asked for is gigabytes nobody asked for")
        XCTAssertTrue(ServiceRegistry.services(in: .ai).map(\.id).contains(.qdrant),
                      "and it is still selectable, which is what makes it a member")
    }

    func testTheDocumentsChatCountsAsAModelConsumer() {
        XCTAssertTrue(ServiceID.modelConsumers.contains(.anythingLLM))
        let local = ServiceRegistry.expanded([.anythingLLM], scope: .publicInternet,
                                             modelBackend: .here)
        XCTAssertTrue(local.contains(.ollama))
    }

    func testTheVectorStoreIsNotPublishedAnywhere() {
        let qdrant = QdrantService()
        XCTAssertNil(qdrant.webIngress(base))
        XCTAssertTrue(qdrant.dnsHostnames(base).isEmpty)
        XCTAssertNil(ServiceSettings.hostnameSettings[.qdrant],
                     "nothing to name, so the form must not ask")
        let compose = qdrant.composeFile(base)?.composeContents ?? ""
        XCTAssertTrue(compose.contains("\"127.0.0.1:\(QdrantService.apiPort):6333\""))
        XCTAssertFalse(compose.contains("0.0.0.0"))
    }

    func testTheVectorStoreTakesAKeyWhereTheEngineDoesNot() throws {
        let compose = try XCTUnwrap(QdrantService().composeFile(base)).composeContents
        XCTAssertTrue(compose.contains("QDRANT__SERVICE__API_KEY"))
        let engine = try XCTUnwrap(OllamaService().composeFile(base)).composeContents
        XCTAssertFalse(engine.lowercased().contains("api_key"))
    }

    func testTheDocumentsChatDerivesBothOfItsBackends() {
        let docs = AnythingLLMService()

        let withEngine = ServiceContext(domain: "example.com", sshUser: "admin",
                                        installedServices: [.anythingLLM, .ollama])
        XCTAssertEqual(docs.modelSource(withEngine), .engine)
        XCTAssertTrue(docs.seededSettings(withEngine).contains("LLM_PROVIDER='ollama'"))

        let withBoth = ServiceContext(domain: "example.com", sshUser: "admin",
                                      installedServices: [.anythingLLM, .ollama, .liteLLM])
        XCTAssertEqual(docs.modelSource(withBoth), .gateway)
        XCTAssertTrue(docs.seededSettings(withBoth).contains("LLM_PROVIDER='litellm'"))

        let alone = ServiceContext(domain: "example.com", sshUser: "admin",
                                   installedServices: [.anythingLLM])
        XCTAssertNil(docs.modelSource(alone))
        XCTAssertFalse(docs.seededSettings(alone).contains { $0.hasPrefix("LLM_PROVIDER") },
                       "a provider naming a container that is not there is worse than none")
    }

    func testTheVectorStoreIsWiredOnlyWhenItIsInstalled() {
        let docs = AnythingLLMService()
        let withStore = ServiceContext(domain: "example.com", sshUser: "admin",
                                       installedServices: [.anythingLLM, .qdrant])
        XCTAssertTrue(docs.seededSettings(withStore).contains("VECTOR_DB='qdrant'"))
        XCTAssertTrue(docs.seededSettings(withStore)
            .contains { $0.contains("\(QdrantService.apiPort)") })

        let without = ServiceContext(domain: "example.com", sshUser: "admin",
                                     installedServices: [.anythingLLM])
        XCTAssertTrue(docs.seededSettings(without).contains("VECTOR_DB='lancedb'"))
        XCTAssertFalse(docs.seededSettings(without).contains { $0.contains("QDRANT") })
    }

    func testDocumentsCanBeIngestedWithNoModelBackend() {
        let docs = AnythingLLMService()
        let alone = ServiceContext(domain: "example.com", sshUser: "admin",
                                   installedServices: [.anythingLLM])
        XCTAssertTrue(docs.seededSettings(alone).contains("EMBEDDING_ENGINE='native'"))
        let report = docs.reportSteps(alone).joined(separator: "\n")
        XCTAssertTrue(report.contains("ai.example.com"))
    }

    func testNoModelPreferenceIsWritten() {
        let docs = AnythingLLMService()
        let ctx = ServiceContext(domain: "example.com", sshUser: "admin",
                                 installedServices: [.anythingLLM, .ollama])
        XCTAssertFalse(docs.seededSettings(ctx).contains { $0.contains("MODEL_PREF") })
    }

    func testTheComposeFileSetsNothingTheUIOwns() throws {
        let compose = try XCTUnwrap(AnythingLLMService().composeFile(base)).composeContents
        XCTAssertTrue(compose.contains("STORAGE_DIR"))
        XCTAssertTrue(compose.contains("SERVER_PORT"))
        XCTAssertFalse(compose.contains("LLM_PROVIDER"))
        XCTAssertFalse(compose.contains("VECTOR_DB"))
        XCTAssertFalse(compose.contains("EMBEDDING_ENGINE"))
    }

    func testTheSettingsFileIsMountedAndIsNotTheComposeEnv() throws {
        let compose = try XCTUnwrap(AnythingLLMService().composeFile(base))
        XCTAssertNil(compose.envTemplate, "no compose-level .env at all")
        XCTAssertTrue(compose.composeContents.contains("/anythingllm.env:/app/server/.env"))
        XCTAssertFalse(compose.composeContents.contains("/.env:/app/server/.env"))
    }

    func testTheSettingsFileIsSeededOnlyWhenItIsAbsent() {
        let steps = AnythingLLMService().setupSteps(base).joined(separator: "\n")
        XCTAssertTrue(steps.contains("if [ ! -s '/opt/anythingllm/anythingllm.env' ]; then"))
        XCTAssertTrue(steps.contains("chown 1000:1000 '/opt/anythingllm/anythingllm.env'"),
                      "the container has to be able to write its own settings back")
    }

    func testNoCapabilityIsGrantedAndTheBrowserStillRuns() throws {
        let compose = try XCTUnwrap(AnythingLLMService().composeFile(base)).composeContents
        XCTAssertFalse(compose.contains("cap_add"), "no capability is added to this container")
        XCTAssertFalse(compose.contains("privileged"))
        XCTAssertTrue(compose.contains(#"ANYTHINGLLM_CHROMIUM_ARGS: "--no-sandbox""#))
    }

    func testTheStoreKeyIsMintedByWhicheverRunsFirst() {
        let both = ServiceContext(domain: "example.com", sshUser: "admin",
                                  installedServices: [.anythingLLM, .qdrant])
        let fromChat = AnythingLLMService().setupSteps(both).joined(separator: "\n")
        let fromStore = QdrantService().setupSteps(both).joined(separator: "\n")
        for steps in [fromChat, fromStore] {
            XCTAssertTrue(steps.contains("if [ ! -s '\(QdrantService.apiKeyPath)' ]; then"),
                          "both ends mint it, and neither overwrites")
        }
        XCTAssertTrue(fromChat.contains("$(cat '\(QdrantService.apiKeyPath)')"))
    }

    func testTheArchiveTakesTheWholeServiceDirectory() throws {
        let backup = try XCTUnwrap(AnythingLLMService().actions(base).backup)
        guard case .wrapperScript(let spec) = backup, case .archive(let plan) = spec.plan else {
            return XCTFail("AnythingLLM takes an archive backup")
        }
        XCTAssertEqual(plan.dataPath, "/opt/anythingllm")
        XCTAssertTrue(plan.encryptsByDefault)
        XCTAssertEqual(plan.quiesceServices, [AnythingLLMService.container])
    }

    /// Deployments stored before this pair existed must still decode
    func testDeploymentsStoredBeforeTheRetrievalPairKeepDecoding() throws {
        let json = Data(#"{"domain":"example.com"}"#.utf8)
        let settings = try JSONDecoder().decode(ServiceSettings.self, from: json)
        XCTAssertEqual(settings.anythingLLMPath, "/opt/anythingllm")
        XCTAssertEqual(settings.anythingLLMHostname, "")
        XCTAssertEqual(settings.qdrantPath, "/opt/qdrant")
    }

    // MARK: - The search engine

    /// It is called, not opened
    func testTheSearchEngineIsNotPublishedAnywhere() {
        let searxng = SearXNGService()
        XCTAssertNil(searxng.webIngress(base))
        XCTAssertTrue(searxng.dnsHostnames(base).isEmpty)
        XCTAssertNil(ServiceSettings.hostnameSettings[.searxng])
    }

    func testTheSearchEngineIsToldToSpeakJSON() {
        let settings = SearXNGService().settingsFile(base)
        XCTAssertTrue(settings.contains("- json"), "a program cannot read the html format")
        XCTAssertTrue(settings.contains("- html"), "the browser format is not taken away")
    }

    func testTheSearchEnginesSettingsAreOursAndStayShort() {
        let settings = SearXNGService().settingsFile(base)
        XCTAssertTrue(settings.contains("use_default_settings: true"),
                      "without this the file has to carry every default upstream ships")
        XCTAssertLessThan(settings.split(separator: "\n").count, 20,
                          "this file is ours; anything this long is theirs")
    }

    func testTheChatIsGivenTheSearchEngineOnlyWhenItIsThere() {
        var withSearch = base
        withSearch.installedServices = [.openWebUI, .searxng]
        let compose = OpenWebUIService().composeFile(withSearch)?.composeContents ?? ""
        XCTAssertTrue(compose.contains("WEB_SEARCH_ENGINE: \"searxng\""))
        XCTAssertTrue(compose.contains("SEARXNG_QUERY_URL"))
        XCTAssertTrue(compose.contains("<query>"), "their placeholder travels whole")

        var alone = base
        alone.installedServices = [.openWebUI]
        let bare = OpenWebUIService().composeFile(alone)?.composeContents ?? ""
        XCTAssertFalse(bare.contains("SEARXNG_QUERY_URL"),
                       "a chat pointed at a container that is not there is worse than no search")
    }

    // MARK: - The messenger assistant

    func testTheAssistantImpliesAModelBackend() {
        let local = ServiceRegistry.expanded([.openclaw], scope: .publicInternet,
                                             modelBackend: .here)
        XCTAssertTrue(local.contains(.ollama))

        let remote = ServiceRegistry.expanded([.openclaw], scope: .publicInternet,
                                              modelBackend: .external)
        XCTAssertTrue(remote.contains(.liteLLM),
                      "somebody else's models are reached with a key, and the key lives in one place")
    }

    func testTheAssistantIsPublishedUnderTheAdminGuard() {
        let openclaw = OpenClawService()
        let ingress = openclaw.webIngress(base)
        XCTAssertEqual(ingress?.hostname, "ai.example.com")
        XCTAssertEqual(ingress?.adminGuard, true)
        XCTAssertEqual(openclaw.dnsHostnames(base), ["ai.example.com"])
        XCTAssertNotNil(ServiceSettings.hostnameSettings[.openclaw])
    }

    func testThePlainAINameGoesToWhicheverServiceIsAloneOnTheShelf() {
        func hostname(_ service: any ManagedService, with installed: Set<ServiceID>) -> String? {
            service.webIngress(ServiceContext(domain: "example.com", sshUser: "admin",
                                              installedServices: installed))?.hostname
        }
        XCTAssertEqual(hostname(OpenWebUIService(), with: [.openWebUI, .ollama, .qdrant, .searxng]),
                       "ai.example.com")
        let both: Set<ServiceID> = [.openWebUI, .openclaw]
        XCTAssertEqual(hostname(OpenWebUIService(), with: both), "openwebui.example.com")
        XCTAssertEqual(hostname(OpenClawService(), with: both), "openclaw.example.com")
        for service in ServiceRegistry.all {
            XCTAssertNotEqual(hostname(service, with: Set(ServiceRegistry.all.map(\.id))),
                              "agent.example.com")
        }
    }

    /// Neighbours meet on one external network, never the host loopback
    func testEveryAIServiceJoinsTheSharedNetwork() throws {
        var all = base
        all.installedServices = [.ollama, .openWebUI, .liteLLM, .qdrant, .anythingLLM, .openclaw, .searxng]
        let services: [any ManagedService] = [OllamaService(), OpenWebUIService(), LiteLLMService(), QdrantService(),
                                              AnythingLLMService(), OpenClawService(), SearXNGService()]
        for service in services {
            let compose = try XCTUnwrap(service.composeFile(all)).composeContents
            XCTAssertTrue(compose.hasSuffix("networks:\n  gryonixnexus-ai:\n    external: true"), "\(service.id)")
            XCTAssertFalse(compose.contains("host.docker.internal"), "\(service.id)")
            let steps = service.setupSteps(all).joined(separator: "\n")
            let create = try XCTUnwrap(steps.range(of: AIServicesNetwork.createStep), "\(service.id)")
            let up = try XCTUnwrap(steps.range(of: "up -d"), "\(service.id)")
            XCTAssertLessThan(create.lowerBound, up.lowerBound, "\(service.id)")
        }
        XCTAssertEqual(SearXNGService.queryURL, "http://searxng:8080/search?q=<query>")
    }

    /// The chat's database outranks its environment for present neighbours
    func testTheChatForgetsStoredNeighbourAddresses() throws {
        var alone = base
        alone.installedServices = [.openWebUI]
        XCTAssertFalse(OpenWebUIService().setupSteps(alone).joined().contains("webui.db"))

        var all = base
        all.installedServices = [.openWebUI, .ollama, .liteLLM, .searxng]
        let steps = OpenWebUIService().setupSteps(all).joined(separator: "\n")
        XCTAssertTrue(steps.contains("-c '\(OpenWebUIService.forgetKeysScript)' /data/webui.db ollama.base_urls "
                                     + "openai.api_base_urls openai.api_keys web.search.enable web.search.engine "
                                     + "web.search.searxng_query_url || true"))
        let forget = try XCTUnwrap(steps.range(of: "webui.db ollama"))
        let up = try XCTUnwrap(steps.range(of: "up -d"))
        XCTAssertLessThan(forget.lowerBound, up.lowerBound)
    }

    func testTheAssistantReportsTheModelAddressItHas() {
        var withGateway = base
        withGateway.installedServices = [.openclaw, .liteLLM, .ollama]
        XCTAssertEqual(OpenClawService().modelEndpoint(withGateway),
                       "http://litellm:\(LiteLLMService.containerPort)/v1",
                       "the gateway wins: it is the one place the keys live")

        var withEngine = base
        withEngine.installedServices = [.openclaw, .ollama]
        XCTAssertEqual(OpenClawService().modelEndpoint(withEngine),
                       "http://ollama:\(OllamaService.apiPort)")

        var alone = base
        alone.installedServices = [.openclaw]
        XCTAssertNil(OpenClawService().modelEndpoint(alone))
    }

    func testTheAssistantIsGivenTheConfigurationItRefusesToStartWithout() {
        let steps = OpenClawService().setupSteps(base).joined(separator: "\n")
        XCTAssertTrue(steps.contains("if [ ! -s '/opt/openclaw/state/openclaw.json' ]; then"),
                      "a re-install must not overwrite the pairings written back into it")
        XCTAssertTrue(steps.contains("printf '%s\\n' '\(OpenClawService.seededConfig)'"),
                      "the keys the gateway checks, in a file this product wrote")
        XCTAssertTrue(OpenClawService.seededConfig.contains(#""mode":"local""#),
                      "unconfigured, the gateway exits on every start")
        XCTAssertTrue(OpenClawService.seededConfig.contains(#""trustedProxies":["127.0.0.1","::1"]"#))
        XCTAssertTrue(steps.contains("chown 1000:1000 '/opt/openclaw/state/openclaw.json'"),
                      "the container has to be able to write its own settings back")
        XCTAssertFalse(steps.contains("--allow-unconfigured"),
                       "upstream's own help says that flag does not repair the config")
    }

    /// A home client must not look like one more proxy
    func testTheAssistantTrustsOnlyTheNetworkGateway() throws {
        let steps = OpenClawService().setupSteps(base).joined(separator: "\n")
        XCTAssertFalse(steps.contains("192.168.0.0/16"))
        let trust = try XCTUnwrap(steps.range(of: #"'.gateway.trustedProxies = ["127.0.0.1", "::1", $g]'"#))
        let network = try XCTUnwrap(steps.range(of: AIServicesNetwork.createStep))
        let chown = try XCTUnwrap(steps.range(of: "chown 1000:1000"))
        let up = try XCTUnwrap(steps.range(of: "up -d"))
        XCTAssertLessThan(network.lowerBound, trust.lowerBound)
        XCTAssertLessThan(trust.lowerBound, chown.lowerBound)
        XCTAssertLessThan(chown.lowerBound, up.lowerBound)
    }

    func testTheAssistantsSiteOverwritesTheForwardedClientHeader() throws {
        let ingress = try XCTUnwrap(OpenClawService().webIngress(base))
        XCTAssertTrue(ingress.overwriteForwardedFor)
        for service in [AnythingLLMService() as any ManagedService, OpenWebUIService(),
                        LiteLLMService(), N8NService()] {
            XCTAssertEqual(service.webIngress(base)?.overwriteForwardedFor, false,
                           "\(service.id.rawValue) does not read forwarded headers")
        }
    }

    func testTheAssistantHoldsNobodysMessengerToken() {
        var context = base
        context.installedServices = [.openclaw, .liteLLM]
        let compose = OpenClawService().composeFile(context)?.composeContents ?? ""
        for token in ["TELEGRAM", "DISCORD", "WHATSAPP", "BOT_TOKEN"] {
            XCTAssertFalse(compose.contains(token),
                           "\(token) belongs to the person, in their own UI")
        }
        XCTAssertTrue(compose.contains("OPENCLAW_GATEWAY_TOKEN"),
                      "the one secret here is the one guarding the gateway itself")
    }

    // MARK: - The graphics card

    func testTheInstallNeverPutsAKernelDriverOnTheHost() {
        var context = base
        context.settings.ollamaUsesGPU = true
        let script = OllamaService().setupSteps(context).joined(separator: "\n")
        for forbidden in ["nvidia-driver", "dkms", "linux-headers",
                          "systemctl reboot", "shutdown -r"] {
            XCTAssertFalse(script.contains(forbidden), "\(forbidden) is a decision about the host")
        }
        XCTAssertTrue(script.contains("nvidia-container-toolkit"))
    }

    func testTheToolkitIsGatedOnADriverAndOnDockerNotKnowingItYet() {
        var context = base
        context.settings.ollamaUsesGPU = true
        let script = OllamaService().setupSteps(context).joined(separator: "\n")
        XCTAssertTrue(script.contains("nvidia-smi -L"))
        XCTAssertTrue(script.contains("docker info"))
        guard let restart = script.range(of: "systemctl restart docker"),
              let gate = script.range(of: "docker info") else {
            return XCTFail("both the gate and the restart have to be in the script")
        }
        XCTAssertTrue(gate.lowerBound < restart.lowerBound,
                      "the restart belongs inside the branch that just configured the runtime")
    }

    func testTheCardIsRequestedInAnOverrideRatherThanTheComposeFile() {
        var context = base
        context.settings.ollamaUsesGPU = true
        let compose = OllamaService().composeFile(context)?.composeContents ?? ""
        XCTAssertFalse(compose.contains("nvidia"), "the compose file must start on any host")

        let script = OllamaService().setupSteps(context).joined(separator: "\n")
        XCTAssertTrue(script.contains("docker-compose.override.yml"))
        XCTAssertTrue(OllamaService.gpuOverrideContents.contains("driver: nvidia"))
    }

    func testTurningTheCardOffTakesTheOverrideAway() {
        let script = OllamaService().setupSteps(base).joined(separator: "\n")
        XCTAssertTrue(script.contains("rm -f \(OllamaService.gpuOverridePath(base))"))
        XCTAssertFalse(script.contains("nvidia"))
        XCTAssertTrue(OllamaService().reportSteps(base).joined().isEmpty == false)
        XCTAssertFalse(OllamaService().reportSteps(base).joined().contains("NVIDIA"))
    }

    func testTheReportSaysWhatHappenedRatherThanWhatWasAsked() {
        var context = base
        context.settings.ollamaUsesGPU = true
        let report = OllamaService().reportSteps(context).joined(separator: "\n")
        XCTAssertTrue(report.contains("if [ -f \(OllamaService.gpuOverridePath(context)) ]"))
        XCTAssertTrue(report.contains("else"))
    }
}
