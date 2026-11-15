package com.skaymer.gryonixnexus.app.servers.demo

import com.skaymer.gryonixnexus.servercontrol.CommandCatalog
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.random.Random

/** What the demo fleet remembers between commands */
object DemoFleetState {
    class Archive(val name: String, val bytes: Long, val madeMillis: Long)

    internal class Machine(
        val mailboxes: MutableList<String>,
        val updatable: MutableSet<String>,
    ) {
        /** Catalog ids whose containers are down */
        val stopped = mutableSetOf<String>()
        val removed = mutableSetOf<String>()

        /** `off`, `on`, or `only <hosts>` as the wrapper prints */
        var lockdown = "off"

        /** Per catalog id, newest first */
        val archives = mutableMapOf<String, MutableList<Archive>>()
        var backupSchedule = ""
        var updateSchedule = ""
        var lastUpdateRun = ""
    }

    private val machines = mutableMapOf<String, Machine>()

    @Synchronized
    fun forgetEverything() = machines.clear()

    @Synchronized
    internal fun <T> with(machine: DemoAgentMachine, read: (Machine) -> T): T =
        read(machines.getOrPut(machine.id) { seeded(machine) })

    private fun seeded(machine: DemoAgentMachine): Machine {
        val domain = machine.deployment.domain
        val seeded = Machine(
            mailboxes = mutableListOf("you@$domain", "family@$domain"),
            updatable = machine.containers.take(2).toMutableSet(),
        )
        val now = System.currentTimeMillis()
        for (id in machine.containers.take(3)) {
            seeded.archives[id] = mutableListOf(
                Archive("$id-2026-08-16-0300.tar.gz", 4_812_544, now - 7_200_000),
                Archive("$id-2026-08-09-0300.tar.gz", 4_755_100, now - 611_000_000),
            )
        }
        return seeded
    }

    fun stopped(machine: DemoAgentMachine): Set<String> = with(machine) { it.stopped.toSet() }

    fun removed(machine: DemoAgentMachine): Set<String> = with(machine) { it.removed.toSet() }

    fun setPower(stop: Boolean, service: String, machine: DemoAgentMachine) = with(machine) {
        if (stop) it.stopped.add(service) else it.stopped.remove(service)
    }

    fun remove(service: String, machine: DemoAgentMachine) = with(machine) {
        it.removed.add(service)
        it.stopped.remove(service)
    }

    fun install(service: String, machine: DemoAgentMachine) = with(machine) {
        it.removed.remove(service)
        it.stopped.remove(service)
    }

    fun archives(service: String, machine: DemoAgentMachine): List<Archive> =
        with(machine) { it.archives[service].orEmpty().toList() }

    fun addArchive(service: String, machine: DemoAgentMachine): Archive = with(machine) {
        val made = Archive("$service-${stamp()}.tar.gz", 4_900_000L + Random.nextLong(400_000), System.currentTimeMillis())
        it.archives.getOrPut(service) { mutableListOf() }.add(0, made)
        made
    }

    fun deleteArchive(name: String, machine: DemoAgentMachine) = with(machine) {
        it.archives.values.forEach { list -> list.removeAll { archive -> archive.name == name } }
    }

    fun backupSchedule(machine: DemoAgentMachine): String = with(machine) { it.backupSchedule }

    fun setBackupSchedule(value: String, machine: DemoAgentMachine) = with(machine) { it.backupSchedule = value }

    fun updateSchedule(machine: DemoAgentMachine): String = with(machine) { it.updateSchedule }

    fun setUpdateSchedule(value: String, machine: DemoAgentMachine) = with(machine) { it.updateSchedule = value }

    fun updatable(machine: DemoAgentMachine): Set<String> = with(machine) { it.updatable.toSet() }

    fun markUpdated(service: String, machine: DemoAgentMachine) = with(machine) {
        it.updatable.remove(service)
        it.lastUpdateRun = "${CommandCatalog.Updates.UPDATED_MARKER} $service"
    }

    fun mailboxes(machine: DemoAgentMachine): List<String> = with(machine) { it.mailboxes.toList() }

    fun addMailbox(address: String, machine: DemoAgentMachine) = with(machine) {
        if (address !in it.mailboxes) it.mailboxes.add(address)
    }

    fun removeMailbox(address: String, machine: DemoAgentMachine) = with(machine) { it.mailboxes.remove(address) }

    fun lockdown(machine: DemoAgentMachine): String = with(machine) { it.lockdown }

    fun setLockdown(value: String, machine: DemoAgentMachine) = with(machine) { it.lockdown = value }

    internal fun stamp(): String = SimpleDateFormat("yyyy-MM-dd-HHmm", Locale.US).format(Date())
}
