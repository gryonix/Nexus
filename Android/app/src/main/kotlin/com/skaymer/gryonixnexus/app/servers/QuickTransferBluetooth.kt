package com.skaymer.gryonixnexus.app.servers

import android.annotation.SuppressLint
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothGattServer
import android.bluetooth.BluetoothGattServerCallback
import android.bluetooth.BluetoothGattService
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.BluetoothStatusCodes
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.os.Build
import android.os.ParcelUuid
import com.skaymer.gryonixnexus.servercontrol.QuickTransferFailure
import com.skaymer.gryonixnexus.servercontrol.QuickTransferFrames
import com.skaymer.gryonixnexus.servercontrol.QuickTransferInbound
import com.skaymer.gryonixnexus.servercontrol.QuickTransferLink
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withTimeoutOrNull

/** Characteristic numbers both platforms use */
object QuickTransferBluetooth {
    val INBOX: UUID = UUID.fromString("7F3A0001-9C4B-4E8B-A1D2-3B6C8E5F0A11")
    val OUTBOX: UUID = UUID.fromString("7F3A0002-9C4B-4E8B-A1D2-3B6C8E5F0A11")
    val CLIENT_CONFIG: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
    const val DEFAULT_MTU = 23
}

/** Advertises the session; each subscriber becomes a link */
@SuppressLint("MissingPermission")
class QuickTransferBluetoothSender(
    private val context: Context,
    private val service: UUID,
    private val onLink: (QuickTransferLink) -> Unit,
) {
    private val manager = context.getSystemService(BluetoothManager::class.java)
    private var server: BluetoothGattServer? = null
    private var outbox: BluetoothGattCharacteristic? = null
    private val links = ConcurrentHashMap<String, PeripheralLink>()
    private val mtus = ConcurrentHashMap<String, Int>()
    private val advertising = object : AdvertiseCallback() {}
    @Volatile private var accepting = true

    fun start() {
        if (manager?.adapter?.isEnabled != true) return
        server = runCatching { manager.openGattServer(context, callback) }.getOrNull() ?: return
        val session = BluetoothGattService(service, BluetoothGattService.SERVICE_TYPE_PRIMARY)
        session.addCharacteristic(BluetoothGattCharacteristic(
            QuickTransferBluetooth.INBOX, BluetoothGattCharacteristic.PROPERTY_WRITE, BluetoothGattCharacteristic.PERMISSION_WRITE,
        ))
        val out = BluetoothGattCharacteristic(
            QuickTransferBluetooth.OUTBOX, BluetoothGattCharacteristic.PROPERTY_NOTIFY, BluetoothGattCharacteristic.PERMISSION_READ,
        )
        out.addDescriptor(BluetoothGattDescriptor(
            QuickTransferBluetooth.CLIENT_CONFIG,
            BluetoothGattDescriptor.PERMISSION_READ or BluetoothGattDescriptor.PERMISSION_WRITE,
        ))
        session.addCharacteristic(out)
        outbox = out
        server?.addService(session)
    }

    /** Takes no one new; the chosen receiver stays connected */
    fun stopAdvertising() {
        accepting = false
        runCatching { manager?.adapter?.bluetoothLeAdvertiser?.stopAdvertising(advertising) }
    }

    fun stop() {
        stopAdvertising()
        links.values.forEach { it.finish() }
        links.clear()
        runCatching { server?.close() }
        server = null
    }

    private fun advertise() {
        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setConnectable(true)
            .build()
        val data = AdvertiseData.Builder().addServiceUuid(ParcelUuid(service)).setIncludeDeviceName(false).build()
        runCatching { manager?.adapter?.bluetoothLeAdvertiser?.startAdvertising(settings, data, advertising) }
    }

    private val callback = object : BluetoothGattServerCallback() {
        override fun onServiceAdded(status: Int, service: BluetoothGattService) {
            if (status == BluetoothGatt.GATT_SUCCESS) advertise()
        }

        override fun onMtuChanged(device: BluetoothDevice, mtu: Int) {
            mtus[device.address] = mtu
            links[device.address]?.mtu = mtu
        }

        override fun onDescriptorWriteRequest(
            device: BluetoothDevice, requestId: Int, descriptor: BluetoothGattDescriptor,
            preparedWrite: Boolean, responseNeeded: Boolean, offset: Int, value: ByteArray?,
        ) {
            if (responseNeeded) server?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, null)
            val server = server ?: return
            val outbox = outbox ?: return
            if (!accepting || descriptor.uuid != QuickTransferBluetooth.CLIENT_CONFIG || links.containsKey(device.address)) return
            val link = PeripheralLink(server, device, outbox)
            link.mtu = mtus[device.address] ?: QuickTransferBluetooth.DEFAULT_MTU
            links[device.address] = link
            onLink(link)
        }

        override fun onCharacteristicWriteRequest(
            device: BluetoothDevice, requestId: Int, characteristic: BluetoothGattCharacteristic,
            preparedWrite: Boolean, responseNeeded: Boolean, offset: Int, value: ByteArray?,
        ) {
            if (responseNeeded) server?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, null)
            if (characteristic.uuid == QuickTransferBluetooth.INBOX && value != null) links[device.address]?.deliver(value)
        }

        override fun onNotificationSent(device: BluetoothDevice, status: Int) {
            links[device.address]?.sent()
        }

        override fun onConnectionStateChange(device: BluetoothDevice, status: Int, newState: Int) {
            if (newState == BluetoothProfile.STATE_DISCONNECTED) links.remove(device.address)?.finish()
        }
    }

    /** One subscribed central, seen as a link */
    private class PeripheralLink(
        private val server: BluetoothGattServer,
        private val device: BluetoothDevice,
        private val outbox: BluetoothGattCharacteristic,
    ) : QuickTransferLink {
        @Volatile var mtu = QuickTransferBluetooth.DEFAULT_MTU
        private val inbound = QuickTransferInbound()
        private val notified = Channel<Unit>(Channel.CONFLATED)

        fun deliver(bytes: ByteArray) = inbound.append(bytes)

        fun finish() = inbound.finish()

        fun sent() {
            notified.trySend(Unit)
        }

        override suspend fun send(payload: ByteArray) {
            for (chunk in QuickTransferInbound.chunks(QuickTransferFrames.frame(payload), maxOf(20, mtu - 3))) {
                if (!notify(chunk)) throw QuickTransferFailure.Closed()
                withTimeoutOrNull(2000) { notified.receive() } ?: throw QuickTransferFailure.Closed()
            }
        }

        @Suppress("DEPRECATION")
        private fun notify(chunk: ByteArray): Boolean = if (Build.VERSION.SDK_INT >= 33) {
            server.notifyCharacteristicChanged(device, outbox, false, chunk) == BluetoothStatusCodes.SUCCESS
        } else {
            outbox.value = chunk
            server.notifyCharacteristicChanged(device, outbox, false)
        }

        override suspend fun receive(): ByteArray = inbound.next()

        override fun close() = inbound.finish()
    }
}

