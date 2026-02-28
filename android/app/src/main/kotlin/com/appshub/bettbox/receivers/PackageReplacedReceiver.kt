package com.appshub.bettbox.receivers

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.appshub.bettbox.GlobalState

class PackageReplacedReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "PackageReplacedReceiver"
        private const val PREFS_NAME = "FlutterSharedPreferences"

        private const val KEY_VPN_RUNNING = "flutter.is_vpn_running"
        private const val KEY_TUN_RUNNING = "flutter.is_tun_running"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_MY_PACKAGE_REPLACED) return

        Log.i(TAG, "Self package replaced, performing full state reset")

        // 1. Reset native layer state first
        try {
            Log.d(TAG, "Resetting GlobalState...")
            GlobalState.resetState()
            Log.i(TAG, "GlobalState reset completed")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to reset GlobalState", e)
        }

        // 2. Clear SharedPreferences flags
        try {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            prefs.edit()
                .putBoolean(KEY_VPN_RUNNING, false)
                .putBoolean(KEY_TUN_RUNNING, false)
                .apply()
            Log.i(TAG, "SharedPreferences flags cleared successfully")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to clear VPN state flags", e)
        }

        Log.i(TAG, "Package replaced state reset completed")
    }
}
