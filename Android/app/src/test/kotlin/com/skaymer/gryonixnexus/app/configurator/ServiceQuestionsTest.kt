package com.skaymer.gryonixnexus.app.configurator

import com.skaymer.gryonixnexus.catalog.DeploymentScope
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.Topology
import com.skaymer.gryonixnexus.catalog.ServiceSettings
import com.skaymer.gryonixnexus.recipe.MailInputValidator
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class ServiceQuestionsTest {
    private fun form(
        services: Set<ServiceID>,
        settings: ServiceSettings = ServiceSettings(),
        scope: DeploymentScope = DeploymentScope.PUBLIC_INTERNET,
    ) = ConfiguratorForm(
        domain = "example.com",
        publicIP = "203.0.113.10",
        scope = scope,
        services = services,
        serviceSettings = settings,
    )

    private fun raised(services: Set<ServiceID>) =
        ServiceQuestions.raisedBy(services, Topology.SINGLE_HOST, DeploymentScope.PUBLIC_INTERNET)

    private fun refusal(form: ConfiguratorForm): String? =
        runCatching { MailInputValidator().validate(form.toInput()) }
            .exceptionOrNull()?.message

    /** The answers written the way the WIZARD writes them */
    private fun accepting(vararg questions: ServiceQuestions.Question): ServiceSettings =
        questions.fold(ServiceSettings()) { settings, question ->
            ServiceQuestions.answering(question, settings, accepted = true)
        }

    @Test
    fun `a game server is refused until its license is accepted, and accepted after`() {
        val unanswered = form(setOf(ServiceID.MINECRAFT_JAVA))
        assertNotNull(
            refusal(unanswered),
            "the catalog used to refuse this and the app had nowhere to answer it",
        )
        assertTrue(
            refusal(unanswered)!!.contains("License"),
            "the refusal this pins is the license one, not some other invalid field: " +
                refusal(unanswered),
        )

        val answered = form(
            setOf(ServiceID.MINECRAFT_JAVA),
            accepting(ServiceQuestions.Question.MINECRAFT_JAVA_EULA),
        )
        assertNull(
            refusal(answered),
            "answering the question the wizard now asks must let the install through",
        )
    }

    @Test
    fun `each edition is answered separately`() {
        val bedrock = form(setOf(ServiceID.MINECRAFT_BEDROCK))
        assertNotNull(refusal(bedrock))
        assertNull(
            refusal(
                form(
                    setOf(ServiceID.MINECRAFT_BEDROCK),
                    accepting(ServiceQuestions.Question.MINECRAFT_BEDROCK_EULA),
                ),
            ),
            "answering Bedrock's question through the wizard's own writer must let it through",
        )
        assertNotNull(
            refusal(
                form(
                    setOf(ServiceID.MINECRAFT_JAVA, ServiceID.MINECRAFT_BEDROCK),
                    accepting(ServiceQuestions.Question.MINECRAFT_JAVA_EULA),
                ),
            ),
            "accepting the Java license must not stand in for the Bedrock one",
        )
        assertNotNull(
            refusal(
                form(
                    setOf(ServiceID.MINECRAFT_JAVA, ServiceID.MINECRAFT_BEDROCK),
                    accepting(ServiceQuestions.Question.MINECRAFT_BEDROCK_EULA),
                ),
            ),
            "accepting the Bedrock license must not stand in for the Java one",
        )
    }

    @Test
    fun `the questions raised are exactly the ones the catalog will refuse over`() {
        assertEquals(
            listOf(ServiceQuestions.Question.MINECRAFT_JAVA_EULA),
            raised(setOf(ServiceID.MINECRAFT_JAVA)),
        )
        assertEquals(
            emptyList<ServiceQuestions.Question>(),
            raised(setOf(ServiceID.NEXTCLOUD, ServiceID.VAULTWARDEN)),
            "a deployment with no game server must not be asked anything",
        )
        assertEquals(
            emptyList<ServiceQuestions.Question>(),
            ServiceQuestions.unanswered(
                form(
                    setOf(ServiceID.MINECRAFT_JAVA),
                    accepting(ServiceQuestions.Question.MINECRAFT_JAVA_EULA),
                ),
            ),
            "an answered question no longer blocks",
        )
    }

    @Test
    fun `the wizard's gate agrees with the catalog on every combination`() {
        val editions = listOf(ServiceID.MINECRAFT_JAVA, ServiceID.MINECRAFT_BEDROCK)
        for (chosen in listOf(emptySet(), setOf(editions[0]), setOf(editions[1]), editions.toSet())) {
            for (java in listOf(false, true)) {
                for (bedrock in listOf(false, true)) {
                    val settings = buildList {
                        if (java) add(ServiceQuestions.Question.MINECRAFT_JAVA_EULA)
                        if (bedrock) add(ServiceQuestions.Question.MINECRAFT_BEDROCK_EULA)
                    }.let { accepting(*it.toTypedArray()) }
                    val blocked = ServiceQuestions.unanswered(form(chosen, settings)).isNotEmpty()
                    val refused = refusal(form(chosen, settings)) != null
                    assertEquals(
                        blocked, refused,
                        "chosen=$chosen java=$java bedrock=$bedrock: the wizard and the " +
                            "catalog disagree about whether this install may go",
                    )
                }
            }
        }
    }

    @Test
    fun `the hub asks only where the machine could be anywhere, and the gate agrees`() {
        val hub = setOf(ServiceID.HOME_ASSISTANT)
        val scopes = listOf(
            DeploymentScope.PUBLIC_INTERNET, DeploymentScope.CLOUDFLARE_TUNNEL,
            DeploymentScope.MESH_ONLY, DeploymentScope.DYNAMIC_DNS,
        )
        for (scope in scopes) {
            for (atHome in listOf(false, true)) {
                val chosen = form(hub, ServiceSettings(machineAtHome = atHome), scope)
                val blocked = ServiceQuestions.unanswered(chosen).isNotEmpty()
                val refused = refusal(chosen) != null
                assertEquals(blocked, refused, "scope=$scope atHome=$atHome: ${refusal(chosen)}")
            }
        }
        assertEquals(
            emptyList<ServiceQuestions.Question>(),
            ServiceQuestions.raisedBy(hub, Topology.VPS_RELAY_WITH_HOME_BACKEND,
                DeploymentScope.PUBLIC_INTERNET),
            "scenario B installs on the home machine and asks nothing",
        )
    }
}
