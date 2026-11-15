package com.skaymer.gryonixnexus.app.notify

import com.skaymer.gryonixnexus.agentclient.AgentError
import org.junit.jupiter.api.Test
import kotlin.test.assertEquals

class StopRefusalTextTest {
    @Test
    fun aStepThatCannotStopIsToldApart() {
        val refusal = AgentError.Rpc("failed_precondition", "this run cannot be stopped once it has started")
        assertEquals(StopRefusalText.Reason.CannotStop, StopRefusalText.reason(refusal))
    }

    @Test
    fun otherFailuresCarryTheirText() {
        val lost = AgentError.Transport("connection reset")
        assertEquals(StopRefusalText.Reason.Failed("connection reset"), StopRefusalText.reason(lost))
    }

    @Test
    fun aMissingRunKeepsItsOwnReason() {
        val miss = StopMiss(StopRefusalText.Reason.NothingRunning)
        assertEquals(StopRefusalText.Reason.NothingRunning, StopRefusalText.reason(miss))
    }
}
