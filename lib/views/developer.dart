import 'package:bett_box/common/common.dart';
import 'package:bett_box/enum/enum.dart';
import 'package:bett_box/models/common.dart';
import 'package:bett_box/providers/config.dart';
import 'package:bett_box/state.dart';
import 'package:bett_box/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app.dart';

class DeveloperView extends ConsumerWidget {
  const DeveloperView({super.key});

  Widget _getDeveloperList(BuildContext context, WidgetRef ref) {
    return generateSectionV2(
      title: appLocalizations.options,
      items: [
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
