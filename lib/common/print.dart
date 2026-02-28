import 'package:bett_box/enum/enum.dart';
import 'package:bett_box/models/models.dart';
import 'package:bett_box/state.dart';
import 'package:flutter/cupertino.dart';

/// 日志模块标签，用于过滤和分类日志
enum LogModule {
  app('APP'),
  core('CORE'),
  listener('LISTENER'),
  config('CONFIG'),
  connection('CONNECTION'),
  proxy('PROXY'),
  traffic('TRAFFIC'),
  vpn('VPN'),
  ui('UI'),
  ffi('FFI');

  final String label;
  const LogModule(this.label);
}

/// 调试日志配置
class DebugConfig {
  /// 是否启用详细调试模式
  static bool verboseMode = false;

  /// 当前日志级别过滤
  static LogLevel minLogLevel = LogLevel.debug;

  /// 启用的模块（为空表示启用所有模块）
  static Set<LogModule> enabledModules = {};

  /// 是否应该记录某个模块的日志
  static bool shouldLogModule(LogModule module) {
    if (enabledModules.isEmpty) return true;
    return enabledModules.contains(module);
  }

  /// 是否应该记录某个级别的日志
  static bool shouldLogLevel(LogLevel level) {
    return level.shouldShow(minLogLevel);
  }
}

class CommonPrint {
  static CommonPrint? _instance;

  CommonPrint._internal();

  factory CommonPrint() {
    _instance ??= CommonPrint._internal();
    return _instance!;
  }

  /// 记录日志，支持模块和级别
  void log(
    String? text, {
    LogLevel level = LogLevel.info,
    LogModule module = LogModule.app,
  }) {
    // 检查是否应该记录此级别和模块的日志
    if (!DebugConfig.shouldLogLevel(level)) return;
    if (!DebugConfig.shouldLogModule(module)) return;

    // 非 verbose 模式下不记录 verbose 日志
    if (!DebugConfig.verboseMode && level == LogLevel.verbose) return;

    final payload = '[${module.label}][${level.displayName}] $text';
    debugPrint(payload);
    if (!globalState.isInit) {
      return;
    }
    globalState.appController.addLog(Log(
      logLevel: level,
      payload: payload,
      dateTime: DateTime.now().showFull,
    ));
  }

  /// 便捷方法：记录 verbose 级别日志
  void verbose(String text, {LogModule module = LogModule.app}) {
    log(text, level: LogLevel.verbose, module: module);
  }

  /// 便捷方法：记录 debug 级别日志
  void debug(String text, {LogModule module = LogModule.app}) {
    log(text, level: LogLevel.debug, module: module);
  }

  /// 便捷方法：记录 info 级别日志
  void info(String text, {LogModule module = LogModule.app}) {
    log(text, level: LogLevel.info, module: module);
  }

  /// 便捷方法：记录 warning 级别日志
  void warning(String text, {LogModule module = LogModule.app}) {
    log(text, level: LogLevel.warning, module: module);
  }

  /// 便捷方法：记录 error 级别日志
  void error(String text, {LogModule module = LogModule.app}) {
    log(text, level: LogLevel.error, module: module);
  }
}

final commonPrint = CommonPrint();
