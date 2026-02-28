import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:bett_box/clash/clash.dart';
import 'package:bett_box/clash/interface.dart';
import 'package:bett_box/common/common.dart';
import 'package:bett_box/enum/enum.dart';
import 'package:bett_box/models/models.dart';
import 'package:bett_box/state.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart';

class ClashCore {
  static ClashCore? _instance;
  late ClashHandlerInterface clashInterface;

  ClashCore._internal() {
    if (system.isAndroid) {
      clashInterface = clashLib!;
    } else {
      clashInterface = clashService!;
    }
    commonPrint.debug('ClashCore initialized, platform: ${system.isAndroid ? "Android" : "Desktop"}', module: LogModule.core);
  }

  factory ClashCore() {
    _instance ??= ClashCore._internal();
    return _instance!;
  }

  Future<bool> preload() {
    commonPrint.verbose('Preloading Clash library...', module: LogModule.core);
    return clashInterface.preload().then((result) {
      commonPrint.debug('Clash library preload completed: $result', module: LogModule.core);
      return result;
    });
  }

  static Future<void> initGeo() async {
    commonPrint.debug('Initializing Geo data...', module: LogModule.core);
    final homePath = await appPath.homeDirPath;
    final homeDir = Directory(homePath);
    final isExists = await homeDir.exists();
    if (!isExists) {
      commonPrint.verbose('Creating home directory: $homePath', module: LogModule.core);
      await homeDir.create(recursive: true);
    }
    const geoFileNameList = [
      mmdbFileName,
      geoIpFileName,
      geoSiteFileName,
      asnFileName,
    ];
    try {
      for (final geoFileName in geoFileNameList) {
        final geoFile = File(join(homePath, geoFileName));
        final isExists = await geoFile.exists();
        if (isExists) {
          commonPrint.verbose('Geo file exists, skipping: $geoFileName', module: LogModule.core);
          continue;
        }
        commonPrint.verbose('Extracting Geo file from assets: $geoFileName', module: LogModule.core);
        final data = await rootBundle.load('assets/data/$geoFileName');
        List<int> bytes = data.buffer.asUint8List();
        await geoFile.writeAsBytes(bytes, flush: true);
        commonPrint.debug('Geo file extracted: $geoFileName', module: LogModule.core);
      }
      commonPrint.debug('Geo data initialization completed', module: LogModule.core);
    } catch (e) {
      commonPrint.error('Geo data initialization failed: $e', module: LogModule.core);
      exit(0);
    }
  }

  Future<bool> init() async {
    commonPrint.info('=== Starting ClashCore initialization ===', module: LogModule.core);
    
    commonPrint.verbose('Step 1: Initializing Geo data', module: LogModule.core);
    await initGeo();
    
    commonPrint.verbose('Step 2: Configuring log system', module: LogModule.core);
    if (globalState.config.appSetting.openLogs) {
      commonPrint.debug('Logs enabled, starting log listener', module: LogModule.core);
      clashCore.startLog();
    } else {
      commonPrint.debug('Logs disabled, stopping log listener', module: LogModule.core);
      clashCore.stopLog();
    }
    
    commonPrint.verbose('Step 3: Getting home directory path', module: LogModule.core);
    final homeDirPath = await appPath.homeDirPath;
    commonPrint.verbose('Home directory path: $homeDirPath', module: LogModule.core);
    
    commonPrint.verbose('Step 4: Calling clashInterface.init', module: LogModule.core);
    final result = await clashInterface.init(
      InitParams(homeDir: homeDirPath, version: globalState.appState.version),
    );
    
    commonPrint.info('=== ClashCore initialization completed: $result ===', module: LogModule.core);
    return result;
  }

  Future<bool> setState(CoreState state) async {
    commonPrint.verbose('Setting core state...', module: LogModule.core);
    final result = await clashInterface.setState(state);
    commonPrint.debug('Core state set completed: $result', module: LogModule.core);
    return result;
  }

  Future<void> shutdown() async {
    commonPrint.info('Shutting down ClashCore...', module: LogModule.core);
    await clashInterface.shutdown();
    commonPrint.debug('ClashCore shutdown completed', module: LogModule.core);
  }

  FutureOr<bool> get isInit async {
    final result = await clashInterface.isInit;
    commonPrint.verbose('Checking if core is initialized: $result', module: LogModule.core);
    return result;
  }

  FutureOr<String> validateConfig(String data) {
    commonPrint.debug('Validating config...', module: LogModule.config);
    return clashInterface.validateConfig(data).then((result) {
      if (result.isNotEmpty) {
        commonPrint.error('Config validation failed: $result', module: LogModule.config);
      } else {
        commonPrint.debug('Config validation passed', module: LogModule.config);
      }
      return result;
    });
  }

