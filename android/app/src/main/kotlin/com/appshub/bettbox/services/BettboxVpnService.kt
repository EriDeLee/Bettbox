package com.appshub.bettbox.services

import android.annotation.SuppressLint
import android.content.Intent
import android.net.ProxyInfo
import android.net.VpnService
import android.os.Binder
import android.os.Build
import android.os.IBinder
import android.os.Parcel
import android.os.RemoteException
import androidx.core.app.NotificationCompat
import com.appshub.bettbox.GlobalState
import com.appshub.bettbox.extensions.getIpv4RouteAddress
import com.appshub.bettbox.extensions.getIpv6RouteAddress
import com.appshub.bettbox.extensions.toCIDR
import com.appshub.bettbox.models.AccessControlMode
import com.appshub.bettbox.models.VpnOptions
import com.appshub.bettbox.plugins.VpnPlugin
import com.appshub.bettbox.util.LogModule
import com.appshub.bettbox.util.LogUtils
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch


class BettboxVpnService : VpnService(), BaseServiceInterface {
    companion object {
        private const val TAG = "BettboxVpnService"
    }

    override fun onCreate() {
        super.onCreate()
        LogUtils.i(LogModule.SERVICE, "=== onCreate: VPN Service Creating ===")
        try {
            GlobalState.initServiceEngine()
            LogUtils.d(LogModule.SERVICE, "Service engine initialized")
        } catch (e: Exception) {
            LogUtils.e(LogModule.SERVICE, "Failed to init service engine", e)
            throw e
        }
    }

