import 'dart:convert';

import 'package:bett_box/common/common.dart';
import 'package:bett_box/enum/enum.dart';
import 'package:bett_box/models/models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// FlClash 数据库提取工具
/// 用于从 FlClash 备份的 database.sqlite 文件中提取 Profile 元数据
class FlClashDatabaseExtractor {
  /// 从 FlClash 数据库文件提取 Profiles
  ///
  /// [dbPath] 数据库文件路径
  /// 返回提取的 Profile 列表
  static Future<List<Profile>> extractProfiles(String dbPath) async {
    Database? db;
    try {
      // 桌面端需要初始化 FFI
      if (system.isDesktop) {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
      }

      // 打开数据库（只读模式）
      db = await openDatabase(dbPath, readOnly: true, singleInstance: false);

      // 查询 profiles 表
      final List<Map<String, dynamic>> results = await db.query('profiles');

      // 转换为 Profile 对象
      final profiles = <Profile>[];
      for (final row in results) {
        try {
          final profile = _convertRowToProfile(row);
          profiles.add(profile);
        } catch (e) {
          commonPrint.log('Failed to convert profile row: $e');
          // 继续处理其他 Profile
        }
      }

      return profiles;
    } catch (e) {
      commonPrint.log('Failed to extract profiles from database: $e');
      rethrow;
    } finally {
      await db?.close();
    }
  }

  /// 将数据库行转换为 Profile 对象
  static Profile _convertRowToProfile(Map<String, dynamic> row) {
    // 提取基本字段
    final id = row['id'].toString(); // int -> String
    final rawLabel = row['label'] as String?;
    final url = row['url'] as String;
    final currentGroupName = row['currentGroupName'] as String?;

    // 智能提取标签：检测是否为流量信息字符串
    String label;
    if (rawLabel != null &&
        (rawLabel.contains('upload=') || rawLabel.contains('download='))) {
      // 场景：label 字段包含流量信息，需要寻找真实名称
      commonPrint.log('Detected traffic info in label field for profile $id');

      // 尝试从其他字段获取名称
      label =
          row['name'] as String? ??
          row['title'] as String? ??
          row['displayName'] as String? ??
          _extractNameFromUrl(url) ??
          'Subscription $id';

      commonPrint.log('Using alternative label: $label');
    } else {
      // 场景：label 是正常的友好名称
      label = rawLabel ?? 'Subscription $id';
    }

    // 提取时间字段
    final lastUpdateDateMillis = row['lastUpdateDate'] as int?;
    final lastUpdateDate = lastUpdateDateMillis != null
        ? DateTime.fromMillisecondsSinceEpoch(lastUpdateDateMillis)
        : null;

    // 提取自动更新设置
    final autoUpdate = (row['autoUpdate'] as int) == 1;
    final autoUpdateDurationMillis = row['autoUpdateDurationMillis'] as int;
    final autoUpdateDuration = Duration(milliseconds: autoUpdateDurationMillis);

    // 提取 JSON 字段（流量信息应该在这里，而不是在 label 中）
    final subscriptionInfo = _parseSubscriptionInfo(row['subscriptionInfo']);
    final selectedMap = _parseSelectedMap(row['selectedMap']);
    final unfoldSet = _parseUnfoldSet(row['unfoldSet']);

    // 提取覆盖类型
    final overwriteTypeStr = row['overwriteType'] as String?;
    final overwriteType = _parseOverwriteType(overwriteTypeStr);

    return Profile(
      id: id,
      label: label, // ✅ 现在显示正确的友好名称
      url: url,
      currentGroupName: currentGroupName,
      lastUpdateDate: lastUpdateDate,
      autoUpdate: autoUpdate,
      autoUpdateDuration: autoUpdateDuration,
      subscriptionInfo: subscriptionInfo, // ✅ 流量信息在正确的字段
      selectedMap: selectedMap,
      unfoldSet: unfoldSet,
      overrideData: OverrideData(
        enable: false, // 默认关闭
        rule: OverrideRule(type: overwriteType),
      ),
    );
  }

  /// 从 URL 中提取名称
  static String? _extractNameFromUrl(String url) {
    if (url.isEmpty) return null;

    try {
      final uri = Uri.parse(url);

      // 尝试从路径段提取
      final pathSegments = uri.pathSegments;
      if (pathSegments.isNotEmpty) {
        final lastSegment = pathSegments.last;
        // 移除文件扩展名
        final nameWithoutExt = lastSegment.replaceAll(
          RegExp(r'\.(yaml|yml|txt)$'),
          '',
        );
        if (nameWithoutExt.isNotEmpty && nameWithoutExt != lastSegment) {
          return nameWithoutExt;
        }
      }

      // 尝试从主机名提取
      if (uri.host.isNotEmpty) {
        return uri.host;
      }
    } catch (e) {
      commonPrint.log('Failed to extract name from URL: $e');
    }

    return null;
  }

  /// 解析 SubscriptionInfo JSON
  static SubscriptionInfo? _parseSubscriptionInfo(dynamic jsonStr) {
    if (jsonStr == null || jsonStr is! String) return null;
    try {
      final map = json.decode(jsonStr) as Map<String, dynamic>;
      return SubscriptionInfo.fromJson(map);
    } catch (e) {
      commonPrint.log('Failed to parse subscriptionInfo: $e');
      return null;
    }
  }

  /// 解析 selectedMap JSON
  static Map<String, String> _parseSelectedMap(dynamic jsonStr) {
    if (jsonStr == null || jsonStr is! String) return {};
    try {
      final map = json.decode(jsonStr);
      return Map<String, String>.from(map);
    } catch (e) {
      commonPrint.log('Failed to parse selectedMap: $e');
      return {};
    }
  }

  /// 解析 unfoldSet JSON
  static Set<String> _parseUnfoldSet(dynamic jsonStr) {
    if (jsonStr == null || jsonStr is! String) return {};
    try {
      final list = json.decode(jsonStr) as List;
      return Set<String>.from(list);
    } catch (e) {
      commonPrint.log('Failed to parse unfoldSet: $e');
      return {};
    }
  }

  /// 解析覆盖类型
  static OverrideRuleType _parseOverwriteType(String? typeStr) {
    if (typeStr == 'override') {
      return OverrideRuleType.override;
    }
    return OverrideRuleType.added;
  }
}
