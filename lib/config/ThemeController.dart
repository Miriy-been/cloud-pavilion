import 'package:flutter/material.dart';

import '../util/SpUtils.dart';

/// 主题模式控制器（全局单例，持久化到本地）
class ThemeController {
  static final ValueNotifier<ThemeMode> mode = ValueNotifier(ThemeMode.light);

  /// 从本地恢复主题模式
  static Future<void> load() async {
    final saved = await SpUtils.getString('themeMode');
    ThemeMode m = ThemeMode.light;
    if (saved == 'dark') m = ThemeMode.dark;
    if (saved == 'system') m = ThemeMode.system;
    mode.value = m;
  }

  /// 切换主题模式并持久化
  static Future<void> set(ThemeMode m) async {
    mode.value = m;
    await SpUtils.setString('themeMode', m.name);
  }
}
