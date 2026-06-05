package lightly.tool

import android.content.Intent
import android.net.VpnService
import android.os.ParcelFileDescriptor
import android.util.Log
import java.net.Inet4Address
import java.net.InetAddress
import kotlin.concurrent.thread
import com.easytier.jni.EasyTierJNI

internal object EasyTierRouteNormalizer {
    fun parseRoute(cidr: String): Pair<String, Int> {
        val (ip, prefixLength) = parseCidr(cidr)
        return Pair(toNetworkAddress(ip, prefixLength), prefixLength)
    }

    fun toNetworkAddress(ip: String, prefixLength: Int): String {
        require(prefixLength in 0..32) { "Invalid prefix length: $prefixLength" }

        val address = InetAddress.getByName(ip)
        require(address is Inet4Address) { "Only IPv4 routes are supported: $ip" }

        val bytes = address.address
        var value = 0L
        for (byte in bytes) {
            value = (value shl 8) or (byte.toInt().toLong() and 0xff)
        }

        val mask = if (prefixLength == 0) {
            0L
        } else {
            (0xffffffffL shl (32 - prefixLength)) and 0xffffffffL
        }
        val network = value and mask

        return listOf(
            (network shr 24) and 0xff,
            (network shr 16) and 0xff,
            (network shr 8) and 0xff,
            network and 0xff,
        ).joinToString(".")
    }

    private fun parseCidr(cidr: String): Pair<String, Int> {
        val parts = cidr.split("/")
        if (parts.size != 2) {
            throw IllegalArgumentException("Invalid CIDR format: $cidr")
        }
        return Pair(parts[0], parts[1].toInt())
    }
}

class EasyTierVpnService : VpnService() {

    private var vpnInterface: ParcelFileDescriptor? = null
    private var isRunning = false
    private var instanceName: String? = null

    companion object {
        private const val TAG = "EasyTierVpnService"
        const val ACTION_STOP = "lightly.tool.action.STOP_EASYTIER_VPN"
    }

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "VPN Service created")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            Log.i(TAG, "Received explicit stop action")
            cleanup()
            stopSelf()
            return START_NOT_STICKY
        }

        val ipv4Address = intent?.getStringExtra("ipv4_address")
        instanceName = intent?.getStringExtra("instance_name")

        if (ipv4Address == null || instanceName == null) {
            Log.e(TAG, "Missing required params: ipv4Address=$ipv4Address, instanceName=$instanceName")
            stopSelf()
            return START_NOT_STICKY
        }

        Log.i(TAG, "Starting VPN Service - IPv4: $ipv4Address, Instance: $instanceName")

        thread {
            try {
                setupVpnInterface(ipv4Address)
            } catch (t: Throwable) {
                Log.e(TAG, "VPN setup failed", t)
                stopSelf()
            }
        }

        return START_STICKY
    }

    private fun setupVpnInterface(ipv4Address: String) {
        try {
            val (ip, networkLength) = parseIpv4Address(ipv4Address)
            val networkAddress = EasyTierRouteNormalizer.toNetworkAddress(ip, networkLength)

            val builder = Builder()
            builder.setSession("EasyTier VPN")
                    .addAddress(ip, networkLength)
                    .addDnsServer("223.5.5.5")
                    .addDnsServer("114.114.114.114")

            // Add route for the EasyTier virtual subnet
            try {
                builder.addRoute(networkAddress, networkLength)
                Log.d(TAG, "Added primary EasyTier route: $networkAddress/$networkLength (host $ip)")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to add EasyTier subnet route $networkAddress/$networkLength for host $ip", e)
            }

            vpnInterface = builder.establish()

            if (vpnInterface == null) {
                Log.e(TAG, "Failed to create VPN interface")
                return
            }

            Log.i(TAG, "VPN interface created successfully")

            instanceName?.let { name ->
                val fd = vpnInterface!!.fd
                val result = EasyTierJNI.setTunFd(name, fd)
                if (result == 0) {
                    Log.i(TAG, "TUN FD set successfully: $fd")
                } else {
                    Log.e(TAG, "Failed to set TUN FD: $result")
                }
            }

            isRunning = true

            while (isRunning && vpnInterface != null) {
                Thread.sleep(1000)
            }
        } catch (t: Throwable) {
            Log.e(TAG, "Error during VPN interface setup", t)
        } finally {
            cleanup()
        }
    }

    private fun parseIpv4Address(ipv4Address: String): Pair<String, Int> {
        return if (ipv4Address.contains("/")) {
            val parts = ipv4Address.split("/")
            Pair(parts[0], parts[1].toInt())
        } else {
            Pair(ipv4Address, 24)
        }
    }

    private fun parseCidr(cidr: String): Pair<String, Int> {
        val parts = cidr.split("/")
        if (parts.size != 2) {
            throw IllegalArgumentException("Invalid CIDR format: $cidr")
        }
        return Pair(parts[0], parts[1].toInt())
    }

    private fun cleanup() {
        isRunning = false
        vpnInterface?.close()
        vpnInterface = null
        Log.i(TAG, "VPN interface cleaned up")
    }

    override fun onDestroy() {
        cleanup()
        Log.d(TAG, "VPN Service destroyed")
        super.onDestroy()
    }

    override fun onRevoke() {
        Log.i(TAG, "VPN permission revoked / VPN replaced")
        cleanup()
        stopSelf()
        super.onRevoke()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        Log.i(TAG, "VPN task removed")
        cleanup()
        stopSelf()
        super.onTaskRemoved(rootIntent)
    }
}
