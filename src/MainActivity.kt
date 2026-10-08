package com.abdulloh.phone_mouse
import android.annotation.SuppressLint
import android.bluetooth.*
import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

@SuppressLint("MissingPermission")
class MainActivity : FlutterActivity() {
  private var hid: BluetoothHidDevice? = null
  private var host: BluetoothDevice? = null
  private var channel: MethodChannel? = null
  private val adapter get() = (getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager).adapter
  private val executor = java.util.concurrent.Executors.newSingleThreadExecutor()
  private val descriptor = byteArrayOf(0x05,1,0x09,2,0xA1.toByte(),1,0x09,1,0xA1.toByte(),0,0x05,9,0x19,1,0x29,3,0x15,0,0x25,1,0x95.toByte(),3,0x75,1,0x81.toByte(),2,0x95.toByte(),1,0x75,5,0x81.toByte(),3,0x05,1,0x09,0x30,0x09,0x31,0x09,0x38,0x15,0x81.toByte(),0x25,0x7f,0x75,8,0x95.toByte(),3,0x81.toByte(),6,0xC0.toByte(),0xC0.toByte())
  private val callback = object : BluetoothHidDevice.Callback() {
    override fun onConnectionStateChanged(device: BluetoothDevice, state: Int) {
      val connected = state == BluetoothProfile.STATE_CONNECTED
      if (connected) host = device else if (state == BluetoothProfile.STATE_DISCONNECTED) host = null
      runOnUiThread { channel?.invokeMethod("state", connected) }
    }
  }
  override fun configureFlutterEngine(engine: FlutterEngine) {
    super.configureFlutterEngine(engine)
    channel = MethodChannel(engine.dartExecutor.binaryMessenger, "mouse")
    channel!!.setMethodCallHandler { call, result ->
      when (call.method) {
        "start" -> {
          adapter.getProfileProxy(this, object : BluetoothProfile.ServiceListener {
            override fun onServiceConnected(profile: Int, proxy: BluetoothProfile) {
              hid = proxy as BluetoothHidDevice
              hid?.registerApp(BluetoothHidDeviceAppSdpSettings("PhoneMouse","Phone Mouse","Abdulloh",BluetoothHidDevice.SUBCLASS1_MOUSE,descriptor),null,null,executor,callback)
            }
            override fun onServiceDisconnected(profile: Int) { hid = null }
          }, BluetoothProfile.HID_DEVICE)
          result.success(null)
        }
        "devices" -> result.success(adapter.bondedDevices.map { mapOf("name" to (it.name ?: it.address), "addr" to it.address) })
        "connect" -> result.success(hid?.connect(adapter.getRemoteDevice(call.arguments as String)) ?: false)
        "disconnect" -> { host?.let { hid?.disconnect(it) }; result.success(null) }
        "send" -> {
          val values = call.arguments as List<*>
          host?.let { hid?.sendReport(it,0,byteArrayOf((values[0] as Int).toByte(),(values[1] as Int).toByte(),(values[2] as Int).toByte(),(values[3] as Int).toByte())) }
          result.success(null)
        }
        else -> result.notImplemented()
      }
    }
  }
}