import 'package:bett_box/common/common.dart';
import 'package:bett_box/enum/enum.dart';
import 'package:bett_box/models/models.dart';
import 'package:bett_box/providers/providers.dart';
import 'package:bett_box/state.dart';
import 'package:bett_box/views/proxies/common.dart';
import 'package:bett_box/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';

class ProxyCard extends StatelessWidget {
  final String groupName;
  final Proxy proxy;
  final GroupType groupType;
  final ProxyCardType type;
  final String? testUrl;

  const ProxyCard({
    super.key,
    required this.groupName,
    required this.testUrl,
    required this.proxy,
    required this.groupType,
    required this.type,
  });

  Future<void> _changeProxy(WidgetRef ref) async {
    final isComputedSelected = groupType.isComputedSelected;
    final isSelector = groupType == GroupType.Selector;
    if (isComputedSelected || isSelector) {
      final currentProxyName = ref.read(getProxyNameProvider(groupName));
      final nextProxyName = switch (isComputedSelected) {
        true => currentProxyName == proxy.name ? '' : proxy.name,
        false => proxy.name,
      };
      final appController = globalState.appController;
      appController.updateCurrentSelectedMap(groupName, nextProxyName);
      appController.changeProxyDebounce(groupName, nextProxyName);
      return;
    }
    globalState.showNotifier(appLocalizations.notSelectedTip);
  }

  @override
  Widget build(BuildContext context) {
    // Isolate repaint
    return RepaintBoundary(
      child: Stack(
        children: [
          Consumer(
            builder: (_, ref, child) {
              final selectedProxyName = ref.watch(
                getSelectedProxyNameProvider(groupName),
              );
              return CommonCard(
                key: key,
                onPressed: () {
                  _changeProxy(ref);
                },
                isSelected: selectedProxyName == proxy.name,
                child: child!,
              );
            },
            // child 不依赖选中状态，不会重建
            child: _ProxyCardContent(
              proxy: proxy,
              type: type,
              testUrl: testUrl,
            ),
          ),
          if (groupType.isComputedSelected)
            Positioned(
              top: 0,
              right: 0,
              child: _ProxyComputedMark(groupName: groupName, proxy: proxy),
            ),
        ],
      ),
    );
  }
}

// Extract as separate component
class _ProxyCardContent extends StatelessWidget {
  final Proxy proxy;
  final ProxyCardType type;
  final String? testUrl;

  const _ProxyCardContent({
    required this.proxy,
    required this.type,
    required this.testUrl,
  });

