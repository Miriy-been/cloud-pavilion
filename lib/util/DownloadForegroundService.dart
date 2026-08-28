import 'package:flutter/services.dart';

/// 下载前台服务（Android）通道封装。
/// 有下载任务进行时启动前台服务保持进程存活，任务全部结束自动停止。
class DownloadForegroundService {
  DownloadForegroundService._();

  static const MethodChannel _channel = MethodChannel('cloudreve/download_fg');

  /// 启动前台服务并显示初始通知（count 个任务，当前文件）
  static Future<void> start(int count, String file) async {
    try {
      await _channel.invokeMethod('start', {'count': count, 'file': file});
    } catch (_) {
      // 通道不可用（非 Android / 平台未实现）时静默忽略，不影响下载逻辑
    }
  }

  /// 更新通知（任务数 / 当前文件 / 总进度百分比）
  static Future<void> update(int count, String file, int percent) async {
    try {
      await _channel.invokeMethod(
          'update', {'count': count, 'file': file, 'percent': percent});
    } catch (_) {}
  }

  /// 停止前台服务（所有下载结束）
  static Future<void> stop() async {
    try {
      await _channel.invokeMethod('stop');
    } catch (_) {}
  }
}