    override fun start(options: VpnOptions): Int {
        LogUtils.i(LogModule.SERVICE, "=== Starting VPN Service ===")
        LogUtils.d(LogModule.SERVICE, "VPN Options: enable=${options.enable}, dns=${options.dnsServerAddress}, mtu=1480")
        
        return with(Builder()) {
            try {
                // IPv4 配置
                if (options.ipv4Address.isNotEmpty()) {
                    val cidr = options.ipv4Address.toCIDR()
                    addAddress(cidr.address, cidr.prefixLength)
                    LogUtils.d(LogModule.SERVICE, "IPv4 Address: ${cidr.address}/${cidr.prefixLength}")
                    
                    val routeAddress = options.getIpv4RouteAddress()
                    if (routeAddress.isNotEmpty()) {
                        try {
                            routeAddress.forEach { i ->
                                LogUtils.v(LogModule.SERVICE, "Adding IPv4 route: ${i.address}/${i.prefixLength}")
                                addRoute(i.address, i.prefixLength)
                            }
                        } catch (e: Exception) {
                            LogUtils.w(LogModule.SERVICE, "Failed to add specific routes, using default route", e)
                            addRoute("0.0.0.0", 0)
                        }
                    } else {
                        LogUtils.d(LogModule.SERVICE, "No specific routes, adding default route 0.0.0.0/0")
                        addRoute("0.0.0.0", 0)
                    }
                } else {
                    LogUtils.d(LogModule.SERVICE, "No IPv4 address, adding default route")
                    addRoute("0.0.0.0", 0)
                }
                
                // IPv6 配置
                try {
                    if (options.ipv6Address.isNotEmpty()) {
                        val cidr = options.ipv6Address.toCIDR()
                        LogUtils.d(LogModule.SERVICE, "IPv6 Address: ${cidr.address}/${cidr.prefixLength}")
                        addAddress(cidr.address, cidr.prefixLength)
                        
                        val routeAddress = options.getIpv6RouteAddress()
                        if (routeAddress.isNotEmpty()) {
                            try {
                                routeAddress.forEach { i ->
                                    LogUtils.v(LogModule.SERVICE, "Adding IPv6 route: ${i.address}/${i.prefixLength}")
                                    addRoute(i.address, i.prefixLength)
                                }
                            } catch (e: Exception) {
                                LogUtils.w(LogModule.SERVICE, "Failed to add specific IPv6 routes", e)
                                addRoute("::", 0)
                            }
                        } else {
                            LogUtils.d(LogModule.SERVICE, "No specific IPv6 routes, adding default route ::/0")
                            addRoute("::", 0)
                        }
                    }
                } catch (e: Exception) {
                    LogUtils.w(LogModule.SERVICE, "IPv6 is not supported or disabled")
                }
                
                // DNS 配置
                LogUtils.d(LogModule.SERVICE, "DNS Server: ${options.dnsServerAddress}")
                addDnsServer(options.dnsServerAddress)
                
                // MTU 配置
                setMtu(1480)
                LogUtils.d(LogModule.SERVICE, "MTU: 1480")
                
                // 访问控制配置
                options.accessControl.let { accessControl ->
                    if (accessControl.enable) {
                        LogUtils.d(LogModule.SERVICE, "Access control enabled: mode=${accessControl.mode}")
                        when (accessControl.mode) {
                            AccessControlMode.acceptSelected -> {
                                LogUtils.d(LogModule.SERVICE, "Accept list size: ${accessControl.acceptList.size}")
                                (accessControl.acceptList + packageName).forEach {
                                    addAllowedApplication(it)
                                }
                            }

                            AccessControlMode.rejectSelected -> {
                                LogUtils.d(LogModule.SERVICE, "Reject list size: ${accessControl.rejectList.size}")
                                (accessControl.rejectList - packageName).forEach {
                                    addDisallowedApplication(it)
                                }
                            }
                        }
                    } else {
                        LogUtils.d(LogModule.SERVICE, "Access control disabled")
                    }
                }
                
                // 会话配置
                setSession("Bettbox")
                setBlocking(false)
                if (Build.VERSION.SDK_INT >= 29) {
                    setMetered(false)
                }
                if (options.allowBypass) {
                    allowBypass()
                    LogUtils.d(LogModule.SERVICE, "Bypass allowed")
                }
                
                // 代理配置
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && options.systemProxy) {
                    LogUtils.d(LogModule.SERVICE, "System proxy enabled: port=${options.port}")
                    setHttpProxy(
                        ProxyInfo.buildDirectProxy(
                            "127.0.0.1",
                            options.port,
                            options.bypassDomain
                        )
                    )
                } else {
                    LogUtils.d(LogModule.SERVICE, "System proxy disabled")
                }
                
                // 建立 VPN 连接
                LogUtils.d(LogModule.SERVICE, "Establishing VPN connection...")
                val fd = establish()?.detachFd()
                    ?: throw NullPointerException("Establish VPN rejected by system")
                
                LogUtils.i(LogModule.SERVICE, "VPN established successfully, FD: $fd")
                return fd
            } catch (e: Exception) {
                LogUtils.e(LogModule.SERVICE, "Failed to start VPN service", e)
                throw e
            }
        }
    }

    override fun stop() {
        LogUtils.i(LogModule.SERVICE, "=== Stopping VPN Service ===")
        stopSelf()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        }
        LogUtils.d(LogModule.SERVICE, "VPN Service stopped")
    }

    override fun onRevoke() {
        LogUtils.w(LogModule.SERVICE, "=== VPN Revoked by System ===")
        VpnPlugin.handleStop()
        super.onRevoke()
    }

    private var cachedBuilder: NotificationCompat.Builder? = null

    fun resetNotificationBuilder() {
        cachedBuilder = null
    }

    private suspend fun notificationBuilder(): NotificationCompat.Builder {
        if (cachedBuilder == null) {
            cachedBuilder = createBettboxNotificationBuilder().await()
        }
        return cachedBuilder!!
    }

    @SuppressLint("ForegroundServiceType")
    override suspend fun startForeground(title: String, content: String) {
        LogUtils.d(LogModule.SERVICE, "=== Starting Foreground Service ===")
        LogUtils.v(LogModule.SERVICE, "Notification params: title='$title', content='$content'")
        
        ensureNotificationChannel()
        val safeTitle = if (title.isBlank()) "Bettbox" else title
        val safeContent = content.trim()
        val builder = notificationBuilder()
        val notification = if (safeContent.isBlank()) {
            builder.setContentTitle(safeTitle).setContentText(null).build()
        } else {
            val separator = " ︙ "
            val combinedText = "$safeTitle$separator$safeContent"
            val spannable = android.text.SpannableString(combinedText)
            val startIndex = safeTitle.length + separator.length
            if (startIndex < combinedText.length) {
                spannable.setSpan(
                    android.text.style.RelativeSizeSpan(0.80f),
                    startIndex,
                    combinedText.length,
                    android.text.Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
                )
            }
            builder.setContentTitle(spannable).setContentText(null).build()
        }

        // Android 14+ SPECIAL_USE
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            try {
                LogUtils.v(LogModule.SERVICE, "Starting foreground with SPECIAL_USE type (Android 14+)")
                startForeground(
                    GlobalState.NOTIFICATION_ID,
                    notification,
                    android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
                )
            } catch (e: Exception) {
                LogUtils.w(LogModule.SERVICE, "SPECIAL_USE failed, trying DATA_SYNC fallback", e)
                // Fallback to dataSync for compatibility
                try {
                    startForeground(
                        GlobalState.NOTIFICATION_ID,
                        notification,
                        android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
                    )
                } catch (e2: Exception) {
                    LogUtils.w(LogModule.SERVICE, "DATA_SYNC failed, using final fallback", e2)
                    // Final fallback without type
                    startForeground(GlobalState.NOTIFICATION_ID, notification)
                }
            }
        } else {
            // Android 13 - dataSync
            LogUtils.v(LogModule.SERVICE, "Starting foreground with default type (Android 13)")
            startForeground(GlobalState.NOTIFICATION_ID, notification)
        }
        
        LogUtils.i(LogModule.SERVICE, "Foreground service started successfully")
    }

    override fun onTrimMemory(level: Int) {
        super.onTrimMemory(level)
        LogUtils.d(LogModule.SERVICE, "onTrimMemory: level=$level")
        GlobalState.getCurrentVPNPlugin()?.requestGc()
    }

    private val binder = LocalBinder()

    inner class LocalBinder : Binder() {
        fun getService(): BettboxVpnService = this@BettboxVpnService

        override fun onTransact(code: Int, data: Parcel, reply: Parcel?, flags: Int): Boolean {
            try {
                val isSuccess = super.onTransact(code, data, reply, flags)
                if (!isSuccess) {
                    LogUtils.w(LogModule.SERVICE, "Binder transaction failed, stopping tile plugin")
                    CoroutineScope(Dispatchers.Main).launch {
                        GlobalState.getCurrentTilePlugin()?.handleStop()
                    }
                }
                return isSuccess
            } catch (e: RemoteException) {
                LogUtils.e(LogModule.SERVICE, "Binder transaction exception", e)
                throw e
            }
        }
    }

    override fun onBind(intent: Intent): IBinder {
        LogUtils.d(LogModule.SERVICE, "onBind: ${intent.action}")
        return binder
    }

    override fun onUnbind(intent: Intent?): Boolean {
        LogUtils.d(LogModule.SERVICE, "onUnbind")
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        LogUtils.i(LogModule.SERVICE, "=== onDestroy: VPN Service Destroying ===")
        stop()
        super.onDestroy()
    }
}
