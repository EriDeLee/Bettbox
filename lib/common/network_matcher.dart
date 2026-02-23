/// Network Matcher utility for Smart Auto-Stop feature.
/// Provides IP address parsing and CIDR matching functionality.
class NetworkMatcher {
  /// Parse an IPv4 address string to a 32-bit integer.
  /// Returns null if the format is invalid.
  static int? parseIPv4(String ip) {
    final trimmed = ip.trim();
    final parts = trimmed.split('.');
    if (parts.length != 4) return null;

    int result = 0;
    for (int i = 0; i < 4; i++) {
      final part = int.tryParse(parts[i]);
      if (part == null || part < 0 || part > 255) return null;
      result = (result << 8) | part;
    }
    return result;
  }

  /// Format a 32-bit integer back to IPv4 string.
  static String formatIPv4(int ip) {
    return '${(ip >> 24) & 0xFF}.${(ip >> 16) & 0xFF}.${(ip >> 8) & 0xFF}.${ip & 0xFF}';
  }

  /// Parse CIDR notation (e.g., "192.168.1.0/24").
  /// Returns (networkAddress, prefixLength) or null if invalid.
  static (int, int)? parseCIDR(String cidr) {
    final trimmed = cidr.trim();
    final parts = trimmed.split('/');

    if (parts.length == 1) {
      // Single IP address, treat as /32
      final ip = parseIPv4(parts[0]);
      if (ip == null) return null;
      return (ip, 32);
    }

    if (parts.length != 2) return null;

    final ip = parseIPv4(parts[0]);
    if (ip == null) return null;

    final prefix = int.tryParse(parts[1]);
    if (prefix == null || prefix < 0 || prefix > 32) return null;

    // Calculate network address by applying mask
    final mask = prefix == 0 ? 0 : (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF;
    final networkAddress = ip & mask;

    return (networkAddress, prefix);
  }

  /// Check if an IP address is within a CIDR range.
  static bool isIPInCIDR(String ip, String cidr) {
    final ipInt = parseIPv4(ip);
    if (ipInt == null) return false;

    final cidrParsed = parseCIDR(cidr);
    if (cidrParsed == null) return false;

    final (networkAddress, prefixLength) = cidrParsed;

    if (prefixLength == 0) return true; // 0.0.0.0/0 matches everything

    final mask = (0xFFFFFFFF << (32 - prefixLength)) & 0xFFFFFFFF;
    return (ipInt & mask) == networkAddress;
  }

  /// Check if an IP matches a single rule (IP or CIDR).
  static bool matchRule(String ip, String rule) {
    final trimmedRule = rule.trim();
    if (trimmedRule.isEmpty) return false;

    // If rule contains '/', treat as CIDR
    if (trimmedRule.contains('/')) {
      return isIPInCIDR(ip, trimmedRule);
    }

    // Otherwise, exact IP match
    final ipInt = parseIPv4(ip);
    final ruleInt = parseIPv4(trimmedRule);
    if (ipInt == null || ruleInt == null) return false;
    return ipInt == ruleInt;
  }

  /// Check if an IP matches any of the comma-separated rules.
  static bool matchAny(String? ip, String rules) {
    if (ip == null || ip.isEmpty) return false;
    if (rules.isEmpty) return false;

    final ruleList = rules.split(',');
    for (final rule in ruleList) {
      if (matchRule(ip, rule)) {
        return true;
      }
    }
    return false;
  }

  /// Validate if a single rule is in valid format.
  static bool isValidRule(String rule) {
    final trimmed = rule.trim();
    if (trimmed.isEmpty) return false;

    if (trimmed.contains('/')) {
      return parseCIDR(trimmed) != null;
    }
    return parseIPv4(trimmed) != null;
  }

  /// Validate the entire rules string (max 2 rules, comma-separated).
  static bool isValidRules(String rules) {
    if (rules.isEmpty) return true; // Empty is valid (means disabled)

    final ruleList = rules.split(',');
    if (ruleList.length > 2) return false;

    for (final rule in ruleList) {
      final trimmed = rule.trim();
      if (trimmed.isEmpty) continue;
      if (!isValidRule(trimmed)) return false;
    }
    return true;
  }

  /// Get validation error message for rules, or null if valid.
  static String? getValidationError(
    String rules, {
    String invalidFormatMsg = 'Invalid IP or CIDR format',
    String tooManyRulesMsg = 'Maximum 2 rules allowed',
  }) {
    if (rules.isEmpty) return null;

    final ruleList = rules.split(',');
    if (ruleList.length > 2) return tooManyRulesMsg;

    for (final rule in ruleList) {
      final trimmed = rule.trim();
      if (trimmed.isEmpty) continue;
      if (!isValidRule(trimmed)) return invalidFormatMsg;
    }
    return null;
  }
}
