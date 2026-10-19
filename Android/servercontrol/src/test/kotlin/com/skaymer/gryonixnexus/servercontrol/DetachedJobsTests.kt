package com.skaymer.gryonixnexus.servercontrol

import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

class DetachedJobsTests {
    @Test
    fun theLaunchDetachesAndLeavesASentinel() {
        val command = DetachedJobs.startCommand(
            "/opt/gryonixnexus-update-ctl.sh run nextcloud", "update-nextcloud-1000")
        assertTrue(command.contains("setsid"), "without this sshd hangs the run up with the channel")
        assertTrue(command.contains(DetachedJobs.EXIT_MARKER),
            "without the sentinel, 'ended' cannot be told from 'disconnected'")
        assertTrue(command.contains("umask 077"))
        assertTrue(command.indexOf(": > ") < command.indexOf("\$DETACH sh -c"),
            "the log must exist before the run does")
    }

    @Test
    fun aSecretGoesToAFileTheRunDeletesBeforeItWorks() {
        val command = DetachedJobs.startCommandWithSecret(
            "sudo /opt/gryonixnexus-backup-ctl.sh backup vpn --encrypt", "backup-vpn-2000")
        assertTrue(command.contains("cat > ") && command.contains(".pass"))
        assertTrue(command.indexOf("rm -f ") < command.indexOf("gryonixnexus-backup-ctl.sh"),
            "removed as the pipe is built, not after the backup has run")
    }

    @Test
    fun theFollowerResumesAndTerminates() {
        val command = DetachedJobs.followCommand("backup-immich-2000", 41)
        assertTrue(command.contains("n=41"), "a client that saw 40 lines asks for the 41st")
        assertTrue(command.contains("exit 0"))
        assertFalse(command.contains("tail -f"), "tail -f deadlocks here — see SetupInstaller")
    }

    @Test
    fun theListingTellsRunningFromFinished() {
        val jobs = DetachedJobs.parseList(
            "update-nextcloud-1700 0\nbackup-immich-1800 -\nuninstall-pihole-1600 3")
        assertEquals(listOf("backup-immich-1800", "update-nextcloud-1700", "uninstall-pihole-1600"),
            jobs.map { it.id }, "newest first")
        assertTrue(jobs[0].isRunning, "no sentinel yet means it is still going")
        assertEquals(0, jobs[1].exitCode)
        assertEquals(3, jobs[2].exitCode, "a failure keeps its code, which says what happened")
    }

    @Test
    fun aSubjectWithDashesComesBackWhole() {
        val id = DetachedJobs.jobID(DetachedJobs.Kind.BACKUP, "adguard-home", 1234)
        assertEquals("backup-adguard-home-1234", id)
        val job = DetachedJobs.parseList("$id -").single()
        assertEquals("adguard-home", job.subject)
        assertEquals(DetachedJobs.Kind.BACKUP, job.kind)
    }

    @Test
    fun aLineThatIsNotAJobIsSkipped() {
        assertTrue(DetachedJobs.parseList("notes.txt 0\nrubbish\n").isEmpty())
        assertTrue(DetachedJobs.parseList("install-x-1 0").isEmpty(),
            "a kind this app does not know is not a kind it may invent")
    }

    @Test
    fun theShellMatchesWhatTheAppleSideSends() {
        val launch = DetachedJobs.startCommand("sudo /opt/x.sh run", "update-x-7")
        assertEquals(
            "umask 077; mkdir -p '.gryonixnexus/jobs' || exit 1; exec 9> '.gryonixnexus/jobs/x.lock'; " +
                "flock -n 9 || { echo 'An operation is already running for this service. Wait for it to finish.' >&2; exit 75; }; " +
                ": > '.gryonixnexus/jobs/update-x-7.log' || exit 1; " +
                "command -v setsid >/dev/null 2>&1 && DETACH=setsid || DETACH=; " +
                "\$DETACH sh -c 'sudo /opt/x.sh run >> '\\''.gryonixnexus/jobs/update-x-7.log'\\'' 2>&1; " +
                "echo \"GRYONIXNEXUS_JOB_EXIT:\$?\" >> '\\''.gryonixnexus/jobs/update-x-7.log'\\''' " +
                "</dev/null >/dev/null 2>&1 & echo 'update-x-7'",
            launch)
    }

    @Test
    fun aDroppedStreamIsReattachedFromTheLastLine() = kotlinx.coroutines.test.runTest {
        val runner = FakeSSHCommandRunner()
        runner.stub("", stdout = "one\ntwo\n")
        runner.stub("", stdout = "three\n${DetachedJobs.EXIT_MARKER}0\n")
        val seen = mutableListOf<String>()

        val followed = DetachedJobs.follow(
            runner, SSHHostID.VPS, "backup-svc-1", kotlin.time.Duration.parse("5s"),
            retryDelay = kotlin.time.Duration.parse("1ms"),
        ) { seen += it }

        assertEquals(listOf("one\n", "two\n", "three\n"), seen)
        assertEquals(0, followed.exitCode)
        val follows = runner.calls.filter { it.kind == FakeSSHCommandRunner.CallKind.STREAM }
        assertEquals(2, follows.size)
        assertTrue(follows[1].command.contains("n=3"), "the second attach starts after the lines shown")
    }

    @Test
    fun aJobWithNoExitMarkerNeverReadsAsDone() = kotlinx.coroutines.test.runTest {
        val runner = FakeSSHCommandRunner()
        repeat(3) { runner.stub("", stdout = "") }

        val followed = DetachedJobs.follow(
            runner, SSHHostID.VPS, "backup-svc-1", kotlin.time.Duration.parse("5s"),
            reattaches = 2, retryDelay = kotlin.time.Duration.parse("1ms"),
        ) { }

        assertEquals(null, followed.exitCode)
    }
}
