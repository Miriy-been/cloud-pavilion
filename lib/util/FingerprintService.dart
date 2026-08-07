import 'dart:convert';

import 'package:cloudpavilion/util/SpUtils.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// 本地指纹快捷登录服务
///
/// 用系统生物识别（指纹/面部）验证身份后，解锁本地加密保存的账号密码自动登录。
/// 密码保存在 Android Keystore / iOS Keychain（flutter_secure_storage），
/// 账号元信息（站点/用户名）存在本地偏好，可同时绑定多个账号。
/// 注意：这是「指纹解锁本地凭据」的快捷登录，不是 FIDO2 通行密钥，
/// 凭据不跨设备同步。
class FingerprintService {
  FingerprintService._();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  /// 本地指纹账号列表存储键（不含密码）
  static const String _accountsKey = 'fp_accounts';

  /// 设备是否支持生物识别
  static Future<bool> isAvailable() async {
    final auth = LocalAuthentication();
    try {
      final canBio = await auth.canCheckBiometrics;
      final supported = await auth.isDeviceSupported();
      return canBio && supported;
    } catch (_) {
      return false;
    }
  }

  /// 弹出系统生物识别验证，成功返回 true；用户取消返回 false；
  /// 设备不支持 / 无已注册生物识别等真实错误会抛出，由调用方提示用户。
  static Future<bool> verify(String reason) async {
    final auth = LocalAuthentication();
    // 仅生物识别（不含锁屏 PIN 兜底），与指纹登录体验一致
    return await auth.authenticate(
      localizedReason: reason,
      biometricOnly: true,
    );
  }

  /// 为某账号开启指纹登录（保存加密密码 + 账号元信息）
  static Future<void> enable(
      String siteUrl, String userName, String siteName, String password) async {
    await _storage.write(
        key: _pwdKey(siteUrl, userName), value: password);
    final accounts = await _loadAccounts();
    accounts.removeWhere(
        (a) => a['siteUrl'] == siteUrl && a['userName'] == userName);
    accounts.add({
      'siteUrl': siteUrl,
      'userName': userName,
      'siteName': siteName,
    });
    await SpUtils.setString(_accountsKey, jsonEncode(accounts));
  }

  /// 已开启指纹登录的账号列表（不含密码）
  static Future<List<Map<String, dynamic>>> listAccounts() async {
    return await _loadAccounts();
  }

  /// 指定账号是否已开启指纹登录
  static Future<bool> hasAccount(String siteUrl, String userName) async {
    final accounts = await _loadAccounts();
    return accounts.any(
        (a) => a['siteUrl'] == siteUrl && a['userName'] == userName);
  }

  /// 读取指定账号本地保存的密码（未开启返回 null）
  static Future<String?> passwordFor(String siteUrl, String userName) =>
      _storage.read(key: _pwdKey(siteUrl, userName));

  /// 关闭指定账号的指纹登录（删除本地密码与账号记录）
  static Future<void> disable(String siteUrl, String userName) async {
    await _storage.delete(key: _pwdKey(siteUrl, userName));
    final accounts = await _loadAccounts();
    accounts.removeWhere(
        (a) => a['siteUrl'] == siteUrl && a['userName'] == userName);
    await SpUtils.setString(_accountsKey, jsonEncode(accounts));
  }

  static Future<List<Map<String, dynamic>>> _loadAccounts() async {
    final raw = await SpUtils.getString(_accountsKey);
    if (raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static String _pwdKey(String siteUrl, String userName) =>
      'fp_pwd_${siteUrl}_$userName';
}
