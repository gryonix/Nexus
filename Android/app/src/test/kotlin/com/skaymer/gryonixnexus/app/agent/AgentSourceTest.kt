package com.skaymer.gryonixnexus.app.agent

import org.junit.jupiter.api.Test
import kotlin.test.assertEquals

class AgentSourceTest {
    @Test
    fun mainBetaAndWipAreRead() {
        assertEquals(listOf("main", "beta", "wip"), AgentSource.entries.mapNotNull { it.branch })
    }

    @Test
    fun aStoredChoiceIsReadBackAndAnythingElseIsTheApp() {
        assertEquals(AgentSource.REPOSITORY_WIP, AgentSource.named("repositoryWip"))
        assertEquals(AgentSource.APP, AgentSource.named("../../etc"))
        assertEquals(AgentSource.APP, AgentSource.named(null))
    }
}
