import 'package:bett_box/common/common.dart';
import 'package:bett_box/enum/enum.dart';
import 'package:bett_box/providers/providers.dart';
import 'package:bett_box/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../widgets/widgets.dart';

class LogsView extends ConsumerStatefulWidget {
  const LogsView({super.key});

  @override
  ConsumerState<LogsView> createState() => _LogsViewState();
}

class _LogsViewState extends ConsumerState<LogsView> {
  final _logsStateNotifier = ValueNotifier<LogsState>(LogsState());
  late ScrollController _scrollController;

  List<Log> _logs = [];
  
  // 调试模式状态
  bool _debugMode = false;
  LogLevel _minLogLevel = LogLevel.verbose;
  Set<LogModule> _enabledModules = {};

  @override
  void initState() {
    super.initState();
    _logs = globalState.appState.logs.list;
    _scrollController = ScrollController(
      initialScrollOffset: _logs.length * LogItem.height,
    );
    _logsStateNotifier.value = _logsStateNotifier.value.copyWith(logs: _logs);
    
    // 初始化调试配置
    _debugMode = DebugConfig.verboseMode;
    _minLogLevel = DebugConfig.minLogLevel;
    _enabledModules = Set.from(DebugConfig.enabledModules);
    
    ref.listenManual(logsProvider.select((state) => state.list), (prev, next) {
      if (prev != next) {
        final isEquality = logListEquality.equals(prev, next);
        if (!isEquality) {
          _logs = next;
          updateLogsThrottler();
        }
      }
    });
  }

