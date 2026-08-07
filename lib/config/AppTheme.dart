import 'package:flutter/material.dart';

/// CloudReve 设计令牌 —— 简约现代风 v1（支持浅色 / 深色）
///
/// 单一品牌蓝，浅色画布。`dark` 标志由 ThemeController 在主题解析后同步，
/// 各组件通过 getter 读取当前模式的配色。
class AppColors {
  /// 当前是否为深色模式（由 [ThemeController] 在 MaterialApp builder 中同步）
  static bool dark = false;

  /// 品牌色种子
  static const seed = Color(0xFF2F6BFF);

  // ---- 浅色调色板 ----
  static const lightBg = Color(0xFFF4F6FA);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightInk = Color(0xFF0B1220);
  static const lightInk2 = Color(0xFF5B6478);
  static const lightInk3 = Color(0xFF9AA3B5);
  static const lightLine = Color(0xFFE8EBF1);
  static const lightPrimary = Color(0xFF2F6BFF);
  static const lightPrimarySoft = Color(0xFFEDF3FF);
  static const lightPrimaryLight = Color(0xFF5B8DEF);

  // ---- 信息蓝（详情等「查看」类操作）----
  static const lightInfo = Color(0xFF0EA5E9);
  static const lightInfoBg = Color(0xFFE0F2FE);

  // ---- 深色调色板 ----
  static const darkBg = Color(0xFF10141B);
  static const darkSurface = Color(0xFF1A1F29);
  static const darkInk = Color(0xFFEDF1F7);
  static const darkInk2 = Color(0xFFA7AFBF);
  static const darkInk3 = Color(0xFF6C7484);
  static const darkLine = Color(0xFF2A303C);
  static const darkPrimary = Color(0xFF6C8CFF);
  static const darkPrimarySoft = Color(0xFF1D2A4A);
  static const darkPrimaryLight = Color(0xFF8AA8FF);

  // ---- 信息蓝（详情等「查看」类操作）----
  static const darkInfo = Color(0xFF38BDF8);
  static const darkInfoBg = Color(0xFF17334A);

  // ---- 语义色（两种模式共用） ----
  static const success = Color(0xFF12B76A);
  static const danger = Color(0xFFE5484D);
  static const lightDangerBg = Color(0xFFFFEEF0);
  static const darkDangerBg = Color(0xFF3A2226);
  static const warning = Color(0xFFF5A623);
  static const lightWarningBg = Color(0xFFFFF3E6);
  static const darkWarningBg = Color(0xFF3A2E1E);

  /// 通用柔和投影色（浅色 4% 深色墨色）
  static const shadow = Color(0x0A0B1220);

  // ---- 当前模式取值 ----
  static Color get bg => dark ? darkBg : lightBg;
  static Color get surface => dark ? darkSurface : lightSurface;
  static Color get ink => dark ? darkInk : lightInk;
  static Color get ink2 => dark ? darkInk2 : lightInk2;
  static Color get ink3 => dark ? darkInk3 : lightInk3;
  static Color get line => dark ? darkLine : lightLine;
  static Color get primary => dark ? darkPrimary : lightPrimary;
  static Color get primarySoft => dark ? darkPrimarySoft : lightPrimarySoft;

  /// 品牌渐变的高亮端（FAB / 播放按钮等主操作）
  static Color get primaryLight => dark ? darkPrimaryLight : lightPrimaryLight;

  /// 信息蓝（详情等「查看」类操作），前景色
  static Color get info => dark ? darkInfo : lightInfo;

  /// 信息蓝浅底
  static Color get infoBg => dark ? darkInfoBg : lightInfoBg;

  /// 警示（分享密码等）浅底
  static Color get warningBg => dark ? darkWarningBg : lightWarningBg;

  /// 危险（删除等）浅底
  static Color get dangerBg => dark ? darkDangerBg : lightDangerBg;

  /// 品牌渐变（对角主操作渐变）
  static List<Color> get brandGradient => [primary, primaryLight];
}

class AppTheme {
  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.seed,
      brightness: brightness,
    ).copyWith(
      primary: isDark ? AppColors.darkPrimary : AppColors.lightPrimary,
      surface: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      error: AppColors.danger,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        foregroundColor: isDark ? AppColors.darkInk : AppColors.lightInk,
        titleTextStyle: TextStyle(
          color: isDark ? AppColors.darkInk : AppColors.lightInk,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: isDark ? AppColors.darkLine : AppColors.lightLine,
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        // 浅蓝底 + 深色文字，与整体浅色风格统一（深色模式用深蓝底 + 浅色文字）
        backgroundColor:
            isDark ? AppColors.darkPrimarySoft : AppColors.lightPrimarySoft,
        contentTextStyle: TextStyle(
          color: isDark ? AppColors.darkInk : AppColors.lightInk,
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
        ),
        // 整体上移，避免贴底展示
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor:
            isDark ? AppColors.darkSurface : AppColors.lightSurface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: TextStyle(
          color: isDark ? AppColors.darkInk : AppColors.lightInk,
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
        contentTextStyle: TextStyle(
          color: isDark ? AppColors.darkInk2 : AppColors.lightInk2,
          fontSize: 14,
          height: 1.6,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor:
              isDark ? AppColors.darkPrimary : AppColors.lightPrimary,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: isDark ? AppColors.darkPrimary : AppColors.lightPrimary,
        selectionColor: (isDark ? AppColors.darkPrimary : AppColors.lightPrimary)
            .withValues(alpha: .25),
        selectionHandleColor:
            isDark ? AppColors.darkPrimary : AppColors.lightPrimary,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: isDark ? AppColors.darkPrimary : AppColors.lightPrimary,
        linearTrackColor: isDark ? AppColors.darkLine : AppColors.lightLine,
      ),
    );
  }
}