  Future<String> updateConfig(UpdateParams updateParams) async {
    commonPrint.info('Updating Clash config...', module: LogModule.config);
    final result = await clashInterface.updateConfig(updateParams);
    if (result.isNotEmpty) {
      commonPrint.error('Config update failed: $result', module: LogModule.config);
    } else {
      commonPrint.debug('Config update completed successfully', module: LogModule.config);
    }
    return result;
  }

  Future<String> setupConfig(SetupParams setupParams) async {
    commonPrint.info('Setting up Clash config...', module: LogModule.config);
    final result = await clashInterface.setupConfig(setupParams);
    if (result.isNotEmpty) {
      commonPrint.error('Config setup failed: $result', module: LogModule.config);
    } else {
      commonPrint.debug('Config setup completed successfully', module: LogModule.config);
    }
    return result;
  }

  Future<List<Group>> getProxiesGroups() async {
    commonPrint.verbose('Fetching proxies groups...', module: LogModule.proxy);
    final proxies = await clashInterface.getProxies();
    if (proxies.isEmpty) {
      commonPrint.warning('No proxies available', module: LogModule.proxy);
      return [];
    }
    final groupNames = [
      UsedProxy.GLOBAL.name,
      ...(proxies[UsedProxy.GLOBAL.name]['all'] as List).where((e) {
        final proxy = proxies[e] ?? {};
        return GroupTypeExtension.valueList.contains(proxy['type']);
      }),
    ];
    final groupsRaw = groupNames.map((groupName) {
      final group = proxies[groupName];
      group['all'] = ((group['all'] ?? []) as List)
          .map((name) => proxies[name])
          .where((proxy) => proxy != null)
          .toList();
      return group;
    }).toList();
    final groups = groupsRaw.map((e) => Group.fromJson(e)).toList();
    commonPrint.debug('Fetched ${groups.length} proxy groups', module: LogModule.proxy);
    return groups;
  }

  FutureOr<String> changeProxy(ChangeProxyParams changeProxyParams) async {
    commonPrint.debug(
      'Changing proxy: ${changeProxyParams.groupName} -> ${changeProxyParams.proxyName}',
      module: LogModule.proxy,
    );
    return await clashInterface.changeProxy(changeProxyParams);
  }

  Future<List<TrackerInfo>> getConnections() async {
    commonPrint.verbose('Fetching connections...', module: LogModule.connection);
    final res = await clashInterface.getConnections();
    if (res.isEmpty) {
      return [];
    }
    try {
      final connectionsData = json.decode(res) as Map;
      final connectionsRaw = connectionsData['connections'] as List? ?? [];
      final connections = connectionsRaw.map((e) => TrackerInfo.fromJson(e)).toList();
      commonPrint.debug('Fetched ${connections.length} connections', module: LogModule.connection);
      return connections;
    } catch (e) {
      commonPrint.error('Failed to parse connections: $e', module: LogModule.connection);
      return [];
    }
  }

  void closeConnection(String id) {
    commonPrint.verbose('Closing connection: $id', module: LogModule.connection);
    clashInterface.closeConnection(id);
  }

  void closeConnections() {
    commonPrint.debug('Closing all connections', module: LogModule.connection);
    clashInterface.closeConnections();
  }

  void resetConnections() {
    commonPrint.debug('Resetting connections', module: LogModule.connection);
    clashInterface.resetConnections();
  }

  Future<List<ExternalProvider>> getExternalProviders() async {
    commonPrint.verbose('Fetching external providers...', module: LogModule.core);
    final externalProvidersRawString = await clashInterface
        .getExternalProviders();
    if (externalProvidersRawString.isEmpty) {
      return [];
    }
    try {
      return Isolate.run<List<ExternalProvider>>(() {
        final externalProviders =
            (json.decode(externalProvidersRawString) as List<dynamic>)
                .map((item) => ExternalProvider.fromJson(item))
                .toList();
        commonPrint.debug('Fetched ${externalProviders.length} external providers', module: LogModule.core);
        return externalProviders;
      });
    } catch (e) {
      commonPrint.error('Failed to parse external providers: $e', module: LogModule.core);
      return [];
    }
  }

  Future<ExternalProvider?> getExternalProvider(
    String externalProviderName,
  ) async {
    commonPrint.verbose('Fetching external provider: $externalProviderName', module: LogModule.core);
    final externalProvidersRawString = await clashInterface.getExternalProvider(
      externalProviderName,
    );
    if (externalProvidersRawString.isEmpty) {
      return null;
    }
    try {
      return ExternalProvider.fromJson(json.decode(externalProvidersRawString));
    } catch (e) {
      commonPrint.error('Failed to parse external provider: $e', module: LogModule.core);
      return null;
    }
  }

