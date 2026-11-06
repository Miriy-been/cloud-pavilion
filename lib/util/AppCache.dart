import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';

/// 本地缓存清理（图片 / 音频 / 临时下载文件等可再生缓存）
///
/// 只操作 cache 目录与下载临时目录，不触碰用户资产
/// （系统 Download / cloudreve 目录下的已下载文件、任务记录等）。
class AppCache {
  AppCache._();

  /// 自动淘汰阈值：缓存超过 300MB 时清理最旧文件。
  /// 音频已改为纯流式（不整曲落盘），剩余大头是缩略图/封面等图片缓存，
  /// 300MB 足够日常使用且不会让本地占用失控。
  static const int evictLimitBytes = 300 * 1024 * 1024;

  /// 正在被写入的文件路径（进行中的下载）。
  ///
  /// `.tmp` 目录同时存放「下载中转文件」，与图片缓存共用清理入口。
  /// 若清理时把这些文件一并删除，正在写入的下载会失败（文件句柄背后
  /// 的路径已消失）。下载开始时登记、结束时注销，清理时跳过。
  static final Set<String> _activeFiles = {};

  /// 登记 / 注销进行中的文件（由 DownloadManager 调用）
  static void markActive(String path) => _activeFiles.add(path);
  static void unmarkActive(String path) => _activeFiles.remove(path);

  /// 该文件是否正在被写入（不区分路径分隔符，避免 Windows/Android 差异）
  static bool _isActive(File f) =>
      _activeFiles.any((p) => _samePath(p, f.path));

  /// 测试入口：判断给定路径是否处于活跃状态
  @visibleForTesting
  static bool isActiveForTest(String path) =>
      _activeFiles.any((p) => _samePath(p, path));

  static bool _samePath(String a, String b) =>
      a.replaceAll('\\', '/') == b.replaceAll('\\', '/');

  /// 需要清理的目录：应用缓存目录 + 下载转存临时目录（documents/CloudReve/.tmp）
  static Future<List<Directory>> _cacheDirs() async {
    final tmp = await getTemporaryDirectory();
    final docs = await getApplicationDocumentsDirectory();
    return [
      tmp,
      Directory('${docs.path}${Platform.pathSeparator}CloudReve'
          '${Platform.pathSeparator}.tmp'),
    ];
  }

  /// 递归列出目录下所有文件（跳过预取中的 .preload 临时文件与正在写入的文件）
  static Stream<File> _walkFiles(Directory dir) async* {
    if (!await dir.exists()) return;
    await for (final e in dir.list(recursive: true, followLinks: false)) {
      if (e is File && !e.path.endsWith('.preload') && !_isActive(e)) yield e;
    }
  }

  /// 统计所有缓存文件的总字节数
  static Future<int> totalCacheSize() async {
    var total = 0;
    for (final dir in await _cacheDirs()) {
      await for (final f in _walkFiles(dir)) {
        try {
          total += f.lengthSync();
        } catch (_) {}
      }
    }
    return total;
  }

  /// 一键清空所有缓存，返回清理的字节数
  static Future<int> clearAllCache() async {
    var freed = 0;
    for (final dir in await _cacheDirs()) {
      await for (final f in _walkFiles(dir)) {
        try {
          freed += f.lengthSync();
          await f.delete();
        } catch (_) {}
      }
    }
    // 清掉 flutter_cache_manager 的索引（图片/封面缓存元数据）
    try {
      await DefaultCacheManager().emptyCache();
    } catch (_) {}
    return freed;
  }

  /// 缓存超阈值时按最后修改时间淘汰最旧文件，直到低于阈值（应用启动时调用）
  static Future<void> evictIfOverflow(
      {int limitBytes = evictLimitBytes}) async {
    final files = <File>[];
    for (final dir in await _cacheDirs()) {
      await for (final f in _walkFiles(dir)) {
        files.add(f);
      }
    }
    var total = 0;
    for (final f in files) {
      try {
        total += f.lengthSync();
      } catch (_) {}
    }
    if (total <= limitBytes) return;
    // 最旧优先删除
    files.sort((a, b) => a.statSync().modified.compareTo(b.statSync().modified));
    var freed = 0;
    for (final f in files) {
      try {
        freed += f.lengthSync();
        await f.delete();
      } catch (_) {}
      if (total - freed <= limitBytes) break;
    }
    try {
      await DefaultCacheManager().emptyCache();
    } catch (_) {}
  }
}
