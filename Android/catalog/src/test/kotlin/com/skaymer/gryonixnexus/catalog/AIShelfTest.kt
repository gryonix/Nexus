package com.skaymer.gryonixnexus.catalog

import com.skaymer.gryonixnexus.catalog.services.LiteLLMService
import com.skaymer.gryonixnexus.catalog.services.OllamaService
import com.skaymer.gryonixnexus.catalog.services.OpenClawService
import com.skaymer.gryonixnexus.catalog.services.OpenWebUIService
import com.skaymer.gryonixnexus.catalog.services.SearXNGService
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class AIShelfTest {
    private fun context(installed: Set<ServiceID>) = ServiceContext(
        domain = "example.com",
        sshUser = "admin",
        settings = ServiceSettings(),
        installedServices = installed
    )

    @Test
    fun `the engine is implied only by the shelf and only when it is local`() {
        val local = ServiceRegistry.expanded(
            setOf(ServiceID.OPEN_WEB_UI), DeploymentScope.PUBLIC_INTERNET, ModelBackend.HERE
        )
        assertTrue(ServiceID.OLLAMA in local)

        val athome = ServiceRegistry.expanded(
            setOf(ServiceID.OPEN_WEB_UI), DeploymentScope.PUBLIC_INTERNET, ModelBackend.HOME
        )
        assertTrue(ServiceID.OLLAMA in athome)

        val remote = ServiceRegistry.expanded(
            setOf(ServiceID.OPEN_WEB_UI), DeploymentScope.PUBLIC_INTERNET, ModelBackend.EXTERNAL
        )
        assertFalse(ServiceID.OLLAMA in remote)

        val unrelated = ServiceRegistry.expanded(
            setOf(ServiceID.VAULTWARDEN), DeploymentScope.PUBLIC_INTERNET, ModelBackend.HERE
        )
        assertFalse(ServiceID.OLLAMA in unrelated)
    }

    /** Switching the shelf on installs its FIRST member */
    @Test
    fun `the shelf leads with the thing a person opens`() {
        assertEquals(
            listOf(
                ServiceID.OPEN_WEB_UI, ServiceID.OLLAMA, ServiceID.ANYTHING_LLM,
                ServiceID.LITE_LLM, ServiceID.QDRANT,
                ServiceID.SEARXNG, ServiceID.OPENCLAW,
            ),
            ServiceRegistry.services(ServiceCategory.AI).map { it.id }
        )
    }

    @Test
    fun `the gateway is implied by models that run somewhere else`() {
        val remote = ServiceRegistry.expanded(
            setOf(ServiceID.OPEN_WEB_UI), DeploymentScope.PUBLIC_INTERNET, ModelBackend.EXTERNAL
        )
        assertTrue(ServiceID.LITE_LLM in remote)
        assertFalse(ServiceID.OLLAMA in remote)

        val local = ServiceRegistry.expanded(
            setOf(ServiceID.OPEN_WEB_UI), DeploymentScope.PUBLIC_INTERNET, ModelBackend.HERE
        )
        assertFalse(ServiceID.LITE_LLM in local)

        assertFalse(
            ServiceID.LITE_LLM in ServiceRegistry.expanded(
                setOf(ServiceID.VAULTWARDEN), DeploymentScope.PUBLIC_INTERNET, ModelBackend.EXTERNAL
            )
        )
    }

    @Test
    fun `the provider keys are not in anything this app writes`() {
        val custom = ServiceContext(
            domain = "example.com",
            sshUser = "admin",
            settings = ServiceSettings(liteLLMPath = "/srv/litellm"),
            installedServices = setOf(ServiceID.LITE_LLM),
        )
        val compose = LiteLLMService().composeFile(custom)!!
        assertTrue(compose.composeContents.contains(LiteLLMService.KEYS_ENV_PATH))
        assertFalse(compose.composeContents.contains("/srv/litellm/keys"))
        assertNull(compose.envTemplate)
        for (provider in LLMProvider.ALL) {
            assertFalse(
                compose.composeContents.contains(provider.environmentKey),
                "${provider.id}: a provider key is named in a file this app writes",
            )
        }
    }

    @Test
    fun `the provider table matches the agents own allowlist`() {
        val agents = listOf(
            "openai=OPENAI_API_KEY",
            "anthropic=ANTHROPIC_API_KEY",
            "deepseek=DEEPSEEK_API_KEY",
            "gemini=GEMINI_API_KEY",
            "groq=GROQ_API_KEY",
            "mistral=MISTRAL_API_KEY",
            "openrouter=OPENROUTER_API_KEY",
            "xai=XAI_API_KEY",
        )
        assertEquals(agents, LLMProvider.ALL.map { "${it.id}=${it.environmentKey}" })
    }

    @Test
    fun `the chat presents its own key and the gateway registers it`() {
        val chat = OpenWebUIService()
        val withGateway = context(setOf(ServiceID.OPEN_WEB_UI, ServiceID.LITE_LLM))

        val compose = chat.composeFile(withGateway)!!.composeContents
        assertTrue(compose.contains("OPENAI_API_BASE_URL"))
        assertTrue(compose.contains("http://litellm:${LiteLLMService.CONTAINER_PORT}/v1"))
        assertTrue(compose.contains("OPENAI_API_KEY: \${LLM_GATEWAY_KEY}"))
        assertTrue(compose.contains("\n      OPENAI_API_KEY: \${LLM_GATEWAY_KEY}\n    volumes:"))

        val chatKey = LiteLLMService.appKeyPath(ServiceID.OPEN_WEB_UI)
        val chatSteps = chat.setupSteps(withGateway).joinToString("\n")
        val gatewaySteps = LiteLLMService().setupSteps(withGateway).joinToString("\n")
        assertTrue(chatSteps.contains("LLM_GATEWAY_KEY=\$(cat '$chatKey')"))
        assertTrue(
            gatewaySteps.contains("[ ! -s '${LiteLLMService.GATEWAY_KEY_PATH}' ]"),
            "an existing key must be left alone, not rotated on every run",
        )
        for (steps in listOf(chatSteps, gatewaySteps)) {
            assertTrue(steps.contains("[ ! -s '$chatKey' ]"))
            assertTrue(steps.contains("key_alias"))
        }

        val alone = context(setOf(ServiceID.OPEN_WEB_UI))
        assertFalse(chat.composeFile(alone)!!.composeContents.contains("OPENAI_API_BASE_URL"))
        assertFalse(
            chat.setupSteps(alone).joinToString("\n").contains(LiteLLMService.APP_KEYS_DIRECTORY)
        )
    }

    @Test
    fun `the chat is pointed at the engine only when the engine is installed`() {
        val chat = OpenWebUIService()

        val wired = chat.composeFile(context(setOf(ServiceID.OPEN_WEB_UI, ServiceID.OLLAMA)))!!.composeContents
        assertTrue(wired.contains("OLLAMA_BASE_URL"))
        assertTrue(wired.contains("${OllamaService.API_PORT}"))

        val alone = chat.composeFile(context(setOf(ServiceID.OPEN_WEB_UI)))!!.composeContents
        assertFalse(alone.contains("OLLAMA_BASE_URL"))
        assertTrue(alone.contains("\n      ENABLE_SIGNUP: \"false\"\n    volumes:"))
        assertTrue(
            chat.reportSteps(context(setOf(ServiceID.OPEN_WEB_UI)))
                .joinToString("\n")
                .contains(L10nServices.openWebUINoEngineNote(AppLanguage.EN))
        )
    }

    @Test
    fun `installing the engine fetches no model`() {
        val steps = OllamaService().setupSteps(context(setOf(ServiceID.OLLAMA))).joinToString("\n")
        for (line in steps.lines()) {
            assertFalse(line.contains("docker exec"), "the install must not run the engine's CLI: $line")
            if (line.contains(" pull")) {
                assertTrue(line.contains("docker compose"), "the only pull here is docker's: $line")
            }
        }
        assertFalse(steps.contains("ollama run"))
    }

    /** An unauthenticated model API has no business on a hostname */
    @Test
    fun `the engine is not published anywhere`() {
        val ollama = OllamaService()
        val ctx = context(setOf(ServiceID.OLLAMA))
        assertNull(ollama.webIngress(ctx))
        assertTrue(ollama.dnsHostnames(ctx).isEmpty())
        assertTrue(ollama.firewallPorts(ctx).isEmpty())
        assertNull(ServiceHostnames.settings[ServiceID.OLLAMA])
    }

    @Test
    fun `the search engine is not published anywhere`() {
        val searxng = SearXNGService()
        val ctx = context(setOf(ServiceID.SEARXNG))
        assertNull(searxng.webIngress(ctx))
        assertTrue(searxng.dnsHostnames(ctx).isEmpty())
        assertNull(ServiceHostnames.settings[ServiceID.SEARXNG])
    }

    /** The license test */
    @Test
    fun `the search engine settings are ours and stay short`() {
        val settings = SearXNGService().settingsFile(context(setOf(ServiceID.SEARXNG)))
        assertTrue(settings.contains("use_default_settings: true"))
        assertTrue(settings.contains("- json"), "a program cannot read the html format")
        assertTrue(settings.lines().size < 20, "this file is ours; anything this long is theirs")
    }

    @Test
    fun `the chat is given the search engine only when it is there`() {
        val withSearch = OpenWebUIService()
            .composeFile(context(setOf(ServiceID.OPEN_WEB_UI, ServiceID.SEARXNG)))
            .composeContents
        assertTrue(withSearch.contains("WEB_SEARCH_ENGINE: \"searxng\""))
        assertTrue(withSearch.contains("<query>"), "their placeholder travels whole")

        val alone = OpenWebUIService()
            .composeFile(context(setOf(ServiceID.OPEN_WEB_UI)))
            .composeContents
        assertFalse(alone.contains("SEARXNG_QUERY_URL"))
    }

    @Test
    fun `the assistant implies a model backend`() {
        val local = ServiceRegistry.expanded(
            setOf(ServiceID.OPENCLAW), DeploymentScope.PUBLIC_INTERNET, ModelBackend.HERE
        )
        assertTrue(ServiceID.OLLAMA in local)

        val remote = ServiceRegistry.expanded(
            setOf(ServiceID.OPENCLAW), DeploymentScope.PUBLIC_INTERNET, ModelBackend.EXTERNAL
        )
        assertTrue(ServiceID.LITE_LLM in remote)
    }

    /** Neighbours meet on one external network, never the host loopback */
    @Test
    fun `every AI service joins the shared network`() {
        val all = context(
            setOf(
                ServiceID.OLLAMA, ServiceID.OPEN_WEB_UI, ServiceID.LITE_LLM, ServiceID.QDRANT,
                ServiceID.ANYTHING_LLM, ServiceID.OPENCLAW, ServiceID.SEARXNG,
            )
        )
        for (service in ServiceRegistry.services(ServiceCategory.AI)) {
            val compose = service.composeFile(all)!!.composeContents
            assertTrue(compose.endsWith("networks:\n  gryonixnexus-ai:\n    external: true"), "${service.id}")
            assertFalse(compose.contains("host.docker.internal"), "${service.id}")
            val steps = service.setupSteps(all).joinToString("\n")
            val create = steps.indexOf(AIServicesNetwork.CREATE_STEP)
            assertTrue(create in 0 until steps.indexOf("up -d"), "${service.id}")
        }
        assertEquals("http://searxng:8080/search?q=<query>", SearXNGService.QUERY_URL)
    }

    /** The chat's database outranks its environment for present neighbours */
    @Test
    fun `the chat forgets stored neighbour addresses`() {
        val chat = OpenWebUIService()
        assertFalse(chat.setupSteps(context(setOf(ServiceID.OPEN_WEB_UI))).joinToString().contains("webui.db"))

        val all = context(setOf(ServiceID.OPEN_WEB_UI, ServiceID.OLLAMA, ServiceID.LITE_LLM, ServiceID.SEARXNG))
        val steps = chat.setupSteps(all).joinToString("\n")
        assertTrue(
            steps.contains(
                "-c '${OpenWebUIService.FORGET_KEYS_SCRIPT}' /data/webui.db ollama.base_urls " +
                    "openai.api_base_urls openai.api_keys web.search.enable web.search.engine " +
                    "web.search.searxng_query_url || true"
            )
        )
        assertTrue(steps.indexOf("webui.db ollama") < steps.indexOf("up -d"))
    }

    @Test
    fun `the assistant reports the model address it has`() {
        val openclaw = OpenClawService()
        assertEquals(
            "http://litellm:${LiteLLMService.CONTAINER_PORT}/v1",
            openclaw.modelEndpoint(
                context(setOf(ServiceID.OPENCLAW, ServiceID.LITE_LLM, ServiceID.OLLAMA))
            ),
            "the gateway wins: it is the one place the keys live"
        )
        assertEquals(
            "http://ollama:${OllamaService.API_PORT}",
            openclaw.modelEndpoint(context(setOf(ServiceID.OPENCLAW, ServiceID.OLLAMA)))
        )
        assertNull(openclaw.modelEndpoint(context(setOf(ServiceID.OPENCLAW))))
    }

    @Test
    fun `the assistant is given the configuration it refuses to start without`() {
        val steps = OpenClawService()
            .setupSteps(context(setOf(ServiceID.OPENCLAW))).joinToString("\n")
        assertTrue(
            steps.contains("if [ ! -s '/opt/openclaw/state/openclaw.json' ]; then"),
            "a re-install must not overwrite the pairings written back into it"
        )
        assertTrue(
            steps.contains(
                """printf '%s\n' '{"gateway":{"mode":"local","trustedProxies":["127.0.0.1","::1"]}}'"""
            ),
            "the one key the gateway checks, in a file this product wrote"
        )
        assertTrue(
            steps.contains("chown 1000:1000 '/opt/openclaw/state/openclaw.json'"),
            "the container has to be able to write its own settings back"
        )
        assertFalse(
            steps.contains("--allow-unconfigured"),
            "upstream's own help says that flag does not repair the config"
        )
    }

    /** A home client must not look like one more proxy */
    @Test
    fun `the assistant trusts only the network gateway`() {
        val steps = OpenClawService().setupSteps(context(setOf(ServiceID.OPENCLAW))).joinToString("\n")
        assertFalse(steps.contains("192.168.0.0/16"))
        val trust = steps.indexOf("""'.gateway.trustedProxies = ["127.0.0.1", "::1", ${'$'}g]'""")
        val network = steps.indexOf(AIServicesNetwork.CREATE_STEP)
        val chown = steps.indexOf("chown 1000:1000")
        assertTrue(network in 0 until trust)
        assertTrue(trust < chown && chown < steps.indexOf("up -d"))
    }

    @Test
    fun `the assistants site overwrites the forwarded client header`() {
        val ingress = OpenClawService().webIngress(context(setOf(ServiceID.OPENCLAW)))
        assertTrue(ingress.overwriteForwardedFor)
        assertTrue(OpenClawService.SEEDED_CONFIG.contains(""""trustedProxies""""))
    }

    @Test
    fun `the assistant holds nobodys messenger token`() {
        val compose = OpenClawService()
            .composeFile(context(setOf(ServiceID.OPENCLAW, ServiceID.LITE_LLM)))
            .composeContents
        for (token in listOf("TELEGRAM", "DISCORD", "WHATSAPP", "BOT_TOKEN")) {
            assertFalse(compose.contains(token), "$token belongs to the person, in their own UI")
        }
        assertTrue(compose.contains("OPENCLAW_GATEWAY_TOKEN"))
    }
}
