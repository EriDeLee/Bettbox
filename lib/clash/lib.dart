import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:ui';

import 'package:ffi/ffi.dart';
import 'package:bett_box/common/common.dart';
import 'package:bett_box/enum/enum.dart';
import 'package:bett_box/models/models.dart';
import 'package:bett_box/plugins/service.dart';
import 'package:bett_box/state.dart';

import 'generated/clash_ffi.dart';
import 'interface.dart';

class ClashLib extends ClashHandlerInterface with AndroidClashInterface {
  static ClashLib? _instance;
  Completer<bool> _canSendCompleter = Completer();
  SendPort? sendPort;
  final receiverPort = ReceivePort();

  ClashLib._internal() {
    commonPrint.debug('ClashLib._internal() called', module: LogModule.ffi);
    _initService();
  }

  @override
  preload() {
    commonPrint.verbose('ClashLib.preload() called', module: LogModule.ffi);
    return _canSendCompleter.future.then((result) {
      commonPrint.debug('ClashLib.preload() completed: $result', module: LogModule.ffi);
      return result;
    });
  }

  Future<void> _initService() async {
    commonPrint.info('Initializing ClashLib service...', module: LogModule.ffi);
    await service?.destroy();
    _registerMainPort(receiverPort.sendPort);
    receiverPort.listen((message) {
      if (message is SendPort) {
        commonPrint.debug('Received SendPort from native', module: LogModule.ffi);
        if (_canSendCompleter.isCompleted) {
          sendPort = null;
          _canSendCompleter = Completer();
        }
        sendPort = message;
        _canSendCompleter.complete(true);
        commonPrint.debug('ClashLib service ready', module: LogModule.ffi);
      } else {
        commonPrint.verbose('Received action result from native', module: LogModule.ffi);
        handleResult(ActionResult.fromJson(json.decode(message)));
      }
    });
    await service?.init();
    commonPrint.info('ClashLib service initialization completed', module: LogModule.ffi);
  }

  void _registerMainPort(SendPort sendPort) {
    IsolateNameServer.removePortNameMapping(mainIsolate);
    IsolateNameServer.registerPortWithName(sendPort, mainIsolate);
  }

  factory ClashLib() {
    _instance ??= ClashLib._internal();
    return _instance!;
  }

  @override
  destroy() async {
    await service?.destroy();
    return true;
  }

  @override
  reStart() {
    _initService();
  }

  @override
  Future<bool> shutdown() async {
    await super.shutdown();
    destroy();
    return true;
  }

  @override
  sendMessage(String message) async {
    await _canSendCompleter.future;
    sendPort?.send(message);
  }

  // @override
  // Future<bool> stopTun() {
  //   return invoke<bool>(
  //     method: ActionMethod.stopTun,
  //   );
  // }

  @override
  Future<AndroidVpnOptions?> getAndroidVpnOptions() async {
    final res = await invoke<String>(method: ActionMethod.getAndroidVpnOptions);
    if (res.isEmpty) {
      return null;
    }
    return AndroidVpnOptions.fromJson(json.decode(res));
  }

  @override
  Future<bool> updateDns(String value) {
    return invoke<bool>(method: ActionMethod.updateDns, data: value);
  }

  @override
  Future<DateTime?> getRunTime() async {
    final runTimeString = await invoke<String>(method: ActionMethod.getRunTime);
    if (runTimeString.isEmpty) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(int.parse(runTimeString));
  }

  @override
  Future<String> getCurrentProfileName() {
    return invoke<String>(method: ActionMethod.getCurrentProfileName);
  }
}

class ClashLibHandler {
  static ClashLibHandler? _instance;

  late final ClashFFI clashFFI;

  late final DynamicLibrary lib;

  ClashLibHandler._internal() {
    commonPrint.info('Initializing ClashLibHandler...', module: LogModule.ffi);
    lib = DynamicLibrary.open('libclash.so');
    commonPrint.debug('Loaded libclash.so', module: LogModule.ffi);
    clashFFI = ClashFFI(lib);
    clashFFI.initNativeApiBridge(NativeApi.initializeApiDLData);
    commonPrint.info('ClashLibHandler initialization completed', module: LogModule.ffi);
  }

  factory ClashLibHandler() {
    _instance ??= ClashLibHandler._internal();
    return _instance!;
  }

  Future<String> invokeAction(String actionParams) {
    commonPrint.verbose('invokeAction: $actionParams', module: LogModule.ffi);
    final completer = Completer<String>();
    final receiver = ReceivePort();
    receiver.listen((message) {
      if (!completer.isCompleted) {
        commonPrint.verbose('invokeAction completed', module: LogModule.ffi);
        completer.complete(message);
        receiver.close();
      }
    });
    final actionParamsChar = actionParams.toNativeUtf8().cast<Char>();
    clashFFI.invokeAction(actionParamsChar, receiver.sendPort.nativePort);
    malloc.free(actionParamsChar);
    return completer.future;
  }

  void attachMessagePort(int messagePort) {
    commonPrint.debug('Attaching message port: $messagePort', module: LogModule.ffi);
    clashFFI.attachMessagePort(messagePort);
  }

