package com.appshub.bettbox;

import android.app.Application
import android.content.Context
import com.appshub.bettbox.util.LogUtils

class BettboxApplication : Application() {
    companion object {
        private lateinit var instance: BettboxApplication
        fun getAppContext(): Context {
            return instance.applicationContext
        }
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
        
        // Initialize logging system
        LogUtils.init(this)
    }
}
