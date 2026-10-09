package com.abdulloh.phone_mouse

import android.annotation.SuppressLint
import android.bluetooth.*
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

@SuppressLint("MissingPermission")
class MainActivity : FlutterActivity() {
    private var hid: BluetoothHidDevice? = null
    private var host: BluetoothDevice? = null
    private var last: BluetoothDevice? = null
    private var manual = false
    private var tries = 0
    private var registered = false
    private var ch: MethodChannel? = null
    private val ex = Executors.newSingleThreadExecutor()
    private val ui = Handler(Looper.getMainLooper())
    private val adapter get() = (getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager).adapter

    private val desc = intArrayOf(
        0x05,0x01,0x09,0x02,0xA1,0x01,0x09,0x01,0xA1,0x00,0x05,0x09,0x19,0x01,0x29,0x03,
        0x15,0x00,0x25,0x01,0x95,0x03,0x75,0x01,0x81,0x02,0x95,0x01,0x75,0x05,0x81,0x03,
        0x05,0x01,0x09,0x30,0x09,0x31,0x09,0x38,0x15,0x81,0x25,0x7F,0x75,0x08,0x95,0x03,
        0x81,0x06,0xC0,0xC0
    ).map { it.toByte() }.toByteArray()

    private fun notify(st: Int) = ui.post { ch?.invokeMethod("state", st) }

    private fun register() {
        val h = hid ?: return
        h.registerApp(
            BluetoothHidDeviceAppSdpSettings("PhoneMouse", "Phone Mouse", "Abdulloh",
                BluetoothHidDevice.SUBCLASS1_MOUSE, desc), null, null, ex, cb)
    }

    private val cb = object : BluetoothHidDevice.Callback() {
        override fun onAppStatusChanged(d: BluetoothDevice?, ok: Boolean) {
            registered = ok
            if (!ok) ui.postDelayed({ register() }, 1000)
        }
        override fun onConnectionStateChanged(d: BluetoothDevice, s: Int) {
            when (s) {
                BluetoothProfile.STATE_CONNECTED -> { host = d; last = d; tries = 0; notify(2) }
                BluetoothProfile.STATE_CONNECTING -> notify(1)
                else -> {
                    if (host == d || host == null) host = null
                    notify(0)
                    val l = last
                    if (!manual && l != null && tries < 6) {
                        tries++
                        ui.postDelayed({ if (host == null) hid?.connect(l) }, 2000)
                    }
                }
            }
        }
        override fun onGetReport(d: BluetoothDevice, type: Byte, id: Byte, size: Int) {
            hid?.replyReport(d, type, id, ByteArray(4))
        }
    }

    override fun configureFlutterEngine(e: FlutterEngine) {
        super.configureFlutterEngine(e)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        ch = MethodChannel(e.dartExecutor.binaryMessenger, "mouse")
        ch!!.setMethodCallHandler { c, r ->
            when (c.method) {
                "start" -> { start(); r.success(null) }
                "devices" -> r.success(adapter.bondedDevices.map { mapOf("name" to (it.name ?: it.address), "addr" to it.address) })
                "connect" -> {
                    val d = adapter.getRemoteDevice(c.arguments as String)
                    manual = false; tries = 0; last = d
                    r.success(if (hid != null && registered) hid!!.connect(d) else false)
                }
                "disconnect" -> { manual = true; host?.let { hid?.disconnect(it) }; r.success(null) }
                "discoverable" -> {
                    startActivity(Intent(BluetoothAdapter.ACTION_REQUEST_DISCOVERABLE)
                        .putExtra(BluetoothAdapter.EXTRA_DISCOVERABLE_DURATION, 300))
                    r.success(null)
                }
                "send" -> {
                    val a = c.arguments as List<*>
                    val h = host
                    if (h != null) hid?.sendReport(h, 0, byteArrayOf(
                        (a[0] as Int).toByte(), (a[1] as Int).toByte(), (a[2] as Int).toByte(), (a[3] as Int).toByte()))
                    r.success(null)
                }
                else -> r.notImplemented()
            }
        }
    }

    private fun start() {
        if (hid != null) { if (!registered) register(); return }
        adapter.getProfileProxy(this, object : BluetoothProfile.ServiceListener {
            override fun onServiceConnected(p: Int, proxy: BluetoothProfile) {
                hid = proxy as BluetoothHidDevice
                register()
            }
            override fun onServiceDisconnected(p: Int) { hid = null; registered = false }
        }, BluetoothProfile.HID_DEVICE)
    }

    override fun onDestroy() {
        manual = true
        try { hid?.unregisterApp(); adapter.closeProfileProxy(BluetoothProfile.HID_DEVICE, hid) } catch (_: Exception) {}
        super.onDestroy()
    }
}