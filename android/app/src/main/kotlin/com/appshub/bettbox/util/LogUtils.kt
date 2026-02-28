package com.appshub.bettbox.util

import android.util.Log
import java.text.SimpleDateFormat
import java.util.*

/**
 * 日志模块枚举
 */
enum class LogModule(val tag: String) {
    APP("Bettbox.App"),
    VPN("Bettbox.VPN"),
    SERVICE("Bettbox.Service"),
    CORE("Bettbox.Core"),
    NETWORK("Bettbox.Network"),
    PLUGIN("Bettbox.Plugin"),
    RECEIVER("Bettbox.Receiver"),
    GLOBAL("Bettbox.Global"),
    UI("Bettbox.UI"),
    FFI("Bettbox.FFI")
}

/**
 * 日志级别枚举
 */
enum class LogLevel(val priority: Int) {
    VERBOSE(2),
    DEBUG(3),
    INFO(4),
    WARN(5),
    ERROR(6),
    ASSERT(7),
    NONE(8)
}

/**
 * 统一日志工具类
 *
 * 功能：
 * 1. 统一的日志格式
 * 2. 可配置的日志级别
 * 3. 模块标签过滤
 * 4. 时间戳和线程信息
 * 5. 支持发布版本自动禁用详细日志
 */
object LogUtils {
    // 全局日志级别，发布版本默认为 INFO
    @Volatile
    var minLogLevel: LogLevel = LogLevel.DEBUG  // 默认使用 DEBUG，可通过外部设置
    
    // 是否为 debug 模式（通过外部设置）
    @Volatile
    var isDebugMode: Boolean = true
    
    // 启用的模块（空表示启用所有）
    @Volatile
    private var enabledModules: Set<LogModule> = emptySet()
    
    // 日期格式化
    private val dateFormat = SimpleDateFormat("HH:mm:ss.SSS", Locale.getDefault())
    
    /**
     * 设置启用的模块
     * @param modules 模块列表，空列表表示启用所有模块
     */
    fun setEnabledModules(modules: Collection<LogModule>) {
        enabledModules = modules.toSet()
    }
    
    /**
     * 添加启用的模块
     */
    fun enableModule(module: LogModule) {
        enabledModules = enabledModules + module
    }
    
    /**
     * 禁用模块
     */
    fun disableModule(module: LogModule) {
        enabledModules = enabledModules - module
    }
    
    /**
     * 检查是否应该记录指定模块的日志
     */
    private fun shouldLog(module: LogModule, level: LogLevel): Boolean {
        // 检查日志级别
        if (level.priority < minLogLevel.priority) {
            return false
        }
        
        // 检查模块过滤
        if (enabledModules.isNotEmpty() && module !in enabledModules) {
            return false
        }
        
        return true
    }
    
    /**
     * 获取带时间戳的日志标签
     */
    private fun getTimestamp(): String {
        return dateFormat.format(Date())
    }
    
    /**
     * 获取当前线程信息
     */
    private fun getThreadInfo(): String {
        val thread = Thread.currentThread()
        return "[${thread.name}]"
    }
    
    /**
     * 格式化日志消息
     */
    private fun formatMessage(
        module: LogModule,
        level: LogLevel,
        message: String,
        throwable: Throwable? = null
    ): String {
        val timestamp = getTimestamp()
        val threadInfo = getThreadInfo()
        val levelTag = when (level) {
            LogLevel.VERBOSE -> "V"
            LogLevel.DEBUG -> "D"
            LogLevel.INFO -> "I"
            LogLevel.WARN -> "W"
            LogLevel.ERROR -> "E"
            LogLevel.ASSERT -> "A"
            LogLevel.NONE -> "?"
        }
        
        val baseMessage = "$timestamp $threadInfo [$levelTag/${module.tag}] $message"
        
        return if (throwable != null) {
            "$baseMessage\n${Log.getStackTraceString(throwable)}"
        } else {
            baseMessage
        }
    }
    
    /**
     * 记录日志
     */
    private fun log(module: LogModule, level: LogLevel, message: String, throwable: Throwable? = null) {
        if (!shouldLog(module, level)) return
        
        val tag = module.tag
        val formattedMessage = formatMessage(module, level, message, throwable)
        
        when (level) {
            LogLevel.VERBOSE -> Log.v(tag, formattedMessage, throwable)
            LogLevel.DEBUG -> Log.d(tag, formattedMessage, throwable)
            LogLevel.INFO -> Log.i(tag, formattedMessage, throwable)
            LogLevel.WARN -> Log.w(tag, formattedMessage, throwable)
            LogLevel.ERROR -> Log.e(tag, formattedMessage, throwable)
            LogLevel.ASSERT -> Log.wtf(tag, formattedMessage, throwable)
            LogLevel.NONE -> {}
        }
    }
    
    // ========== 便捷方法 ==========

    fun v(module: LogModule, message: String) {
        log(module, LogLevel.VERBOSE, message)
    }

    fun d(module: LogModule, message: String) {
        log(module, LogLevel.DEBUG, message)
    }

    fun i(module: LogModule, message: String) {
        log(module, LogLevel.INFO, message)
    }

    fun w(module: LogModule, message: String) {
        log(module, LogLevel.WARN, message)
    }
    
    fun w(module: LogModule, message: String, throwable: Throwable?) {
        log(module, LogLevel.WARN, message, throwable)
    }

    fun e(module: LogModule, message: String, throwable: Throwable? = null) {
        log(module, LogLevel.ERROR, message, throwable)
    }
    
    fun e(module: LogModule, throwable: Throwable, message: String = throwable.message ?: "Unknown error") {
        log(module, LogLevel.ERROR, message, throwable)
    }
    
    fun wtf(module: LogModule, message: String, throwable: Throwable? = null) {
        log(module, LogLevel.ASSERT, message, throwable)
    }
    
    /**
     * 记录带异常堆栈的日志
     */
    fun e(module: LogModule, throwable: Throwable, message: String = throwable.message ?: "Unknown error") {
        log(module, LogLevel.ERROR, message, throwable)
    }
    
    /**
     * 记录方法调用日志
     */
    fun methodEnter(module: LogModule, methodName: String) {
        if (minLogLevel.priority <= LogLevel.DEBUG.priority) {
            log(module, LogLevel.DEBUG, "▶ $methodName")
        }
    }
    
    /**
     * 记录方法返回日志
     */
    fun methodExit(module: LogModule, methodName: String, result: Any? = null) {
        if (minLogLevel.priority <= LogLevel.DEBUG.priority) {
            val resultStr = result?.let { " = $it" } ?: ""
            log(module, LogLevel.DEBUG, "◀ $methodName$resultStr")
        }
    }
    
    /**
     * 记录方法异常日志
     */
    fun methodException(module: LogModule, methodName: String, throwable: Throwable) {
        log(module, LogLevel.ERROR, "✗ $methodName", throwable)
    }
    
    /**
     * 打印分隔线
     */
    fun printSeparator(module: LogModule, title: String = "") {
        if (minLogLevel.priority <= LogLevel.INFO.priority) {
            val separator = "═".repeat(50)
            log(module, LogLevel.INFO, if (title.isEmpty()) separator else "$separator $title $separator")
        }
    }
}
