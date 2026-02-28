import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:bett_box/plugins/app.dart';
import 'package:bett_box/plugins/tile.dart';
import 'package:bett_box/plugins/vpn.dart';
import 'package:bett_box/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'application.dart';
import 'clash/core.dart';
import 'clash/lib.dart';
import 'common/common.dart';
import 'models/models.dart';

const String _sentryDsn = String.fromEnvironment('SENTRY_DSN');

Future<void> _checkUpdateAndClean() async {
  try {
    final prefs = await preferences.sharedPreferencesCompleter.future;
    if (prefs == null) return;

    final lastUpdateTime = await app.getSelfLastUpdateTime();
    final savedUpdateTime = prefs.getInt('last_update_time') ?? 0;

    if (savedUpdateTime == 0) {
      commonPrint.verbose('First run, saving update time: $lastUpdateTime', module: LogModule.app);
      await prefs.setInt('last_update_time', lastUpdateTime);
      return;
    }

    if (savedUpdateTime != lastUpdateTime) {
      commonPrint.info('App updated! Cleaning up zombie VPN state...', module: LogModule.app);
      commonPrint.debug('Update detected: $savedUpdateTime -> $lastUpdateTime', module: LogModule.app);
      await prefs.setBool('is_vpn_running', false);
      await prefs.setBool('is_tun_running', false);
      await prefs.setInt('last_update_time', lastUpdateTime);
      commonPrint.debug('VPN state cleaned up', module: LogModule.app);
    }
  } catch (e) {
    commonPrint.error('Error in _checkUpdateAndClean: $e', module: LogModule.app);
  }
}

Future<void> main() async {
  // Init base services
  commonPrint.info('=== App Starting ===', module: LogModule.app);
  globalState.isService = false;
  commonPrint.debug('Setting isService = false', module: LogModule.app);
  WidgetsFlutterBinding.ensureInitialized();

  // Set image cache size
  commonPrint.verbose('Setting image cache size to 50MB', module: LogModule.app);
  PaintingBinding.instance.imageCache.maximumSizeBytes =
      50 * 1024 * 1024; // 50MB

  final version = await system.version;
  commonPrint.debug('System version: $version', module: LogModule.app);
  
  commonPrint.info('Preloading Clash library...', module: LogModule.core);
  await clashCore.preload();
  
  commonPrint.info('Initializing global state...', module: LogModule.app);
  await globalState.initApp(version);

  commonPrint.info('Checking for updates and cleaning up...', module: LogModule.app);
  await _checkUpdateAndClean();

  // Init UI
  try {
    commonPrint.info('Initializing UI...', module: LogModule.ui);
    await uiManager.initializeUI();
  } catch (e) {
    commonPrint.error('Failed to initialize UI: $e', module: LogModule.ui);
  }

  assert(
    _sentryDsn.isNotEmpty,
    'SENTRY_DSN is not set. Build with --dart-define=SENTRY_DSN=<your-dsn>',
  );

  final enableAdvancedAnalytics =
      globalState.config.appSetting.enableCrashReport;

  commonPrint.debug('Initializing Sentry (enableAdvancedAnalytics=$enableAdvancedAnalytics)', module: LogModule.app);
  await SentryFlutter.init((options) {
    options.dsn = _sentryDsn;
    options.sendDefaultPii = false;
    options.environment = 'production';
    options.release =
        'bettbox@${globalState.packageInfo.version}+${globalState.packageInfo.buildNumber}';

    options.enableAutoSessionTracking = true;
    options.attachStacktrace = true;

    if (enableAdvancedAnalytics) {
      options.tracesSampleRate = 0.2;
      options.profilesSampleRate = 0.1;
    } else {
      options.tracesSampleRate = 0;
      options.profilesSampleRate = 0;
    }
  }, appRunner: () => _runApp(version));
  
  commonPrint.info('=== App Initialization Completed ===', module: LogModule.app);
}

Future<void> _runApp(int version) async {
  commonPrint.debug('Running app with version: $version', module: LogModule.app);
  await android?.init();
  await window?.init(version);
  HttpOverrides.global = BettboxHttpOverrides();
  commonPrint.info('Running Flutter app...', module: LogModule.app);
  runApp(ProviderScope(child: const Application()));
}

