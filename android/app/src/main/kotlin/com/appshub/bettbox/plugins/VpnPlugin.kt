package com.appshub.bettbox.plugins

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Build
import android.os.IBinder
import androidx.core.content.getSystemService
import com.appshub.bettbox.BettboxApplication
import com.appshub.bettbox.GlobalState
import com.appshub.bettbox.RunState
import com.appshub.bettbox.core.Core
import com.appshub.bettbox.extensions.awaitResult
import com.appshub.bettbox.extensions.resolveDns
import com.appshub.bettbox.models.StartForegroundParams
import com.appshub.bettbox.models.VpnOptions
import com.appshub.bettbox.modules.SuspendModule
import com.appshub.bettbox.services.BaseServiceInterface
import com.appshub.bettbox.services.BettboxService
import com.appshub.bettbox.services.BettboxVpnService
import com.appshub.bettbox.util.LogModule
import com.appshub.bettbox.util.LogUtils
import com.google.gson.Gson
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.net.InetSocketAddress
import kotlin.concurrent.withLock

data object VpnPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var flutterMethodChannel: MethodChannel
    private var bettBoxService: BaseServiceInterface? = null
    private var options: VpnOptions? = null
    private var isBind: Boolean = false
    private lateinit var scope: CoroutineScope
    private var lastStartForegroundParams: StartForegroundParams? = null
    private val uidPageNameMap = mutableMapOf<Int, String>()
    private var suspendModule: SuspendModule? = null

    // Quick Response: Network change debounce
    private var quickResponseEnabled = false
    private var disconnectCount = 0
    private var disconnectWindowStart = 0L
    private val disconnectWindowMs = 5000L // 5s window
    private val maxDisconnectsInWindow = 2
    private var lastNetworkType: Int? = null

    private val connectivity by lazy {
        BettboxApplication.getAppContext().getSystemService<ConnectivityManager>()
    }

    private val connection = object : ServiceConnection {
        override fun onServiceConnected(className: ComponentName, service: IBinder) {
            LogUtils.i(LogModule.VPN, "=== onServiceConnected ===")
            isBind = true
            bettBoxService = when (service) {
                is BettboxVpnService.LocalBinder -> {
                    LogUtils.d(LogModule.VPN, "Connected to BettboxVpnService")
                    service.getService()
                }
                is BettboxService.LocalBinder -> {
                    LogUtils.d(LogModule.VPN, "Connected to BettboxService")
                    service.getService()
                }
                else -> throw Exception("invalid binder")
            }
            handleStartService()
        }

        override fun onServiceDisconnected(arg: ComponentName) {
            LogUtils.w(LogModule.VPN, "=== onServiceDisconnected ===")
            isBind = false
            bettBoxService = null
        }
    }

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        LogUtils.i(LogModule.VPN, "=== onAttachedToEngine ===")
        scope = CoroutineScope(Dispatchers.Default)
        scope.launch {
            LogUtils.d(LogModule.VPN, "Registering network callback")
            registerNetworkCallback()
        }
        flutterMethodChannel = MethodChannel(flutterPluginBinding.binaryMessenger, "vpn")
        flutterMethodChannel.setMethodCallHandler(this)

        // Rebind if VPN running but connection lost
        if (GlobalState.currentRunState == RunState.START && bettBoxService == null) {
            LogUtils.w(LogModule.VPN, "VPN is running but service connection lost, rebinding...")
            // Rebind with saved options
            if (options != null) {
                LogUtils.d(LogModule.VPN, "Rebinding service with saved options")
                bindService()
            } else {
                LogUtils.e(LogModule.VPN, "Cannot rebind: options is null")
            }
        }
    }

    override fun onDetachedFromEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        LogUtils.i(LogModule.VPN, "=== onDetachedFromEngine ===")
        unRegisterNetworkCallback()
        flutterMethodChannel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        LogUtils.v(LogModule.VPN, "onMethodCall: ${call.method}")
        when (call.method) {
            "start" -> {
                try {
                    val data = call.argument<String>("data")
                    if (data == null) {
                        LogUtils.e(LogModule.VPN, "start: data parameter is null")
                        result.error("INVALID_ARGUMENT", "data parameter is required", null)
                        return
                    }
                    LogUtils.d(LogModule.VPN, "start: parsing VpnOptions")
                    val vpnOptions = Gson().fromJson(data, VpnOptions::class.java)
                    LogUtils.i(LogModule.VPN, "start: VPN start requested")
                    result.success(handleStart(vpnOptions))
                } catch (e: Exception) {
                    LogUtils.e(LogModule.VPN, "Failed to start VPN: ${e.message}", e)
                    result.error("PARSE_ERROR", "Failed to parse VpnOptions: ${e.message}", null)
                }
            }

            "stop" -> {
                LogUtils.i(LogModule.VPN, "stop: VPN stop requested")
                handleStop()
                result.success(true)
            }

            "getLocalIpAddresses" -> {
                LogUtils.v(LogModule.VPN, "getLocalIpAddresses called")
                result.success(getLocalIpAddresses())
            }

            "setSmartStopped" -> {
                val value = call.argument<Boolean>("value") ?: false
                LogUtils.d(LogModule.VPN, "setSmartStopped: $value")
                GlobalState.isSmartStopped = value
                result.success(true)
            }

            "isSmartStopped" -> {
                result.success(GlobalState.isSmartStopped)
            }

            "smartStop" -> {
                LogUtils.i(LogModule.VPN, "smartStop: Smart stop requested")
                handleSmartStop()
                result.success(true)
            }

            "smartResume" -> {
                LogUtils.i(LogModule.VPN, "smartResume: Smart resume requested")
                val data = call.argument<String>("data")
                result.success(handleSmartResume(Gson().fromJson(data, VpnOptions::class.java)))
            }

            "setQuickResponse" -> {
                quickResponseEnabled = call.argument<Boolean>("enabled") ?: false
                LogUtils.d(LogModule.VPN, "setQuickResponse: enabled=$quickResponseEnabled")
                result.success(true)
            }

            else -> {
                LogUtils.w(LogModule.VPN, "Unknown method: ${call.method}")
                result.notImplemented()
            }
        }
    }
    
    fun setQuickResponse(enabled: Boolean) {
        quickResponseEnabled = enabled
    }

    /**
     * Get local IP addresses from all non-VPN networks.
     * This is more reliable than connectivity_plus when VPN is running.
     */
    fun getLocalIpAddresses(): List<String> {
        val ipAddresses = mutableListOf<String>()
        try {
            for (network in networks) {
                val linkProperties = connectivity?.getLinkProperties(network) ?: continue
                val addresses = linkProperties?.linkAddresses ?: continue
                for (linkAddress in addresses) {
                    val address = linkAddress.address
                    if (address != null && !address.isLoopbackAddress) {
                        val hostAddress = address.hostAddress
                        if (hostAddress != null && !hostAddress.contains(":")) {
                            // Only IPv4 addresses
                            ipAddresses.add(hostAddress)
                        }
                    }
                }
            }
        } catch (e: Exception) {
            android.util.Log.e("VpnPlugin", "getLocalIpAddresses error: ${e.message}")
        }
        return ipAddresses
    }

    fun handleStart(options: VpnOptions): Boolean {
        LogUtils.i(LogModule.VPN, "=== handleStart ===")
        LogUtils.d(LogModule.VPN, "Options: enable=${options.enable}, dns=${options.dnsServerAddress}")
        onUpdateNetwork();
        if (options.enable != this.options?.enable) {
            LogUtils.d(LogModule.VPN, "Enable mode changed, resetting service")
            this.bettBoxService = null
        }
        this.options = options
        when (options.enable) {
            true -> {
                LogUtils.d(LogModule.VPN, "Starting VPN mode")
                handleStartVpn()
            }
            false -> {
                LogUtils.d(LogModule.VPN, "Starting service mode")
                handleStartService()
            }
        }
        return true
    }

    private fun handleStartVpn() {
        LogUtils.i(LogModule.VPN, "=== handleStartVpn ===")
        val plugin = GlobalState.getCurrentAppPlugin()
        if (plugin == null) {
            LogUtils.e(LogModule.VPN, "handleStartVpn: AppPlugin is null")
            GlobalState.updateRunState(RunState.STOP)
            return
        }

        LogUtils.d(LogModule.VPN, "Requesting VPN permission")
        plugin.requestVpnPermission {
            LogUtils.i(LogModule.VPN, "VPN permission granted, proceeding")
            handleStartService()
        }

        // Safety check: if after 5 seconds still PENDING, reset to STOP
        scope.launch {
            LogUtils.d(LogModule.VPN, "Starting safety timeout timer (5s)")
            delay(5000)
            if (GlobalState.currentRunState == RunState.PENDING) {
                LogUtils.w(LogModule.VPN, "VPN start timed out in PENDING state, resetting to STOP")
                GlobalState.updateRunState(RunState.STOP)
            }
        }
    }

    fun requestGc() {
        LogUtils.v(LogModule.VPN, "requestGc: Requesting garbage collection")
        flutterMethodChannel.invokeMethod("gc", null)
    }

    val networks = mutableSetOf<Network>()

    fun onUpdateNetwork() {
        val dns = networks.flatMap { network ->
            connectivity?.resolveDns(network) ?: emptyList()
        }.toSet().joinToString(",")
        LogUtils.v(LogModule.VPN, "onUpdateNetwork: DNS=$dns")
        scope.launch {
            withContext(Dispatchers.Main) {
                flutterMethodChannel.invokeMethod("dnsChanged", dns)
            }
        }
    }

    private val callback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) {
            LogUtils.v(LogModule.NETWORK, "NetworkCallback: onAvailable, network=$network")
            networks.add(network)
            onUpdateNetwork()
            handleNetworkChange()
        }

        override fun onLost(network: Network) {
            LogUtils.v(LogModule.NETWORK, "NetworkCallback: onLost, network=$network")
            networks.remove(network)
            onUpdateNetwork()
            handleNetworkChange()
        }
    }

    private val request = NetworkRequest.Builder().apply {
        addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
        addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
        addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_RESTRICTED)
    }.build()

    private fun registerNetworkCallback() {
        LogUtils.d(LogModule.NETWORK, "Registering network callback")
        networks.clear()
        try {
            connectivity?.registerNetworkCallback(request, callback)
            LogUtils.i(LogModule.NETWORK, "Network callback registered")
        } catch (e: Exception) {
            LogUtils.e(LogModule.NETWORK, "Failed to register network callback", e)
        }
    }

    private fun unRegisterNetworkCallback() {
        LogUtils.d(LogModule.NETWORK, "Unregistering network callback")
        try {
            connectivity?.unregisterNetworkCallback(callback)
            LogUtils.i(LogModule.NETWORK, "Network callback unregistered")
        } catch (e: Exception) {
            LogUtils.e(LogModule.NETWORK, "Failed to unregister network callback", e)
        }
        networks.clear()
        onUpdateNetwork()
    }
    
    private fun handleNetworkChange() {
        if (!quickResponseEnabled) {
            LogUtils.v(LogModule.NETWORK, "handleNetworkChange: quickResponse disabled, skipping")
            return
        }

        // Check runState to bypass quick response if not running
        if (GlobalState.currentRunState != RunState.START) {
            LogUtils.v(LogModule.NETWORK, "handleNetworkChange: VPN not running, skipping")
            return
        }

        val currentNetworkType = getCurrentNetworkType()
        if (lastNetworkType == null) {
            lastNetworkType = currentNetworkType
            LogUtils.d(LogModule.NETWORK, "handleNetworkChange: Initial network type=$currentNetworkType")
            return
        }

        // Network type changed (WiFi <-> Mobile)
        if (currentNetworkType != lastNetworkType) {
            LogUtils.i(LogModule.NETWORK, "Network type changed: $lastNetworkType -> $currentNetworkType")
            lastNetworkType = currentNetworkType

            val now = System.currentTimeMillis()

            // Reset window if expired
            if (now - disconnectWindowStart > disconnectWindowMs) {
                LogUtils.d(LogModule.NETWORK, "Network change window expired, resetting counter")
                disconnectWindowStart = now
                disconnectCount = 0
            }

            // Check if within limit
            if (disconnectCount < maxDisconnectsInWindow) {
                disconnectCount++
                LogUtils.i(LogModule.NETWORK, "Quick Response: Network changed, disconnecting ($disconnectCount/$maxDisconnectsInWindow)")
                handleStop()
            } else {
                LogUtils.w(LogModule.NETWORK, "Quick Response: Disconnect limit reached, ignoring")
            }
        } else {
            LogUtils.v(LogModule.NETWORK, "Network type unchanged, skipping")
        }
    }

    private fun getCurrentNetworkType(): Int {
        val activeNetwork = connectivity?.activeNetwork ?: return -1
        val caps = connectivity?.getNetworkCapabilities(activeNetwork) ?: return -1
        val type = when {
            caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> 1
            caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> 2
            else -> 0
        }
        LogUtils.v(LogModule.NETWORK, "getCurrentNetworkType: $type")
        return type
    }

    private suspend fun startForeground() {
        LogUtils.v(LogModule.VPN, "=== startForeground ===")
        val shouldUpdate = GlobalState.runLock.withLock {
            GlobalState.currentRunState == RunState.START || GlobalState.isSmartStopped
        }
        if (!shouldUpdate) {
            LogUtils.v(LogModule.VPN, "startForeground: Should not update, skipping")
            return
        }
        
        val data = try {
            withTimeoutOrNull(1200L) {
                flutterMethodChannel.awaitResult<String>("getStartForegroundParams")
            }
        } catch (e: Exception) {
            LogUtils.e(LogModule.VPN, "getStartForegroundParams timeout: ${e.message}")
            null
        }

        val startForegroundParams = try {
            data?.let { Gson().fromJson(it, StartForegroundParams::class.java) }
        } catch (e: Exception) {
            LogUtils.e(LogModule.VPN, "Failed to parse StartForegroundParams: ${e.message}")
            null
        } ?: lastStartForegroundParams ?: StartForegroundParams(title = "", content = "")

        LogUtils.d(LogModule.VPN, "StartForeground params: title='${startForegroundParams.title}', content='${startForegroundParams.content}'")

        val shouldNotify = GlobalState.runLock.withLock {
            if (lastStartForegroundParams != startForegroundParams) {
                lastStartForegroundParams = startForegroundParams
                true
            } else {
                false
            }
        }
        if (shouldNotify) {
            LogUtils.d(LogModule.VPN, "Notification content changed, updating")
            try {
                bettBoxService?.startForeground(
                    startForegroundParams.title,
                    startForegroundParams.content,
                )
                LogUtils.i(LogModule.VPN, "Foreground notification updated")
            } catch (e: Exception) {
                LogUtils.e(LogModule.VPN, "startForeground error: ${e.message}")
            }
        } else {
            LogUtils.v(LogModule.VPN, "Notification content unchanged, skipping update")
        }
    }

    /**
     * Force update notification icon
     */
    fun updateNotificationIcon() {
        LogUtils.i(LogModule.VPN, "=== updateNotificationIcon ===")
        scope.launch {
            try {
                // Recreate notification for new icon
                lastStartForegroundParams?.let { params ->
                    LogUtils.d(LogModule.VPN, "Recreating notification with params: title='${params.title}'")
                    (bettBoxService as? BettboxService)?.resetNotificationBuilder()
                    (bettBoxService as? BettboxVpnService)?.resetNotificationBuilder()
                    bettBoxService?.startForeground(params.title, params.content)
                    LogUtils.i(LogModule.VPN, "Notification icon updated")
                } ?: run {
                    LogUtils.w(LogModule.VPN, "updateNotificationIcon: lastStartForegroundParams is null")
                }
            } catch (e: Exception) {
                LogUtils.e(LogModule.VPN, "updateNotificationIcon error: ${e.message}")
            }
        }
    }


    suspend fun getStatus(): Boolean? {
        return withContext(Dispatchers.Default) {
            LogUtils.v(LogModule.VPN, "getStatus: Checking VPN status")
            flutterMethodChannel.awaitResult<Boolean>("status", null)
        }
    }

    private fun handleStartService() {
        LogUtils.i(LogModule.VPN, "=== handleStartService ===")
        
        if (bettBoxService == null) {
            LogUtils.d(LogModule.VPN, "bettBoxService is null, binding service...")
            bindService()
            return
        }
        
        GlobalState.runLock.withLock {
            val currentOptions = options
            if (currentOptions == null) {
                LogUtils.e(LogModule.VPN, "Start service failed: options is null")
                GlobalState.updateRunState(RunState.STOP)
                return
            }

            // Always attempt to re-establish the VPN if called, rather than skipping purely on state.
            // This handles cases where state is START but the actual fd/TUN was destroyed.
            LogUtils.d(LogModule.VPN, "Updating run state to START")
            GlobalState.updateRunState(RunState.START)
            lastStartForegroundParams = null

            try {
                LogUtils.i(LogModule.VPN, "Starting VPN service with options...")
                LogUtils.d(LogModule.VPN, "VPN options: enable=${currentOptions.enable}, dns=${currentOptions.dnsServerAddress}")
                val fd = bettBoxService?.start(currentOptions)
                if (fd == null || fd == 0) {
                    LogUtils.e(LogModule.VPN, "Failed to start VPN: fd is null or 0")
                    GlobalState.updateRunState(RunState.STOP)
                    return
                }

                LogUtils.i(LogModule.VPN, "VPN service started successfully, FD: $fd. Starting Go TUN...")
                Core.startTun(
                    fd = fd,
                    protect = this::protect,
                    resolverProcess = this::resolverProcess,
                )
                LogUtils.i(LogModule.VPN, "Go TUN started")
                
                // Update notice on start
                scope.launch {
                    LogUtils.d(LogModule.VPN, "Updating foreground notification")
                    startForeground()
                }
                
                // Install SuspendModule if dozeSuspend is enabled
                if (currentOptions.dozeSuspend == true) {
                    LogUtils.d(LogModule.VPN, "dozeSuspend enabled, installing SuspendModule")
                    suspendModule?.uninstall()
                    suspendModule = SuspendModule(BettboxApplication.getAppContext())
                    suspendModule?.install()
                    LogUtils.i(LogModule.VPN, "SuspendModule installed")
                }
            } catch (e: Exception) {
                LogUtils.e(LogModule.VPN, "Exception during VPN start: ${e.message}", e)
                GlobalState.updateRunState(RunState.STOP)
            }
        }
    }

    private fun protect(fd: Int): Boolean {
        val result = (bettBoxService as? BettboxVpnService)?.protect(fd) == true
        LogUtils.v(LogModule.VPN, "protect: fd=$fd, result=$result")
        return result
    }

    private fun resolverProcess(
        protocol: Int,
        source: InetSocketAddress,
        target: InetSocketAddress,
        uid: Int,
    ): String {
        val nextUid = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            connectivity?.getConnectionOwnerUid(protocol, source, target) ?: -1
        } else {
            uid
        }
        if (nextUid == -1) {
            return ""
        }
        if (!uidPageNameMap.containsKey(nextUid)) {
            uidPageNameMap[nextUid] =
                BettboxApplication.getAppContext().packageManager?.getPackagesForUid(nextUid)
                    ?.first() ?: ""
        }
        return uidPageNameMap[nextUid] ?: ""
    }

    fun handleStop() {
        LogUtils.i(LogModule.VPN, "=== handleStop ===")
        GlobalState.runLock.withLock {
            if (GlobalState.currentRunState == RunState.STOP) {
                LogUtils.v(LogModule.VPN, "Already stopped, skipping")
                return
            }
            LogUtils.d(LogModule.VPN, "Updating run state to STOP")
            GlobalState.updateRunState(RunState.STOP)
            lastStartForegroundParams = null
            
            // Uninstall SuspendModule
            if (suspendModule != null) {
                LogUtils.d(LogModule.VPN, "Uninstalling SuspendModule")
                suspendModule?.uninstall()
                suspendModule = null
            }
            
            // Stop TUN first to clear routes
            LogUtils.i(LogModule.VPN, "Stopping TUN")
            Core.stopTun()
            LogUtils.d(LogModule.VPN, "TUN stopped")
            
            // Then stop service
            LogUtils.i(LogModule.VPN, "Stopping VPN service")
            bettBoxService?.stop()
            LogUtils.d(LogModule.VPN, "VPN service stopped")
            
            GlobalState.handleTryDestroy()
            LogUtils.i(LogModule.VPN, "=== handleStop Completed ===")
        }
    }

    /**
     * Smart stop: Stop the TUN but keep the foreground service running.
     * Used by Smart Auto Stop feature to maintain notification while VPN is paused.
     */
    fun handleSmartStop() {
        LogUtils.i(LogModule.VPN, "=== handleSmartStop ===")
        GlobalState.runLock.withLock {
            if (GlobalState.currentRunState == RunState.STOP) {
                LogUtils.v(LogModule.VPN, "Already stopped, skipping smart stop")
                return
            }
            LogUtils.d(LogModule.VPN, "Updating run state to STOP (smart)")
            GlobalState.updateRunState(RunState.STOP)
            GlobalState.isSmartStopped = true
            LogUtils.d(LogModule.VPN, "isSmartStopped set to true")
            
            // Uninstall SuspendModule
            if (suspendModule != null) {
                LogUtils.d(LogModule.VPN, "Uninstalling SuspendModule")
                suspendModule?.uninstall()
                suspendModule = null
            }
            
            // Stop TUN but keep service running
            LogUtils.i(LogModule.VPN, "Stopping TUN (smart stop)")
            Core.stopTun()
            LogUtils.d(LogModule.VPN, "TUN stopped (smart)")
            
            // Update notification to show "SmartAutoStopServiceRunning"
            scope.launch {
                LogUtils.d(LogModule.VPN, "Updating foreground notification")
                startForeground()
            }
            LogUtils.i(LogModule.VPN, "=== handleSmartStop Completed ===")
        }
    }

    /**
     * Smart resume: Resume VPN from smart-stopped state.
     * Restarts the TUN without rebinding the service.
     */
    fun handleSmartResume(options: VpnOptions): Boolean {
        LogUtils.i(LogModule.VPN, "=== handleSmartResume ===")
        GlobalState.runLock.withLock {
            if (GlobalState.currentRunState == RunState.START) {
                LogUtils.v(LogModule.VPN, "Already running, skipping smart resume")
                return true
            }
            LogUtils.d(LogModule.VPN, "isSmartStopped set to false")
            GlobalState.isSmartStopped = false
            this.options = options

            if (bettBoxService == null) {
                // Service was destroyed, need to rebind
                LogUtils.w(LogModule.VPN, "Service was destroyed, need to rebind")
                bindService()
                return true
            }

            LogUtils.d(LogModule.VPN, "Updating run state to START")
            GlobalState.updateRunState(RunState.START)
            lastStartForegroundParams = null
            
            LogUtils.i(LogModule.VPN, "Starting VPN service")
            val fd = bettBoxService?.start(options)
            Core.startTun(
                fd = fd ?: 0,
                protect = this::protect,
                resolverProcess = this::resolverProcess,
            )
            LogUtils.i(LogModule.VPN, "TUN started")
            
            // Update notification to "Service running"
            scope.launch {
                LogUtils.d(LogModule.VPN, "Updating foreground notification")
                startForeground()
            }
            
            // Install SuspendModule if dozeSuspend is enabled
            if (options.dozeSuspend == true) {
                LogUtils.d(LogModule.VPN, "dozeSuspend enabled, installing SuspendModule")
                suspendModule?.uninstall()
                suspendModule = SuspendModule(BettboxApplication.getAppContext())
                suspendModule?.install()
                LogUtils.i(LogModule.VPN, "SuspendModule installed")
            }
            LogUtils.i(LogModule.VPN, "=== handleSmartResume Completed ===")
            return true
        }
    }

    private fun bindService() {
        LogUtils.i(LogModule.VPN, "=== bindService ===")
        if (isBind) {
            LogUtils.d(LogModule.VPN, "Already bound, unbinding first")
            BettboxApplication.getAppContext().unbindService(connection)
        }
        val intent = when (options?.enable == true) {
            true -> {
                LogUtils.d(LogModule.VPN, "Binding to BettboxVpnService")
                Intent(BettboxApplication.getAppContext(), BettboxVpnService::class.java)
            }
            false -> {
                LogUtils.d(LogModule.VPN, "Binding to BettboxService")
                Intent(BettboxApplication.getAppContext(), BettboxService::class.java)
            }
        }
        LogUtils.i(LogModule.VPN, "Binding service with BIND_AUTO_CREATE")
        BettboxApplication.getAppContext().bindService(intent, connection, Context.BIND_AUTO_CREATE)
    }
}
