package com.appshub.bettbox

import android.os.SystemClock
import androidx.lifecycle.MutableLiveData
import com.appshub.bettbox.plugins.AppPlugin
import com.appshub.bettbox.plugins.TilePlugin
import com.appshub.bettbox.plugins.VpnPlugin
import com.appshub.bettbox.util.LogModule
import com.appshub.bettbox.util.LogUtils
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

enum class RunState {
    START,
    PENDING,
    STOP
}


object GlobalState {
    companion object {
        private const val TAG = "GlobalState"
    }
    
    val runLock = ReentrantLock()

    const val NOTIFICATION_CHANNEL = "Bettbox"

    const val NOTIFICATION_ID = 1

    private const val TOGGLE_DEBOUNCE_MS = 1000L
    @Volatile
    private var lastToggleAt = 0L

    @Volatile
    var currentRunState: RunState = RunState.STOP
        private set

    val runState: MutableLiveData<RunState> = MutableLiveData<RunState>(RunState.STOP)

    fun updateRunState(newState: RunState) {
        LogUtils.d(LogModule.GLOBAL, "updateRunState: ${currentRunState} -> $newState")
        currentRunState = newState
        try {
            if (android.os.Looper.myLooper() == android.os.Looper.getMainLooper()) {
                runState.value = newState
            } else {
                runState.postValue(newState)
            }
        } catch (e: Exception) {
            LogUtils.e(LogModule.GLOBAL, "Failed to post runState update", e)
            runState.postValue(newState)
        }
    }
    var flutterEngine: FlutterEngine? = null
    private var serviceEngine: FlutterEngine? = null

    // Smart Auto Stop state - when true, VPN was stopped by smart auto stop feature
    @Volatile
    var isSmartStopped: Boolean = false

    fun getCurrentAppPlugin(): AppPlugin? {
        val currentEngine = if (flutterEngine != null) flutterEngine else serviceEngine
        val plugin = currentEngine?.plugins?.get(AppPlugin::class.java) as AppPlugin?
        LogUtils.v(LogModule.GLOBAL, "getCurrentAppPlugin: ${if (plugin != null) "found" else "null"} (flutterEngine=${flutterEngine != null}, serviceEngine=${serviceEngine != null})")
        return plugin
    }

    fun syncStatus() {
        LogUtils.d(LogModule.GLOBAL, "syncStatus: Syncing VPN status with Flutter")
        CoroutineScope(Dispatchers.Default).launch {
            val status = try {
                VpnPlugin.getStatus() ?: false
            } catch (e: Exception) {
                LogUtils.e(LogModule.GLOBAL, "Failed to get VPN status", e)
                false
            }
            withContext(Dispatchers.Main){
                val newState = if (status) RunState.START else RunState.STOP
                LogUtils.i(LogModule.GLOBAL, "syncStatus: Status synced - $newState")
                updateRunState(newState)
            }
        }
    }

    suspend fun getText(text: String): String {
        return getCurrentAppPlugin()?.getText(text) ?: ""
    }

    fun getCurrentTilePlugin(): TilePlugin? {
        val currentEngine = if (flutterEngine != null) flutterEngine else serviceEngine
        val plugin = currentEngine?.plugins?.get(TilePlugin::class.java) as TilePlugin?
        LogUtils.v(LogModule.GLOBAL, "getCurrentTilePlugin: ${if (plugin != null) "found" else "null"}")
        return plugin
    }

    fun getCurrentVPNPlugin(): VpnPlugin? {
        val plugin = serviceEngine?.plugins?.get(VpnPlugin::class.java) as VpnPlugin?
        LogUtils.v(LogModule.GLOBAL, "getCurrentVPNPlugin: ${if (plugin != null) "found" else "null"}")
        return plugin
    }

    fun handleToggle() {
        LogUtils.i(LogModule.GLOBAL, "=== handleToggle ===")
        if (!acquireToggleSlot()) {
            LogUtils.w(LogModule.GLOBAL, "handleToggle: Debounced, ignoring")
            return
        }
        val starting = handleStart(skipDebounce = true)
        if (!starting) {
            LogUtils.d(LogModule.GLOBAL, "handleToggle: Start failed, stopping")
            handleStop(skipDebounce = true)
        }
    }