@pragma('vm:entry-point')
Future<void> _service(List<String> flags) async {
  commonPrint.info('=== Service Starting ===', module: LogModule.vpn);
  globalState.isService = true;
  WidgetsFlutterBinding.ensureInitialized();

  await _checkUpdateAndClean();

  final quickStart = flags.contains('quick');
  commonPrint.debug('Service started with quickStart=$quickStart', module: LogModule.vpn);
  final clashLibHandler = ClashLibHandler();
  await globalState.init();

  tile?.addListener(
    _TileListenerWithService(
      onStart: () async {
        await app.tip(appLocalizations.startVpn);
        await globalState.handleStart();
      },
      onStop: () async {
        await app.tip(appLocalizations.stopVpn);
        clashLibHandler.stopListener();
        await vpn?.stop();
        exit(0);
      },
    ),
  );

  vpn?.handleGetStartForegroundParams = () async {
    // Check if smart-stopped from native side
    final isSmartStopped = await vpn?.isSmartStopped() ?? false;

    if (isSmartStopped) {
      return json.encode({
        'title': appLocalizations.coreSuspended,
        'content': appLocalizations.smartAutoStopServiceRunning,
      });
    }

    return json.encode({
      'title': appLocalizations.coreConnected,
      'content': appLocalizations.serviceRunning,
    });
  };

  vpn?.addListener(
    _VpnListenerWithService(
      onDnsChanged: (String dns) {
        clashLibHandler.updateDns(dns);
      },
    ),
  );
  if (!quickStart) {
    commonPrint.debug('Starting main IPC handler', module: LogModule.vpn);
    _handleMainIpc(clashLibHandler);
  } else {
    commonPrint.info('Quick start mode', module: LogModule.vpn);

    final prefs = await preferences.sharedPreferencesCompleter.future;
    final isVpnRunning = prefs?.getBool('is_vpn_running') ?? false;
    commonPrint.debug('is_vpn_running flag: $isVpnRunning', module: LogModule.vpn);

    if (!isVpnRunning) {
      commonPrint.error('is_vpn_running is false. Aborting quick start to prevent zombie VPN.', module: LogModule.vpn);
      await vpn?.stop();
      exit(0);
      return;
    }

    commonPrint.debug('Initializing Clash Geo data', module: LogModule.core);
    await ClashCore.initGeo();
    app.tip(appLocalizations.startVpn);
    final homeDirPath = await appPath.homeDirPath;
    final version = await system.version;
    final clashConfig = globalState.config.patchClashConfig.copyWith.tun(
      enable: false,
    );
    Future(() async {
      commonPrint.debug('Setting up Clash config in background', module: LogModule.core);
      final profileId = globalState.config.currentProfileId;
      if (profileId == null) {
        commonPrint.error('No profile ID selected', module: LogModule.core);
        return;
      }
      final params = await globalState.getSetupParams(pathConfig: clashConfig);
      commonPrint.verbose('Quick start params: $params', module: LogModule.core);
      final res = await clashLibHandler.quickStart(
        InitParams(homeDir: homeDirPath, version: version),
        params,
        globalState.getCoreState(),
      );
      debugPrint(res);
      if (res.isNotEmpty) {
        commonPrint.error('Quick start failed: $res', module: LogModule.core);
        await vpn?.stop();
        exit(0);
      }
      commonPrint.debug('Quick start successful, starting VPN', module: LogModule.vpn);
      await vpn?.start(clashLibHandler.getAndroidVpnOptions());
      clashLibHandler.startListener();
      commonPrint.info('=== Quick Start Completed ===', module: LogModule.vpn);
    });
  }
}

void _handleMainIpc(ClashLibHandler clashLibHandler) {
  final sendPort = IsolateNameServer.lookupPortByName(mainIsolate);
  if (sendPort == null) {
    return;
  }
  final serviceReceiverPort = ReceivePort();
  serviceReceiverPort.listen((message) async {
    final res = await clashLibHandler.invokeAction(message);
    sendPort.send(res);
  });
  sendPort.send(serviceReceiverPort.sendPort);
  final messageReceiverPort = ReceivePort();
  clashLibHandler.attachMessagePort(messageReceiverPort.sendPort.nativePort);
  messageReceiverPort.listen((message) {
    sendPort.send(message);
  });
}

@immutable
class _TileListenerWithService with TileListener {
  final Function() _onStart;
  final Function() _onStop;

  const _TileListenerWithService({
    required Function() onStart,
    required Function() onStop,
  }) : _onStart = onStart,
       _onStop = onStop;

  @override
  void onStart() {
    _onStart();
  }

  @override
  void onStop() {
    _onStop();
  }
}

@immutable
class _VpnListenerWithService with VpnListener {
  final Function(String dns) _onDnsChanged;

  const _VpnListenerWithService({required Function(String dns) onDnsChanged})
    : _onDnsChanged = onDnsChanged;

  @override
  void onDnsChanged(String dns) {
    super.onDnsChanged(dns);
    _onDnsChanged(dns);
  }
}