/** Finds the sender's session over Bluetooth and connects to it */
@SuppressLint("MissingPermission")
class QuickTransferBluetoothReceiver private constructor(
    private val context: Context,
    private val service: UUID,
) : QuickTransferLink {
    private val manager = context.getSystemService(BluetoothManager::class.java)
    private var gatt: BluetoothGatt? = null
    private var inbox: BluetoothGattCharacteristic? = null
    private var mtu = QuickTransferBluetooth.DEFAULT_MTU
    private val ready = CompletableDeferred<Unit>()
    private val written = Channel<Boolean>(Channel.CONFLATED)
    private val inbound = QuickTransferInbound()
    @Volatile private var discovering = false

    private val scan = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            if (gatt != null) return
            manager?.adapter?.bluetoothLeScanner?.stopScan(this)
            gatt = result.device.connectGatt(context, false, callback, BluetoothDevice.TRANSPORT_LE)
        }

        override fun onScanFailed(errorCode: Int) {
            ready.completeExceptionally(QuickTransferFailure.Closed())
        }
    }

    private fun start() {
        val scanner = manager?.adapter?.takeIf { it.isEnabled }?.bluetoothLeScanner
            ?: return run { ready.completeExceptionally(QuickTransferFailure.Closed()) }
        val filter = ScanFilter.Builder().setServiceUuid(ParcelUuid(service)).build()
        val settings = ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build()
        runCatching { scanner.startScan(listOf(filter), settings, scan) }
            .onFailure { ready.completeExceptionally(QuickTransferFailure.Closed()) }
    }

    private val callback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
            when (newState) {
                BluetoothProfile.STATE_CONNECTED -> gatt.requestMtu(517)
                BluetoothProfile.STATE_DISCONNECTED -> fail()
            }
        }

        override fun onMtuChanged(gatt: BluetoothGatt, mtu: Int, status: Int) {
            if (status == BluetoothGatt.GATT_SUCCESS) this@QuickTransferBluetoothReceiver.mtu = mtu
            if (discovering) return
            discovering = true
            gatt.discoverServices()
        }

        override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
            val found = gatt.getService(service)
            inbox = found?.getCharacteristic(QuickTransferBluetooth.INBOX)
            val outbox = found?.getCharacteristic(QuickTransferBluetooth.OUTBOX)
            val config = outbox?.getDescriptor(QuickTransferBluetooth.CLIENT_CONFIG)
            if (inbox == null || outbox == null || config == null) return fail()
            gatt.setCharacteristicNotification(outbox, true)
            writeConfig(gatt, config)
        }

        override fun onDescriptorWrite(gatt: BluetoothGatt, descriptor: BluetoothGattDescriptor, status: Int) {
            if (status == BluetoothGatt.GATT_SUCCESS) ready.complete(Unit) else fail()
        }

        override fun onCharacteristicChanged(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic, value: ByteArray) {
            if (characteristic.uuid == QuickTransferBluetooth.OUTBOX) inbound.append(value)
        }

        @Deprecated("Android 12 and older")
        override fun onCharacteristicChanged(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic) {
            @Suppress("DEPRECATION")
            if (Build.VERSION.SDK_INT < 33) characteristic.value?.let { onCharacteristicChanged(gatt, characteristic, it) }
        }

        override fun onCharacteristicWrite(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic, status: Int) {
            written.trySend(status == BluetoothGatt.GATT_SUCCESS)
        }
    }

    @Suppress("DEPRECATION")
    private fun writeConfig(gatt: BluetoothGatt, config: BluetoothGattDescriptor) {
        val enable = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
        if (Build.VERSION.SDK_INT >= 33) {
            gatt.writeDescriptor(config, enable)
        } else {
            config.value = enable
            gatt.writeDescriptor(config)
        }
    }

    @Suppress("DEPRECATION")
    private fun write(chunk: ByteArray): Boolean {
        val gatt = gatt ?: return false
        val inbox = inbox ?: return false
        val type = BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
        return if (Build.VERSION.SDK_INT >= 33) {
            gatt.writeCharacteristic(inbox, chunk, type) == BluetoothStatusCodes.SUCCESS
        } else {
            inbox.writeType = type
            inbox.value = chunk
            gatt.writeCharacteristic(inbox)
        }
    }

    private fun fail() {
        if (!ready.isCompleted) runCatching { gatt?.close() }
        ready.completeExceptionally(QuickTransferFailure.Closed())
        written.trySend(false)
        inbound.finish()
    }

    override suspend fun send(payload: ByteArray) {
        for (chunk in QuickTransferInbound.chunks(QuickTransferFrames.frame(payload), maxOf(20, minOf(512, mtu - 3)))) {
            if (!write(chunk)) throw QuickTransferFailure.Closed()
            if (withTimeoutOrNull(5000) { written.receive() } != true) throw QuickTransferFailure.Closed()
        }
    }

    override suspend fun receive(): ByteArray = inbound.next()

    override fun close() {
        runCatching { manager?.adapter?.bluetoothLeScanner?.stopScan(scan) }
        runCatching { gatt?.disconnect() }
        runCatching { gatt?.close() }
        fail()
    }

    companion object {
        /** Scans, connects and subscribes; returns once ready */
        suspend fun connect(context: Context, service: UUID): QuickTransferLink {
            val receiver = QuickTransferBluetoothReceiver(context, service)
            return suspendCancellableCoroutine { continuation ->
                continuation.invokeOnCancellation { receiver.close() }
                receiver.ready.invokeOnCompletion { error ->
                    if (error == null) continuation.resume(receiver) { receiver.close() }
                    else if (continuation.isActive) continuation.resumeWith(Result.failure(error))
                }
                receiver.start()
            }
        }
    }
}
