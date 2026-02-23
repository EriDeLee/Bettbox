import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

/// Windows Helper 服务认证管理器
///
/// 负责生成和管理 HMAC-SHA256 认证密钥，用于保护 Helper 服务的 API 调用
class HelperAuthManager {
  static String? _authKey;

  /// 生成随机认证密钥（应用启动时调用一次）
  ///
  /// 生成 32 字节的随机密钥，用于 HMAC-SHA256 签名
  static void generateAuthKey() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    _authKey = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// 获取认证密钥（用于传递给 Helper 服务）
  static String? getAuthKey() => _authKey;

  /// 生成请求签名
  ///
  /// 返回包含时间戳和签名的 HTTP 头
  ///
  /// [body] 请求体内容（用于签名）
  static Map<String, String> generateAuthHeaders(String body) {
    if (_authKey == null) {
      // 如果没有密钥，返回空头（向后兼容）
      return {};
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final message = '$timestamp:$body';

    // 计算 HMAC-SHA256
    final keyBytes = _hexToBytes(_authKey!);
    final messageBytes = utf8.encode(message);
    final hmacSha256 = Hmac(sha256, keyBytes);
    final digest = hmacSha256.convert(messageBytes);
    final signature = digest.toString();

    return {'X-Timestamp': timestamp.toString(), 'X-Signature': signature};
  }

  /// 将十六进制字符串转换为字节数组
  static List<int> _hexToBytes(String hex) {
    final result = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      result.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return result;
  }

  /// 清除认证密钥
  static void clearAuthKey() {
    _authKey = null;
  }
}
