import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:cloudpavilion/util/SpUtils.dart';

/// 当前登录账号的 Token 管理（单账号上下文，多账号切换时整体覆盖）
///
/// token 属敏感凭据，Android 走 KeyStore 加密（EncryptedSharedPreferences），
/// iOS 走 Keychain；**不再写入 SharedPreferences**（明文 XML，
/// root / 备份 / 调试构建可直接读取）。
///
/// 为兼容老版本已登录用户，首次读取时会从 SharedPreferences 迁移一次：
/// 读到即写入安全存储并删除 SP 中的明文副本。
class TokenManager {
  static const String _accessKey = 'access_token';
  static const String _refreshKey = 'refresh_token';
  static const String _accessExpiresKey = 'access_expires';
  static const String _refreshExpiresKey = 'refresh_expires';

  /// flutter_secure_storage：Android 走 KeyStore 加密存储，iOS 走 Keychain。
  /// 版本 10 起默认使用自定义加密实现（EncryptedSharedPreferences 已废弃，
  /// 旧数据会在首次访问时自动迁移），因此不再显式配置 AndroidOptions。
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  /// 是否已完成旧数据迁移检查（进程内只做一次）
  static bool _migrated = false;

  /// 迁移旧版本写入 SharedPreferences 的明文 token（仅首次调用时执行）
  static Future<void> _migrateOnce() async {
    if (_migrated) return;
    _migrated = true;
    try {
      final legacy = await SpUtils.getString(_accessKey);
      if (legacy.isEmpty) return;
      // 明文副本存在：搬到安全存储后删除，避免残留
      for (final key in const [
        _accessKey,
        _refreshKey,
        _accessExpiresKey,
        _refreshExpiresKey,
      ]) {
        final v = await SpUtils.getString(key);
        if (v.isEmpty) continue;
        await _storage.write(key: key, value: v);
        await SpUtils.remove(key);
      }
    } catch (e) {
      // 迁移失败不阻塞登录（如个别机型 KeyStore 异常），
      // 下次启动会再次尝试；此路径下仍可读旧明文数据
      debugPrint('token 迁移到安全存储失败: $e');
      _migrated = false;
    }
  }

  static Future<String?> _read(String key) async {
    await _migrateOnce();
    try {
      final v = await _storage.read(key: key);
      if (v != null) return v;
    } catch (e) {
      debugPrint('读取安全存储失败($key): $e');
    }
    // 安全存储不可用 / 迁移尚未成功时，回退读取旧明文位置，
    // 避免已登录用户在升级后被动登出
    final legacy = await SpUtils.getString(key);
    return legacy.isEmpty ? null : legacy;
  }

  /// 保存 token 对（expires 为 ISO8601 字符串）
  static Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
    required DateTime accessExpires,
    required DateTime refreshExpires,
  }) async {
    await _migrateOnce();
    await _storage.write(key: _accessKey, value: accessToken);
    await _storage.write(key: _refreshKey, value: refreshToken);
    await _storage.write(
        key: _accessExpiresKey, value: accessExpires.toIso8601String());
    await _storage.write(
        key: _refreshExpiresKey, value: refreshExpires.toIso8601String());
  }

  /// 读取 access token
  static Future<String> getAccessToken() async {
    return await _read(_accessKey) ?? '';
  }

  /// 读取 refresh token
  static Future<String> getRefreshToken() async {
    return await _read(_refreshKey) ?? '';
  }

  /// access token 是否已过期（提前 1 分钟视为过期）
  static Future<bool> isAccessTokenExpired() async {
    final exp = await _read(_accessExpiresKey) ?? '';
    if (exp.isEmpty) return true;
    final t = DateTime.tryParse(exp);
    if (t == null) return true;
    return t.isBefore(DateTime.now().add(const Duration(minutes: 1)));
  }

  /// access token 是否在 margin 内即将过期（用于提前刷新）
  static Future<bool> isAccessTokenExpiringSoon(
      [Duration margin = const Duration(minutes: 10)]) async {
    final exp = await _read(_accessExpiresKey) ?? '';
    if (exp.isEmpty) return true;
    final t = DateTime.tryParse(exp);
    if (t == null) return true;
    return t.isBefore(DateTime.now().add(margin));
  }

  /// refresh token 是否在 margin 内即将过期（用于提前刷新）
  static Future<bool> isRefreshTokenExpiringSoon(
      [Duration margin = const Duration(minutes: 30)]) async {
    final exp = await _read(_refreshExpiresKey) ?? '';
    if (exp.isEmpty) return true;
    final t = DateTime.tryParse(exp);
    if (t == null) return true;
    return t.isBefore(DateTime.now().add(margin));
  }

  /// refresh token 是否已过期
  static Future<bool> isRefreshTokenExpired() async {
    final exp = await _read(_refreshExpiresKey) ?? '';
    if (exp.isEmpty) return true;
    final t = DateTime.tryParse(exp);
    if (t == null) return true;
    return t.isBefore(DateTime.now());
  }

  /// 清除 token（安全存储与可能残留的旧明文副本一并清理）
  static Future<void> clear() async {
    _migrated = true; // 主动清除时不再触发迁移
    for (final key in const [
      _accessKey,
      _refreshKey,
      _accessExpiresKey,
      _refreshExpiresKey,
    ]) {
      try {
        await _storage.delete(key: key);
      } catch (e) {
        debugPrint('清除安全存储失败($key): $e');
      }
      await SpUtils.remove(key);
    }
  }

  // ---------- 多账号快照 ----------
  //
  // 切换账号需要该账号自己的 token 对。原先整体塞在 SharedPreferences 的
  // accounts JSON 里（明文），现改为按「站点 + 用户名」维度存入安全存储，
  // accounts 中只保留非敏感信息。

  /// 账号快照的 token 存储键
  static String _snapshotKey(String siteUrl, String userName) =>
      'account_token|$siteUrl|$userName';

  /// 保存某账号的 token 快照（供后续切号使用）
  static Future<void> saveSnapshot({
    required String siteUrl,
    required String userName,
    required Map<String, dynamic> token,
  }) async {
    await _migrateOnce();
    try {
      await _storage.write(
        key: _snapshotKey(siteUrl, userName),
        value: jsonEncode(token),
      );
    } catch (e) {
      debugPrint('保存账号 token 快照失败: $e');
    }
  }

  /// 读取某账号的 token 快照；不存在或损坏时返回 null
  static Future<Map<String, dynamic>?> readSnapshot(
      String siteUrl, String userName) async {
    await _migrateOnce();
    try {
      final raw = await _storage.read(key: _snapshotKey(siteUrl, userName));
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (e) {
      debugPrint('读取账号 token 快照失败: $e');
      return null;
    }
  }

  /// 删除某账号的 token 快照（删除账号 / 改密失效时调用）
  static Future<void> deleteSnapshot(String siteUrl, String userName) async {
    try {
      await _storage.delete(key: _snapshotKey(siteUrl, userName));
    } catch (e) {
      debugPrint('删除账号 token 快照失败: $e');
    }
  }
}
