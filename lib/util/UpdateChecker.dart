import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_2/config/AppTheme.dart';
import 'package:flutter_application_2/config/AppWidgets.dart';
import 'package:flutter_application_2/util/SpUtils.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// 版本更新检查（基于 GitHub Releases）
///
/// - 自动检查（App 启动后）：距上次弹窗不足 24h 不重复打扰；失败静默不提示；
/// - 手动检查（设置页入口）：忽略冷却；已是最新 / 检查失败时给出提示。
///
/// 发布流程：新版本构建 APK 后上传到 GitHub Releases（tag 命名如 v1.1.0），
/// 更新说明写在 release body 里即可，App 会自动弹窗提示。
class UpdateChecker {
  UpdateChecker._();

  /// GitHub Releases 最新版本 API（未认证限流 60 次/小时/IP，App 低频检查足够）
  static const String _latestApi =
      'https://api.github.com/repos/Miriy-been/cloud-pavilion/releases/latest';
  /// 项目发布主页（release 无 APK 附件时的兜底下载入口）
  static const String _releasesPage =
      'https://github.com/Miriy-been/cloud-pavilion/releases';

  static const String _lastPromptKey = 'update_last_prompt_at';
  static const Duration _autoCooldown = Duration(hours: 24);

  /// 独立 Dio 实例：GitHub 请求不走站点拦截器（不切 baseUrl / 不加云盘 token）
  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ));

  /// 检查更新。
  /// [manual] 手动检查（设置页）：忽略冷却，无更新/失败时 toast 提示；
  /// [context] 用于弹窗与 toast，为 null 时仅静默检查。
  static Future<void> check({bool manual = false, BuildContext? context}) async {
    // 自动检查：冷却期内直接跳过，避免一天多次打扰
    if (!manual) {
      final last = await SpUtils.getInt(_lastPromptKey);
      if (last > 0 &&
          DateTime.now().millisecondsSinceEpoch - last <
              _autoCooldown.inMilliseconds) {
        return;
      }
    }

    try {
      final resp = await _dio.get(_latestApi);
      final data = resp.data;
      if (data is! Map) return;
      final tag = data['tag_name']?.toString() ?? '';
      final current = (await PackageInfo.fromPlatform()).version;
      if (_isNewer(tag, current)) {
        // 记录提示时间，防止自动检查重复打扰
        SpUtils.setInt(
            _lastPromptKey, DateTime.now().millisecondsSinceEpoch);
        if (context == null || !context.mounted) return;
        await _showUpdateSheet(context, data, tag, current);
      } else if (manual && context != null && context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(appSnack('当前已是最新版本 v$current'));
      }
    } catch (_) {
      // 无网络 / 超时 / 仓库不可达：自动检查静默
      if (manual && context != null && context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(appSnack('检查更新失败，请稍后再试'));
      }
    }
  }

  /// tag（如 v1.1.0）是否比当前版本（如 1.0.0）新
  static bool _isNewer(String tag, String current) {
    final tagV = _parseVersion(tag);
    final curV = _parseVersion(current);
    if (tagV == null || curV == null) return false;
    for (var i = 0; i < 3; i++) {
      if (tagV[i] != curV[i]) return tagV[i] > curV[i];
    }
    return false;
  }

  /// 从任意格式字符串中提取主版本号 x.y.z（忽略 v 前缀 / +build 后缀；
  /// 兼容两位版本号如 v1.1，缺失的第三位按 0 处理）
  static List<int>? _parseVersion(String s) {
    final m = RegExp(r'(\d+)\.(\d+)(?:\.(\d+))?').firstMatch(s);
    if (m == null) return null;
    return [
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3) ?? '0'),
    ];
  }

  /// 取 release 附件中的 APK 下载直链；无 APK 时返回 null（跳转 releases 页）
  static String? _apkUrl(Map data) {
    final assets = data['assets'];
    if (assets is List) {
      for (final a in assets) {
        if (a is! Map) continue;
        final name = a['name']?.toString() ?? '';
        final url = a['browser_download_url']?.toString() ?? '';
        if (url.isNotEmpty &&
            (name.endsWith('.apk') || url.endsWith('.apk'))) {
          return url;
        }
      }
    }
    return null;
  }

  /// 更新提示弹窗（底部弹窗，与全局弹窗风格统一）
  static Future<void> _showUpdateSheet(
      BuildContext context, Map data, String tag, String current) async {
    final body = (data['body']?.toString() ?? '').trim();
    final apkUrl = _apkUrl(data);
    final target = apkUrl ?? _releasesPage;

    await showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final maxHeight = MediaQuery.of(ctx).size.height * 0.75;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: Padding(
              padding: const EdgeInsets.all(pagePad),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 6),
                  const SheetHandle(),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: AppColors.primarySoft,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.system_update_alt,
                            size: 22, color: AppColors.primary),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '发现新版本 v$tag',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: AppColors.ink,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '当前版本 v$current',
                              style: TextStyle(
                                  fontSize: 12.5, color: AppColors.ink3),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (body.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    // 更新说明（限高滚动，防长文本溢出）
                    Container(
                      width: double.infinity,
                      constraints: BoxConstraints(maxHeight: maxHeight * 0.45),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.bg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: SingleChildScrollView(
                        child: Text(
                          body,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.55,
                            color: AppColors.ink2,
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.ink2,
                            side: BorderSide(color: AppColors.line),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('稍后提醒'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: () {
                            Navigator.pop(ctx);
                            launchUrl(Uri.parse(target),
                                mode: LaunchMode.externalApplication);
                          },
                          child: const Text('立即更新'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
