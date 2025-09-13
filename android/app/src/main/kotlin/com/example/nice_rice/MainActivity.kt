package com.example.nice_rice

import android.annotation.SuppressLint
import android.bluetooth.*
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.*
import androidx.core.app.ActivityCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.util.*
import kotlin.concurrent.thread

class MainActivity : FlutterActivity() {

    private val CHANNEL = "app.bluetooth/controls"
    private lateinit var methodChannel: MethodChannel
    private lateinit var btAdapter: BluetoothAdapter
    private var gatt: BluetoothGatt? = null
    private var sppSocket: BluetoothSocket? = null



    private val SPP_UUID: UUID =
        UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val manager = getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        btAdapter = manager.adapter

        // ✅ Assign the method channel properly here
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)

        // Ask runtime permissions once (simple example)
        requestBtPermissionsIfNeeded()

        // ✅ Now set the handler on the initialized methodChannel
        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "ensureBluetoothOn" -> {
                    result.success(btAdapter.isEnabled)
                }

                "listBondedDevices" -> {
                    try {
                        val out = btAdapter.bondedDevices.map {
                            mapOf("name" to (it.name ?: ""), "address" to it.address)
                        }
                        result.success(out)
                    } catch (e: SecurityException) {
                        result.error("perm", "Missing BLUETOOTH_CONNECT", e.message)
                    }
                }

                "discoverDevices" -> {
                    discoverAllOnce(result)
                }

                "connect" -> {
                    val address = call.argument<String>("address")
                    val type = call.argument<String>("type") ?: "ble"
                    val timeoutMs = call.argument<Int>("timeoutMs") ?: 15000
                    if (address.isNullOrBlank()) {
                        result.error("bad_args", "Missing 'address'", null); return@setMethodCallHandler
                    }
                    when (type.lowercase(Locale.ROOT)) {
                        "spp" -> connectSpp(address, timeoutMs, result)
                        else  -> connectBle(address, timeoutMs, result)
                    }
                }

                "sendData" -> {
                    val data = call.argument<String>("data")
                    thread {
                        try {
                            val stream = sppSocket?.outputStream
                            val input = sppSocket?.inputStream
                            if (stream != null && data != null) {
                                stream.write((data + "\n").toByteArray())
                                stream.flush()

                                val buffer = ByteArray(128)
                                val len = input?.read(buffer) ?: -1
                                val reply = buffer.copyOf(len).toString(Charsets.UTF_8).trim()

                                runOnUiThread { result.success(reply) }
                            } else {
                                runOnUiThread { result.success(null) }
                            }
                        } catch (e: Exception) {
                            runOnUiThread {
                                result.error("send_fail", "Failed to send or receive", e.message)
                            }
                        }
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun requestBtPermissionsIfNeeded() {
        if (Build.VERSION.SDK_INT >= 31) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(
                    android.Manifest.permission.BLUETOOTH_SCAN,
                    android.Manifest.permission.BLUETOOTH_CONNECT
                ),
                1001
            )
        } else {
            // Pre-Android 12: scanning needs location
            ActivityCompat.requestPermissions(
                this,
                arrayOf(android.Manifest.permission.ACCESS_FINE_LOCATION),
                1002
            )
        }
    }

    // ---- Discovery: Classic + BLE (single pass, merged) ---------------------
    @SuppressLint("MissingPermission")
    private fun discoverAllOnce(result: MethodChannel.Result) {
        val out = mutableMapOf<String, MutableMap<String,String>>() // by address
        val handler = Handler(Looper.getMainLooper())

        // 1) bonded devices
        try {
            btAdapter.bondedDevices.forEach { d ->
                val addr = d.address ?: return@forEach
                val name = d.name ?: ""
                out.getOrPut(addr) { mutableMapOf("address" to addr, "name" to "") }["name"] = name
            }
        } catch (_: SecurityException) {}

        // 2) classic discovery
        val classicFilter = IntentFilter().apply {
            addAction(BluetoothDevice.ACTION_FOUND)
            addAction(BluetoothAdapter.ACTION_DISCOVERY_FINISHED)
        }
        val classicReceiver = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context?, intent: Intent?) {
                when (intent?.action) {
                    BluetoothDevice.ACTION_FOUND -> {
                        val dev = intent.getParcelableExtra<BluetoothDevice>(BluetoothDevice.EXTRA_DEVICE) ?: return
                        val addr = dev.address ?: return
                        val name = dev.name ?: ""
                        val entry = out.getOrPut(addr) { mutableMapOf("address" to addr, "name" to "") }
                        if (entry["name"].isNullOrEmpty() && name.isNotEmpty()) entry["name"] = name
                    }
                }
            }
        }

        val bleScanner = btAdapter.bluetoothLeScanner
        val bleCb = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, r: ScanResult) {
                val dev = r.device ?: return
                val addr = dev.address ?: return
                val name = dev.name ?: r.scanRecord?.deviceName ?: ""
                val entry = out.getOrPut(addr) { mutableMapOf("address" to addr, "name" to "") }
                if (entry["name"].isNullOrEmpty() && !name.isNullOrEmpty()) entry["name"] = name
            }
        }

        try {
            registerReceiver(classicReceiver, classicFilter)
            btAdapter.startDiscovery()
            try { bleScanner.startScan(bleCb) } catch (_: SecurityException) {}

            handler.postDelayed({
                try { btAdapter.cancelDiscovery() } catch (_: Exception) {}
                try { bleScanner.stopScan(bleCb) } catch (_: Exception) {}
                try { unregisterReceiver(classicReceiver) } catch (_: Exception) {}

                val list = out.values.map { mapOf("name" to (it["name"] ?: ""), "address" to (it["address"] ?: "")) }
                    .sortedWith(compareBy(
                        { if ((it["name"] ?: "").isEmpty()) 1 else 0 },
                        { (it["name"] ?: "zzzz").lowercase(Locale.ROOT) }
                    ))
                result.success(list)
            }, 4000)
        } catch (e: SecurityException) {
            try { unregisterReceiver(classicReceiver) } catch (_: Exception) {}
            result.error("perm", "Missing BLUETOOTH_SCAN/CONNECT permission", e.message)
        }
    }

    // ---- BLE GATT connect (for completeness) --------------------------
    @SuppressLint("MissingPermission")
    private fun connectBle(address: String, timeoutMs: Int, result: MethodChannel.Result) {
        val device = btAdapter.getRemoteDevice(address)
        var completed = false

        val cb = object : BluetoothGattCallback() {
            override fun onConnectionStateChange(g: BluetoothGatt, status: Int, newState: Int) {
                if (newState == BluetoothProfile.STATE_CONNECTED) {
                    gatt = g
                    if (!completed) {
                        completed = true
                        result.success(true)
                    }
                } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                    if (!completed) {
                        completed = true
                        result.success(false)
                    }
                    g.close()
                }
            }
        }

        try {
            val g = device.connectGatt(this, false, cb, BluetoothDevice.TRANSPORT_LE)
            Handler(Looper.getMainLooper()).postDelayed({
                if (!completed) {
                    completed = true
                    try { g.disconnect(); g.close() } catch (_: Exception) {}
                    result.success(false)
                }
            }, timeoutMs.toLong())
        } catch (e: SecurityException) {
            result.error("perm", "Missing BLUETOOTH_CONNECT permission", e.message)
        }
    }

    // ---- Classic SPP connect (for your ESP32 BluetoothSerial) ---------------
    @SuppressLint("MissingPermission")
    private fun connectSpp(address: String, timeoutMs: Int, result: MethodChannel.Result) {
        thread {
            try {
                val device = btAdapter.getRemoteDevice(address)
                val sock = device.createRfcommSocketToServiceRecord(SPP_UUID)
                btAdapter.cancelDiscovery()
                sock.connect() // blocks; success => RFCOMM up
                sppSocket = sock

                // 🔁 Start listening for incoming data (e.g., MOISTURE:xxxx)
                thread {
                    val input = sock.inputStream
                    val reader = input.bufferedReader()

                    try {
                        while (true) {
                            val line = reader.readLine() ?: break
                            val clean = line.trim()
                            if (clean.isNotEmpty()) {
                                runOnUiThread {
                                    methodChannel.invokeMethod("onDataReceived", clean)
                                }
                            }
                        }
                    } catch (_: Exception) {
                        // Connection lost or read error
                    }
                }


                runOnUiThread { result.success(true) }
            } catch (e: IOException) {
                runOnUiThread { result.success(false) }
            } catch (e: SecurityException) {
                runOnUiThread { result.error("perm", "Missing BLUETOOTH_CONNECT permission", e.message) }
            }
        }
    }
}
