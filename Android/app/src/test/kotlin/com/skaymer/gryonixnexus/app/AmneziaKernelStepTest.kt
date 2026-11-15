package com.skaymer.gryonixnexus.app

import com.skaymer.gryonixnexus.app.ui.kernelStep
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test

/** The step line reads the agent's "3/4" */
class AmneziaKernelStepTest {
    @Test
    fun aCountBecomesAStep() {
        assertEquals(3 to 4, kernelStep("3/4"))
    }

    @Test
    fun anythingElseShowsNoStep() {
        for (note in listOf("", "4", "0/4", "5/4", "a/b", "1/2/3", "less than 1 GB free on the disk")) {
            assertNull(kernelStep(note), note)
        }
    }
}
