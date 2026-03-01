package com.appshub.bettbox.core

import com.appshub.bettbox.util.LogModule
import com.appshub.bettbox.util.LogUtils
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.URL

data object Core {
    private external fun startTun(
        fd: Int,
        cb: TunInterface
    )

    private external fun suspend(suspended: Int)

    private fun parseInetSocketAddress(address: String): InetSocketAddress {
        val url = URL("https://$address")

        return InetSocketAddress(InetAddress.getByName(url.host), url.port)
    }

    fun startTun(
        fd: Int,
        protect: (Int) -> Boolean,
        resolverProcess: (protocol: Int, source: InetSocketAddress, target: InetSocketAddress, uid: Int) -> String
    ) {
        startTun(fd, object : TunInterface {
            override fun protect(fd: Int) {
                protect(fd)
            }

            override fun resolverProcess(
                protocol: Int,
                source: String,
                target: String,
                uid: Int
            ): String {
                return resolverProcess(
                    protocol,
                    parseInetSocketAddress(source),
                    parseInetSocketAddress(target),
                    uid,
                )
            }
        });
    }

    fun suspended(value: Boolean) {
        try {
            LogUtils.d(LogModule.CORE, "suspended called with value: $value")
            suspend(if (value) 1 else 0)
            LogUtils.d(LogModule.CORE, "suspend JNI call completed")
        } catch (e: Exception) {
            LogUtils.e(LogModule.CORE, "Error calling suspend: ${e.message}", e)
        }
    }

    external fun stopTun()

    init {
        System.loadLibrary("core")
    }
}