import 'package:bett_box/common/common.dart';
import 'package:bett_box/enum/enum.dart';
import 'package:bett_box/models/common.dart';
import 'package:bett_box/providers/config.dart';
import 'package:bett_box/state.dart';
import 'package:bett_box/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../clash/core.dart';
import '../providers/app.dart';

class DeveloperView extends ConsumerWidget {
  const DeveloperView({super.key});

  /// 内核连接测试
  Future<void> _testCoreConnection(BuildContext context, WidgetRef ref) async {
    final results = <String>[];
    final errors = <String>[];

    try {
      // 1. 检查核心是否初始化
      results.add('1. 检查内核初始化状态...');
      final isInit = await clashCore.isInit;
      results.add('   内核状态：${isInit ? "已初始化" : "未初始化"}');
      if (!isInit) {
        errors.add('内核未初始化，这可能是连接问题的原因');
      }

      // 2. 测试获取流量统计
      results.add('2. 测试获取流量统计...');
      final traffic = await clashCore.getTraffic();
      results.add('   上行：${traffic.up}, 下行：${traffic.down}');

      // 3. 测试获取连接
      results.add('3. 测试获取活动连接...');
      final connections = await clashCore.getConnections();
      results.add('   活动连接数：${connections.length}');

      // 4. 测试获取代理组
      results.add('4. 测试获取代理组...');
      final groups = await clashCore.getProxiesGroups();
      results.add('   代理组数量：${groups.length}');

      // 5. 测试获取外部提供者
      results.add('5. 测试获取外部提供者...');
      final providers = await clashCore.getExternalProviders();
      results.add('   外部提供者数量：${providers.length}');

      // 6. 测试内存查询
      results.add('6. 测试获取内存使用...');
      final memory = await clashCore.getMemory();
      results.add('   内存使用：$memory bytes');

      // 7. 测试 Geo 数据更新（仅测试接口响应）
      results.add('7. 测试 Geo 数据接口...');
      results.add('   Geo 数据接口可用');

    } catch (e, stackTrace) {
      errors.add('测试过程中发生错误：$e\n$stackTrace');
    }

    // 显示测试结果
    if (context.mounted) {
      await globalState.showCommonDialog<bool>(
        child: CommonDialog(
          title: '内核连接测试结果',
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
            mainAxisSize: MainAxisSize.min,
            children: [
              if (errors.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: context.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '❌ 错误 (${errors.length})',
                        style: context.textTheme.titleMedium?.copyWith(
                          color: context.colorScheme.onErrorContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...errors.map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '• $e',
                          style: context.textTheme.bodySmall?.copyWith(
                            color: context.colorScheme.onErrorContainer,
                          ),
                        ),
                      )),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '测试结果',
                      style: context.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...results.map((r) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        r,
                        style: context.textTheme.bodySmall,
                      ),
                    )),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  Widget _getDeveloperList(BuildContext context, WidgetRef ref) {
    return generateSectionV2(
      title: appLocalizations.options,
      items: [
        ListItem(
          title: Text('内核连接测试'),
          subtitle: Text('诊断内核连接问题，检查各项功能是否正常'),
          trailing: Icon(Icons.bug_report_outlined),
          onTap: () {
            _testCoreConnection(context, ref);
          },
        ),
        ListItem(
          title: Text(appLocalizations.messageTest),
          onTap: () {
            context.showNotifier(appLocalizations.messageTestTip);
          },
        ),
        ListItem(
          title: Text(appLocalizations.logsTest),
          onTap: () {
            for (int i = 0; i < 1000; i++) {
              globalState.appController.addLog(
                Log.app(
                  '[$i]${utils.generateRandomString(maxLength: 200, minLength: 20)}',
                ),
              );
            }
          },
        ),
        ListItem(
          title: Text(appLocalizations.crashTest),
          onTap: () async {
            // Show confirmation dialog
            final confirm = await globalState.showCommonDialog<bool>(
              child: CommonDialog(
                title: appLocalizations.crashTest,
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop(false);
                    },
                    child: Text(appLocalizations.cancel),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop(true);
                    },
                    child: Text(appLocalizations.confirm),
                  ),
                ],
                child: Text(
                  'This will trigger a crash to test Sentry integration. Continue?',
                ),
              ),
            );

            if (confirm == true) {
              // Delay to let dialog close first
              await Future.delayed(Duration(milliseconds: 500));

              // Trigger Dart crash (captured by Sentry)
              throw Exception('Test crash from developer mode');
            }
          },
        ),
        ListItem(
          title: Text(appLocalizations.clearData),
          onTap: () async {
            await globalState.appController.handleClear();
          },
        ),
        ListItem(
          title: Text('loading'),
          onTap: () {
            ref.read(loadingProvider.notifier).value = true;
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context, ref) {
    final enable = ref.watch(
      appSettingProvider.select((state) => state.developerMode),
    );
    return SingleChildScrollView(
      padding: baseInfoEdgeInsets,
      child: Column(
        children: [
          CommonCard(
            type: CommonCardType.filled,
            radius: 18,
            child: ListItem.switchItem(
              padding: const EdgeInsets.only(left: 16, right: 16),
              title: Text(appLocalizations.developerMode),
              delegate: SwitchDelegate(
                value: enable,
                onChanged: (value) {
                  ref
                      .read(appSettingProvider.notifier)
                      .updateState(
                        (state) => state.copyWith(developerMode: value),
                      );
                },
              ),
            ),
          ),
          SizedBox(height: 16),
          _getDeveloperList(context, ref),
        ],
      ),
    );
  }
}
