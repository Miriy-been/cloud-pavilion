import 'dart:async';

import 'package:cloudpavilion/util/DioUtil.dart';
import 'package:cloudpavilion/util/SpUtils.dart';
import 'package:cloudpavilion/util/TokenManager.dart';

/// Token 定时自动刷新（全局单例）
/// 周期性检查 access / refresh token 的过期状态，临近过期时主动调用刷新接口续期。
/// 每次刷新会同时换发新的 refresh_token，从而让会话长效在线，无需频繁重新登录。
class TokenAutoRefresh {
  TokenAutoRefresh._();
  static final TokenAutoRefresh instance = TokenAutoRefresh._();

  /// 定时检查间隔
  static const Duration _interval = Duration(minutes: 15);

  Timer? _timer;

  /// 启动定时刷新（登录后 / 应用启动且已登录时调用）
  void start() {
    _timer ??= Timer.periodic(_interval, (_) {
      refreshIfNeeded();
    });
    // 启动时立即检查一次，避免等待首个周期
    refreshIfNeeded();
  }

  /// 停止定时刷新（退出登录时调用）
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// 检查并刷新 token（定时触发 / 应用恢复前台时均可调用）
  Future<void> refreshIfNeeded() async {
    if (!(await SpUtils.getBool('isLogin'))) return;
    // 仅当 access 或 refresh token 临近过期时才刷新，避免无意义请求
    final needAccess = await TokenManager.isAccessTokenExpiringSoon();
    final needRefresh = await TokenManager.isRefreshTokenExpiringSoon();
    if (!needAccess && !needRefresh) return;
    // refresh token 已过期则无法续期
    if (await TokenManager.isRefreshTokenExpired()) return;
    if ((await TokenManager.getRefreshToken()).isEmpty) return;
    try {
      // 与 401 重试共用并发锁，避免重复刷新
      await DioUtil().refreshTokenNow();
    } catch (_) {
      // 刷新失败不在此强制登出，交由请求层 401 逻辑处理
    }
  }
}
