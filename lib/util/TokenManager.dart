import 'package:cloudpavilion/util/SpUtils.dart';

/// 当前登录账号的 Token 管理（单账号上下文，多账号切换时整体覆盖）
class TokenManager {
  static const String _accessKey = 'access_token';
  static const String _refreshKey = 'refresh_token';
  static const String _accessExpiresKey = 'access_expires';
  static const String _refreshExpiresKey = 'refresh_expires';

  /// 保存 token 对（expires 为 ISO8601 字符串）
  static Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
    required DateTime accessExpires,
    required DateTime refreshExpires,
  }) async {
    await SpUtils.setString(_accessKey, accessToken);
    await SpUtils.setString(_refreshKey, refreshToken);
    await SpUtils.setString(
        _accessExpiresKey, accessExpires.toIso8601String());
    await SpUtils.setString(
        _refreshExpiresKey, refreshExpires.toIso8601String());
  }

  /// 读取 access token
  static Future<String> getAccessToken() async {
    return await SpUtils.getString(_accessKey);
  }

  /// 读取 refresh token
  static Future<String> getRefreshToken() async {
    return await SpUtils.getString(_refreshKey);
  }

  /// access token 是否已过期（提前 1 分钟视为过期）
  static Future<bool> isAccessTokenExpired() async {
    final exp = await SpUtils.getString(_accessExpiresKey);
    if (exp.isEmpty) return true;
    final t = DateTime.tryParse(exp);
    if (t == null) return true;
    return t.isBefore(DateTime.now().add(const Duration(minutes: 1)));
  }

  /// access token 是否在 margin 内即将过期（用于提前刷新）
  static Future<bool> isAccessTokenExpiringSoon(
      [Duration margin = const Duration(minutes: 10)]) async {
    final exp = await SpUtils.getString(_accessExpiresKey);
    if (exp.isEmpty) return true;
    final t = DateTime.tryParse(exp);
    if (t == null) return true;
    return t.isBefore(DateTime.now().add(margin));
  }

  /// refresh token 是否在 margin 内即将过期（用于提前刷新）
  static Future<bool> isRefreshTokenExpiringSoon(
      [Duration margin = const Duration(minutes: 30)]) async {
    final exp = await SpUtils.getString(_refreshExpiresKey);
    if (exp.isEmpty) return true;
    final t = DateTime.tryParse(exp);
    if (t == null) return true;
    return t.isBefore(DateTime.now().add(margin));
  }

  /// refresh token 是否已过期
  static Future<bool> isRefreshTokenExpired() async {
    final exp = await SpUtils.getString(_refreshExpiresKey);
    if (exp.isEmpty) return true;
    final t = DateTime.tryParse(exp);
    if (t == null) return true;
    return t.isBefore(DateTime.now());
  }

  /// 清除 token
  static Future<void> clear() async {
    await SpUtils.remove(_accessKey);
    await SpUtils.remove(_refreshKey);
    await SpUtils.remove(_accessExpiresKey);
    await SpUtils.remove(_refreshExpiresKey);
  }
}