  @override
  Widget build(BuildContext context) {
    final measure = globalState.measure;
    return Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ProxyNameText(proxy: proxy, type: type),
          const SizedBox(height: 8),
          if (type == ProxyCardType.expand) ...[
            SizedBox(
              height: measure.bodySmallHeight,
              child: _ProxyDesc(proxy: proxy),
            ),
            const SizedBox(height: 6),
            _ProxyDelayText(proxy: proxy, testUrl: testUrl),
          ] else
            SizedBox(
              height: measure.bodySmallHeight,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Flexible(
                    flex: 1,
                    child: TooltipText(
                      text: Text(
                        proxy.type,
                        style: context.textTheme.bodySmall?.copyWith(
                          overflow: TextOverflow.ellipsis,
                          color: context.textTheme.bodySmall?.color?.opacity80,
                        ),
                      ),
                    ),
                  ),
                  _ProxyDelayText(proxy: proxy, testUrl: testUrl),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// Extract proxy name component
class _ProxyNameText extends StatelessWidget {
  final Proxy proxy;
  final ProxyCardType type;

  const _ProxyNameText({required this.proxy, required this.type});

  @override
  Widget build(BuildContext context) {
    final measure = globalState.measure;
    if (type == ProxyCardType.min) {
      return SizedBox(
        height: measure.bodyMediumHeight * 1,
        child: EmojiText(
          proxy.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.textTheme.bodyMedium,
        ),
      );
    } else {
      return SizedBox(
        height: measure.bodyMediumHeight * 2,
        child: EmojiText(
          proxy.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: context.textTheme.bodyMedium,
        ),
      );
    }
  }
}

// Extract delay text component
class _ProxyDelayText extends ConsumerWidget {
  final Proxy proxy;
  final String? testUrl;

  const _ProxyDelayText({required this.proxy, required this.testUrl});

  void _handleTestCurrentDelay() {
    proxyDelayTest(proxy, testUrl);
  }

  Widget _buildDelayAnimation(
    DelayAnimationType type,
    double size,
    Color color,
  ) {
    return switch (type) {
      DelayAnimationType.none => Icon(Icons.bolt, size: size),
      DelayAnimationType.rotatingCircle =>
        SpinKitRotatingCircle(color: color, size: size),
      DelayAnimationType.pulse => SpinKitPulse(color: color, size: size),
      DelayAnimationType.spinningLines =>
        SpinKitSpinningLines(color: color, size: size),
      DelayAnimationType.threeInOut =>
        SpinKitThreeInOut(color: color, size: size),
      DelayAnimationType.threeBounce =>
        SpinKitThreeBounce(color: color, size: size),
      DelayAnimationType.circle => SpinKitCircle(color: color, size: size),
      DelayAnimationType.fadingCircle =>
        SpinKitFadingCircle(color: color, size: size),
      DelayAnimationType.fadingFour =>
        SpinKitFadingFour(color: color, size: size),
      DelayAnimationType.wave => SpinKitWave(color: color, size: size),
      DelayAnimationType.doubleBounce =>
        SpinKitDoubleBounce(color: color, size: size),
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final measure = globalState.measure;
    final delayAnimation = ref.watch(
      proxiesStyleSettingProvider.select((state) => state.delayAnimation),
    );

    return SizedBox(
      height: measure.labelSmallHeight,
      child: Consumer(
        builder: (_, ref, _) {
          final delay = ref.watch(
            getDelayProvider(proxyName: proxy.name, testUrl: testUrl),
          );
          return delay == null
              ? SizedBox(
                  height: measure.labelSmallHeight,
                  width: measure.labelSmallHeight,
                  child: delayAnimation == DelayAnimationType.none
                      ? IconButton(
                          icon: const Icon(Icons.bolt),
                          iconSize: measure.labelSmallHeight,
                          padding: EdgeInsets.zero,
                          onPressed: _handleTestCurrentDelay,
                        )
                      : GestureDetector(
                          onTap: _handleTestCurrentDelay,
                          child: _buildDelayAnimation(
                            delayAnimation,
                            measure.labelSmallHeight,
                            context.colorScheme.primary,
                          ),
                        ),
                )
              : GestureDetector(
                  onTap: _handleTestCurrentDelay,
                  child: Text(
                    delay > 0 ? '$delay ms' : 'Timeout',
                    style: context.textTheme.labelSmall?.copyWith(
                      overflow: TextOverflow.ellipsis,
                      color: utils.getDelayColor(delay),
                    ),
                  ),
                );
        },
      ),
    );
  }
}

class _ProxyDesc extends ConsumerWidget {
  final Proxy proxy;

  const _ProxyDesc({required this.proxy});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final desc = ref.watch(getProxyDescProvider(proxy));
    return EmojiText(
      desc,
      overflow: TextOverflow.ellipsis,
      style: context.textTheme.bodySmall?.copyWith(
        color: context.textTheme.bodySmall?.color?.opacity80,
      ),
    );
  }
}

class _ProxyComputedMark extends ConsumerWidget {
  final String groupName;
  final Proxy proxy;

  const _ProxyComputedMark({required this.groupName, required this.proxy});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final proxyName = ref.watch(getProxyNameProvider(groupName));
    if (proxyName != proxy.name) {
      return const SizedBox();
    }
    return Container(
      alignment: Alignment.topRight,
      margin: const EdgeInsets.all(8),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Theme.of(context).colorScheme.secondaryContainer,
        ),
        child: const SelectIcon(),
      ),
    );
  }
}
