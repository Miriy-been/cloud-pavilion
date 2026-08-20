import 'package:local_auth/local_auth.dart';

/// 生物识别（指纹/面部）验证服务
///
/// 用于「账户切换指纹保护」：在账户管理中切号时，通过系统生物识别校验身份后放行，
/// 防止他人拿到手机后直接代登已保存的账号。
class FingerprintService {
  FingerprintService._();

  /// 设备是否支持生物识别（含已登记的生物识别信息）
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
  /// 设备不支持 / 无已登记生物识别等真实错误会抛出，由调用方提示用户。
  static Future<bool> verify(String reason) async {
    final auth = LocalAuthentication();
    // 仅生物识别（不含锁屏 PIN 兜底）
    return await auth.authenticate(
      localizedReason: reason,
      biometricOnly: true,
    );
  }
}