  void updateDns(String dns) {
    commonPrint.verbose('updateDns: $dns', module: LogModule.ffi);
    final dnsChar = dns.toNativeUtf8().cast<Char>();
    clashFFI.updateDns(dnsChar);
    malloc.free(dnsChar);
  }

  void setState(CoreState state) {
    commonPrint.verbose('setState called', module: LogModule.ffi);
    final stateChar = json.encode(state).toNativeUtf8().cast<Char>();
    clashFFI.setState(stateChar);
    malloc.free(stateChar);
  }

  String getCurrentProfileName() {
    commonPrint.verbose('getCurrentProfileName called', module: LogModule.ffi);
    final currentProfileRaw = clashFFI.getCurrentProfileName();
    final currentProfile = currentProfileRaw.cast<Utf8>().toDartString();
    clashFFI.freeCString(currentProfileRaw);
    return currentProfile;
  }

  AndroidVpnOptions getAndroidVpnOptions() {
    commonPrint.verbose('getAndroidVpnOptions called', module: LogModule.ffi);
    final vpnOptionsRaw = clashFFI.getAndroidVpnOptions();
    final vpnOptions = json.decode(vpnOptionsRaw.cast<Utf8>().toDartString());
    clashFFI.freeCString(vpnOptionsRaw);
    return AndroidVpnOptions.fromJson(vpnOptions);
  }

  Traffic getTraffic() {
    commonPrint.verbose('getTraffic called', module: LogModule.traffic);
    final trafficRaw = clashFFI.getTraffic();
    final trafficString = trafficRaw.cast<Utf8>().toDartString();
    clashFFI.freeCString(trafficRaw);
    if (trafficString.isEmpty) {
      return Traffic();
    }
    return Traffic.fromMap(json.decode(trafficString));
  }

  Traffic getTotalTraffic(bool value) {
    commonPrint.verbose('getTotalTraffic called', module: LogModule.traffic);
    final trafficRaw = clashFFI.getTotalTraffic();
    final trafficString = trafficRaw.cast<Utf8>().toDartString();
    clashFFI.freeCString(trafficRaw);
    if (trafficString.isEmpty) {
      return Traffic();
    }
    return Traffic.fromMap(json.decode(trafficString));
  }

  Future<bool> startListener() async {
    commonPrint.info('startListener called', module: LogModule.listener);
    clashFFI.startListener();
    return true;
  }

  Future<bool> stopListener() async {
    commonPrint.info('stopListener called', module: LogModule.listener);
    clashFFI.stopListener();
    return true;
  }

  DateTime? getRunTime() {
    commonPrint.verbose('getRunTime called', module: LogModule.core);
    final runTimeRaw = clashFFI.getRunTime();
    final runTimeString = runTimeRaw.cast<Utf8>().toDartString();
    if (runTimeString.isEmpty) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(int.parse(runTimeString));
  }

  Future<Map<String, dynamic>> getConfig(String id) async {
    commonPrint.verbose('getConfig for profile: $id', module: LogModule.config);
    final path = await appPath.getProfilePath(id);
    final pathChar = path.toNativeUtf8().cast<Char>();
    final configRaw = clashFFI.getConfig(pathChar);
    final configString = configRaw.cast<Utf8>().toDartString();
    if (configString.isEmpty) {
      commonPrint.warning('getConfig returned empty config', module: LogModule.config);
      return {};
    }
    final config = json.decode(configString);
    malloc.free(pathChar);
    clashFFI.freeCString(configRaw);
    commonPrint.debug('getConfig completed', module: LogModule.config);
    return config;
  }

  Future<String> quickStart(
    InitParams initParams,
    SetupParams setupParams,
    CoreState state,
  ) {
    commonPrint.info('quickStart called', module: LogModule.core);
    commonPrint.verbose('quickStart params: init=$initParams, setup=$setupParams, state=$state', module: LogModule.core);
    final completer = Completer<String>();
    final receiver = ReceivePort();
    receiver.listen((message) {
      if (!completer.isCompleted) {
        commonPrint.verbose('quickStart completed with result: $message', module: LogModule.core);
        completer.complete(message);
        receiver.close();
      }
    });
    final params = json.encode(setupParams);
    final initValue = json.encode(initParams);
    final stateParams = json.encode(state);
    final initParamsChar = initValue.toNativeUtf8().cast<Char>();
    final paramsChar = params.toNativeUtf8().cast<Char>();
    final stateParamsChar = stateParams.toNativeUtf8().cast<Char>();
    clashFFI.quickStart(
      initParamsChar,
      paramsChar,
      stateParamsChar,
      receiver.sendPort.nativePort,
    );
    malloc.free(initParamsChar);
    malloc.free(paramsChar);
    malloc.free(stateParamsChar);
    return completer.future;
  }
}

ClashLib? get clashLib =>
    system.isAndroid && !globalState.isService ? ClashLib() : null;

ClashLibHandler? get clashLibHandler =>
    system.isAndroid && globalState.isService ? ClashLibHandler() : null;
