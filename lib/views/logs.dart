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

  @override
  void initState() {
    super.initState();
    _logs = globalState.appState.logs.list;
    _scrollController = ScrollController(
      initialScrollOffset: _logs.length * LogItem.height,
    );
    _logsStateNotifier.value = _logsStateNotifier.value.copyWith(logs: _logs);
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

  void _handleClearLogs() {
    ref.read(logsProvider.notifier).clearLogs();
  }

  Future<void> _handleLogLevelSettings() async {
    final currentLogLevel = ref.read(
      patchClashConfigProvider.select((state) => state.logLevel),
    );

    final selectedLogLevel = await globalState.showCommonDialog<LogLevel>(
      child: OptionsDialog<LogLevel>(
        title: appLocalizations.logLevel,
        options: LogLevel.values,
        value: currentLogLevel,
        textBuilder: (logLevel) => logLevel.name,
      ),
    );

    if (selectedLogLevel != null && selectedLogLevel != currentLogLevel) {
      ref
          .read(patchClashConfigProvider.notifier)
          .updateState((state) => state.copyWith(logLevel: selectedLogLevel));
      // Sync config to core immediately
      globalState.appController.updateClashConfigDebounce();
    }
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

  @override
  Widget build(BuildContext context) {
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
              CommonChip(
                onPressed: () {
                  if (onClick == null) return;
                  onClick!(log.logLevel.name);
                },
                label: log.logLevel.name,
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