    fun handleStart(skipDebounce: Boolean = false): Boolean {
        LogUtils.i(LogModule.GLOBAL, "=== handleStart ===")
        if (!skipDebounce && !acquireToggleSlot()) {
            LogUtils.w(LogModule.GLOBAL, "handleStart: Debounced, ignoring")
            return false
        }
        // Allow attempting start even if state is START, to recover from inconsistent states.
        // It will transition to PENDING and then re-evaluate.
        LogUtils.d(LogModule.GLOBAL, "Updating run state to PENDING")
        updateRunState(RunState.PENDING)
        runLock.lock()
        try {
            val tilePlugin = getCurrentTilePlugin()
            if (tilePlugin != null) {
                LogUtils.d(LogModule.GLOBAL, "TilePlugin exists, calling handleStart")
                tilePlugin.handleStart()
            } else {
                LogUtils.d(LogModule.GLOBAL, "TilePlugin is null, initializing service engine")
                initServiceEngine()
            }
        } finally {
            runLock.unlock()
        }
        LogUtils.i(LogModule.GLOBAL, "=== handleStart Completed ===")
        return true
    }

    fun handleStop(skipDebounce: Boolean = false) {
        LogUtils.i(LogModule.GLOBAL, "=== handleStop ===")
        if (!skipDebounce && !acquireToggleSlot()) {
            LogUtils.w(LogModule.GLOBAL, "handleStop: Debounced, ignoring")
            return
        }
        if (currentRunState == RunState.START || currentRunState == RunState.PENDING) {
            LogUtils.d(LogModule.GLOBAL, "Updating run state to PENDING")
            updateRunState(RunState.PENDING)
            runLock.lock()
            try {
                LogUtils.d(LogModule.GLOBAL, "Getting TilePlugin and calling handleStop")
                getCurrentTilePlugin()?.handleStop()
            } finally {
                runLock.unlock()
            }
        } else {
            LogUtils.w(LogModule.GLOBAL, "handleStop: Invalid state ${currentRunState}, skipping")
        }
        LogUtils.i(LogModule.GLOBAL, "=== handleStop Completed ===")
    }

    private fun acquireToggleSlot(): Boolean {
        val now = SystemClock.elapsedRealtime()
        synchronized(this) {
            if (now - lastToggleAt < TOGGLE_DEBOUNCE_MS) {
                LogUtils.v(LogModule.GLOBAL, "acquireToggleSlot: Debounced (${now - lastToggleAt}ms < ${TOGGLE_DEBOUNCE_MS}ms)")
                return false
            }
            lastToggleAt = now
            LogUtils.v(LogModule.GLOBAL, "acquireToggleSlot: Acquired")
            return true
        }
    }

    fun handleTryDestroy() {
        LogUtils.d(LogModule.GLOBAL, "handleTryDestroy: flutterEngine=${flutterEngine != null}")
        if (flutterEngine == null) {
            LogUtils.d(LogModule.GLOBAL, "handleTryDestroy: Destroying service engine")
            destroyServiceEngine()
        }
    }

    fun destroyServiceEngine() {
        LogUtils.i(LogModule.GLOBAL, "=== destroyServiceEngine ===")
        runLock.withLock {
            serviceEngine?.destroy()
            serviceEngine = null
            LogUtils.d(LogModule.GLOBAL, "Service engine destroyed")
        }
    }

    fun initServiceEngine() {
        LogUtils.i(LogModule.GLOBAL, "=== initServiceEngine ===")
        if (serviceEngine != null) {
            LogUtils.d(LogModule.GLOBAL, "Service engine already exists, skipping")
            return
        }
        LogUtils.d(LogModule.GLOBAL, "Destroying any existing service engine")
        destroyServiceEngine()
        runLock.withLock {
            LogUtils.d(LogModule.GLOBAL, "Creating new FlutterEngine for service")
            serviceEngine = FlutterEngine(BettboxApplication.getAppContext())
            serviceEngine?.plugins?.add(VpnPlugin)
            serviceEngine?.plugins?.add(AppPlugin())
            serviceEngine?.plugins?.add(TilePlugin())
            LogUtils.d(LogModule.GLOBAL, "Plugins registered: VpnPlugin, AppPlugin, TilePlugin")
            
            val vpnService = DartExecutor.DartEntrypoint(
                FlutterInjector.instance().flutterLoader().findAppBundlePath(),
                "_service"
            )
            val args = if (flutterEngine == null) listOf("quick") else null
            LogUtils.d(LogModule.GLOBAL, "Executing Dart entrypoint: _service, args=${args ?: "null"}")
            serviceEngine?.dartExecutor?.executeDartEntrypoint(
                vpnService,
                args
            )
            LogUtils.i(LogModule.GLOBAL, "=== initServiceEngine Completed ===")
        }
    }
}


