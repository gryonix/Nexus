package com.skaymer.gryonixnexus.servercontrol

import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

class BackupListParserTest {
    @Test
    fun `files and directories are listed, total and links are not`() {
        val output = """
            total 1.5G
            -rw-r--r-- 1 root root 512M Jul 10 03:00 mailcow-2026-07-10.tar.gz
            drwxr-xr-x 2 root root 4.0K Jul  9 03:00 mailcow-2026-07-09-03-00-00
            lrwxrwxrwx 1 root root   24 Jul  8 03:00 latest -> mailcow-2026-07-09
            -rw-r--r-- 1 user user  48M Jul  9 03:05 vw-backup with space.tar.gz.gpg
        """.trimIndent()

        val entries = BackupListParser.parse(output)

        assertEquals(3, entries.size)
        assertEquals("mailcow-2026-07-10.tar.gz", entries[0].name)
        assertEquals("512M", entries[0].sizeText)
        assertEquals("Jul 10 03:00", entries[0].dateText)
        assertEquals("mailcow-2026-07-09-03-00-00", entries[1].name)
        assertTrue(entries[1].isDirectory)
        assertEquals("vw-backup with space.tar.gz.gpg", entries[2].name)
    }

    @Test
    fun `consecutive spaces in a name survive`() {
        val entries = BackupListParser.parse(
            "-rw-r--r-- 1 user user 48M Jul  9 03:05 my  backup   v2.tar.gz.gpg",
        )
        assertEquals(1, entries.size)
        assertEquals("my  backup   v2.tar.gz.gpg", entries[0].name)
    }

    @Test
    fun `a name repeating an earlier column is not truncated`() {
        val entries = BackupListParser.parse("-rw-r--r-- 1 root root 4.0K Jul  9 03:05 root-4.0K.tar.gz")
        assertEquals(1, entries.size)
        assertEquals("root-4.0K.tar.gz", entries[0].name)
    }

    @Test
    fun `a full path is kept and stripped only for display`() {
        val entries = BackupListParser.parse(
            "-rw-r--r-- 1 user user 48M Jul  9 03:05 /opt/backups/vaultwarden/vault-20260709.tar.gz.gpg",
        )
        assertEquals("/opt/backups/vaultwarden/vault-20260709.tar.gz.gpg", entries[0].name)
        assertEquals("vault-20260709.tar.gz.gpg", entries[0].displayName)

        val plain = BackupListParser.parse(
            "-rw-r--r-- 1 user user 48M Jul  9 03:05 vault-20260709.tar.gz.gpg",
        )
        assertEquals("vault-20260709.tar.gz.gpg", plain[0].displayName)
    }

    @Test
    fun `the listing is bounded`() {
        val output = (0 until 15).joinToString("\n") {
            "-rw-r--r-- 1 root root 1M Jul 10 03:00 file-$it.gz"
        }
        assertEquals(10, BackupListParser.parse(output).size)
    }
}

class DKIMRecordParserTest {
    private val report = """
        Some prose the installer printed, localized at generation time.
        GRYONIXNEXUS_DKIM dkim._domainkey.example.com v=DKIM1; k=rsa; p=MIIBIjANBg
        GRYONIXNEXUS_DKIM dkim._domainkey.second.example v=DKIM1; k=rsa; p=AAAABBB
        More prose.
    """.trimIndent()

    @Test
    fun `every marker line becomes a record, value and all`() {
        val records = DKIMRecordParser.parse(report)
        assertEquals(2, records.size)
        assertEquals("dkim._domainkey.example.com", records[0].name)
        assertEquals("v=DKIM1; k=rsa; p=MIIBIjANBg", records[0].value)
        assertEquals("TXT", records[0].type)
        assertEquals("dkim._domainkey.second.example", records[1].name)
    }

    @Test
    fun `the markers are stripped from what a human reads`() {
        val stripped = DKIMRecordParser.stripMarkers(report)
        assertTrue(!stripped.contains(DKIMRecordParser.MARKER))
        assertTrue(stripped.contains("Some prose"))
        assertTrue(stripped.contains("More prose."))
    }

    @Test
    fun `a marker line with no value is not a record`() {
        assertEquals(emptyList(), DKIMRecordParser.parse("GRYONIXNEXUS_DKIM dkim._domainkey.example.com"))
    }
}

class BackupEstimateTest {
    @Test
    fun `the wrapper's estimate line becomes bytes`() {
        val estimate = BackupEstimate.parse("some output\nGRYONIXNEXUS_BACKUP_ESTIMATE 1024 4096\ndone")
        assertEquals(1024L, estimate?.dataBytes)
        assertEquals(4096L, estimate?.freeBytes)
        assertTrue(estimate?.fitsOnDisk == true)
    }

    /**
     * **An older server answers "unsupported action", and that must read as NO
     * ESTIMATE, never as a number.** A zero here would say "this backup costs
     * nothing and the disk is full", which is two wrong answers at once.
     */
    @Test
    fun `a server that does not know the subcommand yields no estimate`() {
        assertNull(BackupEstimate.parse("gryonixnexus-backup-ctl: unsupported action 'estimate'"))
        assertNull(BackupEstimate.parse(""))
    }

    /** A truncated marker line is not half an estimate. */
    @Test
    fun `a marker line missing a field yields no estimate`() {
        assertNull(BackupEstimate.parse("GRYONIXNEXUS_BACKUP_ESTIMATE 1024"))
        assertNull(BackupEstimate.parse("GRYONIXNEXUS_BACKUP_ESTIMATE not-a-number 4096"))
    }

    @Test
    fun `a run that would not fit says so`() {
        val estimate = BackupEstimate.parse("GRYONIXNEXUS_BACKUP_ESTIMATE 8192 4096")
        assertTrue(estimate?.fitsOnDisk == false)
    }

