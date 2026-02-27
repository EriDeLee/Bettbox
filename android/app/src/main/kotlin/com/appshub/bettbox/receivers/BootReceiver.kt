package com.appshub.bettbox.receivers

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.appshub.bettbox.MainActivity

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
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) {
            return
        }

        Log.d(TAG, "Device boot completed, checking autoLaunch setting")

        try {
            // Read settings from SharedPreferences
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            
            // Clear VPN running flags on boot to ensure a clean state
            Log.i(TAG, "Clearing VPN running state flags on boot")
            prefs.edit()
                .putBoolean(KEY_VPN_RUNNING, false)
                .putBoolean(KEY_TUN_RUNNING, false)
                .apply()
            
            val autoLaunch = prefs.getBoolean(AUTO_LAUNCH_KEY, false)
            Log.d(TAG, "AutoLaunch setting: $autoLaunch")

            if (autoLaunch) {
                Log.d(TAG, "AutoLaunch enabled, starting MainActivity")
                
                // Launch the main activity
                val launchIntent = Intent(context, MainActivity::class.java).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
                }
                
                context.startActivity(launchIntent)
                
                Log.d(TAG, "MainActivity launch request sent")
            } else {
                Log.d(TAG, "AutoLaunch disabled, skipping app launch")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error in BootReceiver", e)
        }
    }
}