  Future<String> updateGeoData(UpdateGeoDataParams params) {
    commonPrint.info('Updating Geo data: ${params.type}', module: LogModule.core);
    return clashInterface.updateGeoData(params);
  }

  Future<String> sideLoadExternalProvider({
    required String providerName,
    required String data,
  }) {
    commonPrint.debug('Side-loading external provider: $providerName', module: LogModule.core);
    return clashInterface.sideLoadExternalProvider(
      providerName: providerName,
      data: data,
    );
  }

  Future<String> updateExternalProvider({required String providerName}) async {
    commonPrint.info('Updating external provider: $providerName', module: LogModule.core);
    return clashInterface.updateExternalProvider(providerName);
  }

  Future<void> startListener() async {
    commonPrint.info('Starting Clash listener...', module: LogModule.listener);
    await clashInterface.startListener();
    commonPrint.debug('Clash listener started successfully', module: LogModule.listener);
  }

  Future<void> stopListener() async {
    commonPrint.info('Stopping Clash listener...', module: LogModule.listener);
    await clashInterface.stopListener();
    commonPrint.debug('Clash listener stopped', module: LogModule.listener);
  }

  Future<Delay> getDelay(String url, String proxyName) async {
    commonPrint.verbose('Testing delay for $proxyName: $url', module: LogModule.proxy);
    final data = await clashInterface.asyncTestDelay(url, proxyName);
    if (data.isEmpty) {
      throw Exception('Empty delay response');
    }
    try {
      return Delay.fromJson(json.decode(data));
    } catch (e) {
      commonPrint.error('Failed to parse delay: $e', module: LogModule.proxy);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getConfig(String id) async {
    commonPrint.verbose('Getting config for profile: $id', module: LogModule.config);
    final profilePath = await appPath.getProfilePath(id);
    final res = await clashInterface.getConfig(profilePath);
    if (res.isSuccess) {
      commonPrint.debug('Config retrieved successfully', module: LogModule.config);
      return res.data as Map<String, dynamic>;
    } else {
      commonPrint.error('Failed to get config: ${res.message}', module: LogModule.config);
      throw res.message;
    }
  }

  Future<Traffic> getTraffic() async {
    final trafficString = await clashInterface.getTraffic();
    if (trafficString.isEmpty) {
      return Traffic();
    }
    try {
      return Traffic.fromMap(json.decode(trafficString));
    } catch (e) {
      commonPrint.error('Failed to parse traffic: $e', module: LogModule.traffic);
      return Traffic();
    }
  }

  Future<IpInfo?> getCountryCode(String ip) async {
    commonPrint.verbose('Getting country code for IP: $ip', module: LogModule.connection);
    final countryCode = await clashInterface.getCountryCode(ip);
    if (countryCode.isEmpty) {
      return null;
    }
    return IpInfo(ip: ip, countryCode: countryCode);
  }

  Future<Traffic> getTotalTraffic() async {
    final totalTrafficString = await clashInterface.getTotalTraffic();
    if (totalTrafficString.isEmpty) {
      return Traffic();
    }
    try {
      return Traffic.fromMap(json.decode(totalTrafficString));
    } catch (e) {
      commonPrint.error('Failed to parse total traffic: $e', module: LogModule.traffic);
      return Traffic();
    }
  }

  Future<int> getMemory() async {
    commonPrint.verbose('Getting memory usage...', module: LogModule.core);
    final value = await clashInterface.getMemory();
    if (value.isEmpty) {
      return 0;
    }
    return int.parse(value);
  }

  void resetTraffic() {
    commonPrint.verbose('Resetting traffic statistics', module: LogModule.traffic);
    clashInterface.resetTraffic();
  }

  void startLog() {
    commonPrint.info('Starting Clash log listener', module: LogModule.listener);
    clashInterface.startLog();
  }

  void stopLog() {
    commonPrint.info('Stopping Clash log listener', module: LogModule.listener);
    clashInterface.stopLog();
  }

  Future<void> requestGc() async {
    commonPrint.verbose('Requesting garbage collection...', module: LogModule.core);
    await clashInterface.forceGc();
    commonPrint.debug('Garbage collection requested', module: LogModule.core);
  }

  Future<void> flushFakeIP() async {
    commonPrint.debug('Flushing Fake-IP cache...', module: LogModule.core);
    await clashInterface.flushFakeIP();
  }

  Future<void> flushDnsCache() async {
    commonPrint.debug('Flushing DNS cache...', module: LogModule.core);
    await clashInterface.flushDnsCache();
  }

  Future<void> destroy() async {
    commonPrint.info('Destroying ClashCore...', module: LogModule.core);
    await clashInterface.destroy();
    commonPrint.debug('ClashCore destroyed', module: LogModule.core);
  }
}

final clashCore = ClashCore();