  List<Widget> _buildActions() {
    return [
      // 调试模式开关
      IconButton(
        onPressed: _toggleDebugMode,
        icon: Icon(
          _debugMode ? Icons.bug_report : Icons.bug_report_outlined,
          color: _debugMode ? context.colorScheme.primary : null,
        ),
        tooltip: '调试模式',
      ),
      // 日志级别过滤
      IconButton(
        onPressed: _handleLogLevelSettings,
        icon: const Icon(Icons.filter_list_outlined),
        tooltip: '日志级别过滤',
      ),
      ValueListenableBuilder(
        valueListenable: _logsStateNotifier,
        builder: (_, state, _) {
          return IconButton(
            style: state.autoScrollToEnd
                ? ButtonStyle(
                    backgroundColor: WidgetStatePropertyAll(
                      context.colorScheme.secondaryContainer,
                    ),
                  )
                : null,
            onPressed: () {
              _logsStateNotifier.value = _logsStateNotifier.value.copyWith(
                autoScrollToEnd: !_logsStateNotifier.value.autoScrollToEnd,
              );
            },
            icon: const Icon(Icons.vertical_align_top_outlined),
          );
        },
      ),
      InkWell(
        onTap: _handleExport,
        onLongPress: _handleClearLogs,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: const Icon(Icons.save_as_outlined, size: 24),
        ),
      ),
    ];
  }

  void _toggleDebugMode() {
    setState(() {
      _debugMode = !_debugMode;
      DebugConfig.verboseMode = _debugMode;
    });
    commonPrint.info('调试模式已${_debugMode ? '开启' : '关闭'}', module: LogModule.app);
  }

  void _handleClearLogs() {
    ref.read(logsProvider.notifier).clearLogs();
  }

  Future<void> _handleLogLevelSettings() async {
    final selectedLevel = await globalState.showCommonDialog<LogLevel>(
      child: OptionsDialog<LogLevel>(
        title: '日志级别过滤',
        options: LogLevel.values,
        value: _minLogLevel,
        textBuilder: (logLevel) => '${logLevel.displayName} - ${_getLevelDesc(logLevel)}',
      ),
    );

    if (selectedLevel != null && selectedLevel != _minLogLevel) {
      setState(() {
        _minLogLevel = selectedLevel;
        DebugConfig.minLogLevel = selectedLevel;
      });
    }
  }

  String _getLevelDesc(LogLevel level) {
    return switch (level) {
      LogLevel.verbose => '最详细',
      LogLevel.debug => '调试信息',
      LogLevel.info => '一般信息',
      LogLevel.warning => '警告',
      LogLevel.error => '错误',
      LogLevel.silent => '静默',
    };
  }

  void _onSearch(String value) {
    _logsStateNotifier.value = _logsStateNotifier.value.copyWith(query: value);
  }

  void _onKeywordsUpdate(List<String> keywords) {
    _logsStateNotifier.value = _logsStateNotifier.value.copyWith(
      keywords: keywords,
    );
  }

  @override
  void dispose() {
    _logsStateNotifier.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _handleExport() async {
    final res = await globalState.appController.safeRun<bool>(
      () async {
        return await globalState.appController.exportLogs();
      },
      needLoading: true,
      title: appLocalizations.exportLogs,
    );
    if (res != true) return;
    globalState.showMessage(
      title: appLocalizations.tip,
      message: TextSpan(text: appLocalizations.exportSuccess),
    );
  }

  void updateLogsThrottler() {
    throttler.call(FunctionTag.logs, () {
      if (!mounted) {
        return;
      }
      final isEquality = logListEquality.equals(
        _logs,
        _logsStateNotifier.value.logs,
      );
      if (isEquality) {
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _logsStateNotifier.value = _logsStateNotifier.value.copyWith(
            logs: _logs,
          );
        }
      });
    }, duration: commonDuration);
  }

  @override
  Widget build(BuildContext context) {
    return CommonScaffold(
      actions: [
        IconButton(
          onPressed: _handleLogLevelSettings,
          icon: const Icon(Icons.settings_outlined),
          tooltip: appLocalizations.logLevel,
        ),
        ..._buildActions(),
      ],
      onKeywordsUpdate: _onKeywordsUpdate,
      searchState: AppBarSearchState(onSearch: _onSearch),
      title: appLocalizations.logs,
      body: ValueListenableBuilder<LogsState>(
        valueListenable: _logsStateNotifier,
        builder: (context, state, _) {
          final logs = state.list;
          if (logs.isEmpty) {
            return NullStatus(
              label: appLocalizations.nullTip(appLocalizations.logs),
            );
          }
          final items = logs
              .map<Widget>(
                (log) => LogItem(
                  key: Key(log.dateTime),
                  log: log,
                  onClick: (value) {
                    context.commonScaffoldState?.addKeyword(value);
                  },
                ),
              )
              .separated(const Divider(height: 0))
              .toList();
          return Align(
            alignment: Alignment.topCenter,
            child: ScrollToEndBox(
              onCancelToEnd: () {
                _logsStateNotifier.value = _logsStateNotifier.value.copyWith(
                  autoScrollToEnd: false,
                );
              },
              controller: _scrollController,
              enable: state.autoScrollToEnd,
              dataSource: logs,
              child: CommonScrollBar(
                controller: _scrollController,
                child: ListView.builder(
                  physics: NextClampingScrollPhysics(),
                  reverse: true,
                  shrinkWrap: true,
                  controller: _scrollController,
                  itemBuilder: (_, index) {
                    return items[index];
                  },
                  itemExtentBuilder: (index, _) {
                    if (index.isOdd) {
                      return 0;
                    }
                    return LogItem.height;
                  },
                  itemCount: items.length,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class LogItem extends StatelessWidget {
  final Log log;
  final Function(String)? onClick;

  static double get height {
    final measure = globalState.measure;
    return measure.bodyLargeHeight * 2 +
        8 +
        24 +
        globalState.measure.labelMediumHeight +
        16 +
        16;
  }

  const LogItem({super.key, required this.log, this.onClick});

  /// 从日志 payload 中提取模块标签
  String? _extractModule(String payload) {
    // 格式：[MODULE][LEVEL] message
    final moduleMatch = RegExp(r'\[([A-Z]+)\]\[([A-Z]+)\]').firstMatch(payload);
    if (moduleMatch != null) {
      return moduleMatch.group(1);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final module = _extractModule(log.payload);
    
    return ListItem(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      onTap: () {
        globalState.showCommonDialog(child: LogDetailDialog(log: log));
      },
      title: SizedBox(
        height: globalState.measure.bodyLargeHeight * 2,
        child: Text(
          log.payload,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: context.textTheme.bodyLarge?.copyWith(
            color: log.logLevel.color,
          ),
        ),
      ),
      subtitle: Column(
        children: [
          SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  // 模块标签
                  if (module != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: _getModuleColor(module, context),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        module,
                        style: context.textTheme.labelSmall?.copyWith(
                          color: context.colorScheme.onPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  // 日志级别标签
                  CommonChip(
                    onPressed: () {
                      if (onClick == null) return;
                      onClick!(log.logLevel.name);
                    },
                    label: log.logLevel.displayName,
                  ),
                ],
              ),
              Text(
                log.dateTime,
                style: context.textTheme.bodySmall?.copyWith(
                  color: context.colorScheme.onSurface.opacity80,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _getModuleColor(String module, BuildContext context) {
    return switch (module) {
      'CORE' => context.colorScheme.primary,
      'LISTENER' => context.colorScheme.secondary,
      'CONFIG' => context.colorScheme.tertiary,
      'CONNECTION' => context.colorScheme.error,
      'PROXY' => context.colorScheme.primaryContainer,
      'TRAFFIC' => context.colorScheme.secondaryContainer,
      'VPN' => context.colorScheme.tertiaryContainer,
      'UI' => Colors.purple.shade300,
      'FFI' => Colors.orange.shade300,
      _ => context.colorScheme.surfaceContainerHighest,
    };
  }
}

class LogDetailDialog extends StatelessWidget {
  final Log log;

  const LogDetailDialog({super.key, required this.log});

  @override
  Widget build(BuildContext context) {
    return CommonDialog(
      title: appLocalizations.details(appLocalizations.log),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop(true);
          },
          child: Text(appLocalizations.confirm),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 6,
        children: [
          SelectableText(
            log.payload,
            style: context.textTheme.bodyLarge?.copyWith(
              color: log.logLevel.color,
            ),
          ),
          SelectableText(
            log.dateTime,
            style: context.textTheme.bodySmall?.copyWith(
              color: context.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
