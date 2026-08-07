import 'package:flutter/foundation.dart';

/// 全局登录态（所有登录/登出/改密/token 失效路径同步更新）
///
/// 驱动根路由守卫 [AuthGate]：登录态一旦丢失（如 token 刷新失败），
/// 主界面立即替换为登录页，避免未登录仍停留在存储/分类等内部页面。
class AuthState {
  AuthState._();

  static final ValueNotifier<bool> isLoggedIn = ValueNotifier(false);
}
