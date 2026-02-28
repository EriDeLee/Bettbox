package com.appshub.bettbox.receivers

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.appshub.bettbox.MainActivity
import com.appshub.bettbox.util.LogModule
import com.appshub.bettbox.util.LogUtils

/**
 * Boot receiver to handle auto-launch functionality on device boot
 *
 * This receiver listens for BOOT_COMPLETED broadcast and launches the app
 * if the user has enabled the autoLaunch setting.
 */
class BootReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "BootReceiver"
        private const val PREFS_NAME = "FlutterSharedPreferences"
        private const val AUTO_LAUNCH_KEY = "flutter.autoLaunch"

        private const val KEY_VPN_RUNNING = "flutter.is_vpn_running"
        private const val KEY_TUN_RUNNING = "flutter.is_tun_running"
    }

    override fun onReceive(context: Context, intent: Intent) {
        LogUtils.i(LogModule.RECEIVER, "=== onReceive: BOOT_COMPLETED ===")
        
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) {
            LogUtils.w(LogModule.RECEIVER, "onReceive: Ignoring non-boot action: ${intent.action}")
            return
        }

        LogUtils.d(LogModule.RECEIVER, "Device boot completed, checking autoLaunch setting")

        try {
            // Read settings from SharedPreferences
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

            // Clear VPN running flags on boot to ensure a clean state
            LogUtils.i(LogModule.RECEIVER, "Clearing VPN running state flags on boot")
            prefs.edit()
                .putBoolean(KEY_VPN_RUNNING, false)
                .putBoolean(KEY_TUN_RUNNING, false)
                .apply()
            LogUtils.d(LogModule.RECEIVER, "VPN state flags cleared")

            val autoLaunch = prefs.getBoolean(AUTO_LAUNCH_KEY, false)
            LogUtils.d(LogModule.RECEIVER, "AutoLaunch setting: $autoLaunch")

            if (autoLaunch) {
                LogUtils.i(LogModule.RECEIVER, "AutoLaunch enabled, starting MainActivity")

                // Launch the main activity
                val launchIntent = Intent(context, MainActivity::class.java).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
                }

                try {
                    context.startActivity(launchIntent)
                    LogUtils.i(LogModule.RECEIVER, "MainActivity launch request sent successfully")
                } catch (e: Exception) {
                    LogUtils.e(LogModule.RECEIVER, "Failed to start MainActivity", e)
                }
            } else {
                LogUtils.d(LogModule.RECEIVER, "AutoLaunch disabled, skipping app launch")
            }
        } catch (e: Exception) {
            LogUtils.e(LogModule.RECEIVER, "Error in BootReceiver", e)
        }
        
        LogUtils.i(LogModule.RECEIVER, "=== onReceive Completed ===")
    }
}