    /**
     * The LAST done line wins: a wrapper that retried announces more than one,
     * and the archive that exists is the one it finished with.
     */
    @Test
    fun `the finished archive is read from the last done line`() {
        val outcome = BackupOutcome.parse(
            "GRYONIXNEXUS_BACKUP_DONE 10 /opt/backups/old.tar.gz\n" +
                "GRYONIXNEXUS_BACKUP_DONE 2048 /opt/backups/vault-20260709.tar.gz.gpg",
            log = "log",
        )
        assertEquals(2048L, outcome?.sizeBytes)
        assertEquals("/opt/backups/vault-20260709.tar.gz.gpg", outcome?.path)
    }

    /** mailcow runs its own tool and announces nothing this can parse. */
    @Test
    fun `a run that announced no archive yields no outcome`() {
        assertNull(BackupOutcome.parse("mailcow: backup complete", log = "log"))
    }
}

class OutputTailTest {
    @Test
    fun `a long output keeps its END, which is what says whether it worked`() {
        val long = "a".repeat(5000) + "END"
        val tail = OutputTail.tail(long)
        assertEquals(3001, tail.length) // ellipsis + 3000 chars
        assertTrue(tail.endsWith("END"))
        assertTrue(tail.startsWith("…"))
    }

    @Test
    fun `a short output is untouched`() {
        assertEquals("short", OutputTail.tail("short"))
    }
}

class ContainerStatusTest {
    /** The STATUS column is verbatim docker text, and health is read off it. */
    @Test
    fun `docker's own words decide the health`() {
        assertEquals(HealthLevel.OK, ContainerStatus("vw", "Up 3 days (healthy)").health)
        assertEquals(HealthLevel.CRITICAL, ContainerStatus("web", "Exited (0) 2 days ago").health)
        assertEquals(HealthLevel.WARNING, ContainerStatus("db", "Created").health)
    }

    @Test
    fun `a restarting container is a warning, not a success`() {
        assertEquals(HealthLevel.WARNING, ContainerStatus("x", "Restarting (1) 5 seconds ago").health)
    }
}

class DockerComposePSParserTest {
    @Test
    fun `every row becomes a container, and its own words decide the health`() {
        val output = """
            NAME                                  IMAGE                       COMMAND                  SERVICE          CREATED       STATUS                 PORTS
            mailcowdockerized-nginx-mailcow-1     nginx:mainline-alpine       "/docker-entrypoint.…"   nginx-mailcow    2 weeks ago   Up 2 hours (healthy)   0.0.0.0:443->443/tcp
            mailcowdockerized-postfix-mailcow-1   mailcow/postfix:1.77        "/docker-entrypoint.…"   postfix-mailcow  2 weeks ago   Exited (1) 3 days ago
            mailcowdockerized-watchdog-mailcow-1  mailcow/watchdog:2.05       "/watchdog.sh"           watchdog-mailcow 2 weeks ago   Restarting (1) 5 seconds ago
        """.trimIndent()

        val statuses = DockerComposePSParser.parse(output)

        assertEquals(3, statuses.size)
        assertEquals("mailcowdockerized-nginx-mailcow-1", statuses[0].name)
        assertEquals(HealthLevel.OK, statuses[0].health)
        assertEquals(HealthLevel.CRITICAL, statuses[1].health)
        assertEquals(HealthLevel.WARNING, statuses[2].health)
    }

    @Test
    fun `output with no header is a parse failure, not an empty list`() {
        assertFailsWith<ServerControlError.ParseFailure> {
            DockerComposePSParser.parse("Cannot connect to the Docker daemon\n")
        }
    }
}

class DockerPSParserTest {
    private val output = """
        CONTAINER ID   IMAGE                        COMMAND            CREATED       STATUS                  PORTS                    NAMES
        1a2b3c4d5e6f   vaultwarden/server:latest    "/start.sh"        3 weeks ago   Up 3 days (healthy)     127.0.0.1:8080->80/tcp   vaultwarden
        9f8e7d6c5b4a   nginx:alpine                 "/entrypoint.sh"   4 weeks ago   Exited (0) 2 days ago                            web,web-alias
    """.trimIndent()

    @Test
    fun `a container is found by its exact name`() {
        val vw = DockerPSParser.find("vaultwarden", DockerPSParser.parse(output))
        assertEquals(HealthLevel.OK, vw?.health)
        assertTrue(vw!!.status.startsWith("Up 3 days"))
    }

    @Test
    fun `a container is found among comma-separated names`() {
        val web = DockerPSParser.find("web-alias", DockerPSParser.parse(output))
        assertEquals(HealthLevel.CRITICAL, web?.health)
    }

    @Test
    fun `a container that is not there is null, not a wrong row`() {
        assertNull(DockerPSParser.find("mailcow", DockerPSParser.parse(output)))
    }
}

class ANSIStripperTest {
    @Test
    fun `colour and cursor sequences are removed, the text is not`() {
        val coloured = "\u001B[1;32mOK\u001B[0m done \u001B[2K\u001B[1Gend"
        assertEquals("OK done end", ANSIStripper.strip(coloured))
    }

    @Test
    fun `carriage-return progress collapses to what it ended up saying`() {
        val progress = "Downloading 10%\rDownloading 50%\rDownloading 100%\nDone"
        assertEquals("Downloading 100%\nDone", ANSIStripper.strip(progress))
    }

    @Test
    fun `an OSC title is removed by either of its two endings`() {
        assertEquals("ab", ANSIStripper.strip("a\u001B]0;window title\u0007b"))
        assertEquals("ab", ANSIStripper.strip("a\u001B]0;window title\u001B\\b"))
    }
}
