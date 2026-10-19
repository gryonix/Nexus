package com.skaymer.gryonixnexus.app.configurator

import com.skaymer.gryonixnexus.catalog.DeploymentScope
import com.skaymer.gryonixnexus.catalog.HomePlacement
import com.skaymer.gryonixnexus.catalog.ServiceID
import com.skaymer.gryonixnexus.catalog.ServiceSettings
import com.skaymer.gryonixnexus.catalog.Topology

/** The per-service answers an install cannot be generated without */
object ServiceQuestions {
    /** One question, and what an answer to it means */
    enum class Question {
        /** Mojang's EULA for the Java edition — refused without it */
        MINECRAFT_JAVA_EULA,

        /** Mojang's EULA for the Bedrock edition — refused without it */
        MINECRAFT_BEDROCK_EULA,

        /** Home-only services on a machine that could be anywhere */
        MACHINE_AT_HOME,
    }

    /** The questions this set of services raises */
    fun raisedBy(
        services: Set<ServiceID>,
        topology: Topology,
        scope: DeploymentScope,
    ): List<Question> = buildList {
        if (ServiceID.MINECRAFT_JAVA in services) add(Question.MINECRAFT_JAVA_EULA)
        if (ServiceID.MINECRAFT_BEDROCK in services) add(Question.MINECRAFT_BEDROCK_EULA)
        if (ServiceID.HOME_ASSISTANT in services && HomePlacement.needsAnswer(topology, scope)) {
            add(Question.MACHINE_AT_HOME)
        }
    }

    fun isAnswered(question: Question, settings: ServiceSettings): Boolean = when (question) {
        Question.MINECRAFT_JAVA_EULA -> settings.minecraftJavaAcceptsEULA
        Question.MINECRAFT_BEDROCK_EULA -> settings.minecraftBedrockAcceptsEULA
        Question.MACHINE_AT_HOME -> settings.machineAtHome
    }

    /** The answer written back */
    fun answering(
        question: Question,
        settings: ServiceSettings,
        accepted: Boolean,
    ): ServiceSettings = when (question) {
        Question.MINECRAFT_JAVA_EULA -> settings.copy(minecraftJavaAcceptsEULA = accepted)
        Question.MINECRAFT_BEDROCK_EULA -> settings.copy(minecraftBedrockAcceptsEULA = accepted)
        Question.MACHINE_AT_HOME -> settings.copy(machineAtHome = accepted)
    }

    /** What still blocks this form */
    fun unanswered(form: ConfiguratorForm): List<Question> =
        raisedBy(form.services, form.topology, form.scope)
            .filterNot { isAnswered(it, form.serviceSettings) }
}
