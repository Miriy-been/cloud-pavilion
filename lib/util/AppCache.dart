import 'dart:io';

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

  /// 递归列出目录下所有文件（跳过预取中的 .preload 临时文件）
  static Stream<File> _walkFiles(Directory dir) async* {
    if (!await dir.exists()) return;
    await for (final e in dir.list(recursive: true, followLinks: false)) {
      if (e is File && !e.path.endsWith('.preload')) yield e;
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
