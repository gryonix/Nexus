package com.skaymer.gryonixnexus.app.agent

import com.skaymer.gryonixnexus.agentclient.AgentError
import com.skaymer.gryonixnexus.app.servers.WrapperLogText
import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class AgentOutdatedTests {
    @Test
    fun anOldAgentsDiskReplyAsksForAnUpdate() {
        assertTrue(AgentOutdated.matches(AgentError.Rpc("invalid_argument", "choose a disk task")))
        assertFalse(AgentOutdated.matches(AgentError.Rpc("failed_precondition", "the disk is mounted")))
    }

    @Test
    fun anAgentErrorReadsAsItsOwnMessage() {
        assertEquals("the disk is mounted", AgentError.Rpc("failed_precondition", "the disk is mounted").message)
    }

    @Test
    fun knownWrapperLinesBecomeStagesAndOthersDoNot() {
        assertEquals(WrapperLogText.Stage.BACKUP, WrapperLogText.stage("backing up nextcloud before updating it"))
        assertEquals(WrapperLogText.Stage.WAITING, WrapperLogText.stage("waiting for immich: server"))
        assertNull(WrapperLogText.stage("Pulling fs layer"))
    }

    @Test
    fun aStageOutlivesTheLinesAfterIt() {
        val job = RunningJob(id = "j", deploymentID = "d", title = "t")
            .withLine("backing up nextcloud before updating it")
            .withLine("Pulling fs layer")
        assertEquals(WrapperLogText.Stage.BACKUP, job.stage)
        assertEquals("Pulling fs layer", job.line)
    }
}
