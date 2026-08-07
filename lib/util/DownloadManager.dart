import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:cloudpavilion/model/DownloadTaskModel.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:path_provider/path_provider.dart';
import 'ErrorText.dart';
import 'SpUtils.dart';

/// 本地下载任务管理器（全局单例）
/// 任务增删 / 状态变化时通知监听者；进度高频回调时进行节流通知
class DownloadManager extends ChangeNotifier {
  DownloadManager._();
  static final DownloadManager instance = DownloadManager._();

  /// 任务记录本地持久化 key 前缀（按账号隔离，站点+用户名 维度）
  static const _kTasksKey = 'downloadTasks';

  /// 当前账号的任务持久化 key
  Future<String> _tasksKey() async {
    final siteUrl = await SpUtils.getString('CurrentBaseUrl');
    final userName = await SpUtils.getString('currentUserName');
    return siteUrl.isEmpty || userName.isEmpty
        ? _kTasksKey
        : '${_kTasksKey}_$siteUrl|$userName';
  }

  final List<DownloadTaskModel> tasks = [];
  final Dio _dio = Dio();
  final Map<DownloadTaskModel, CancelToken> _tokens = {};

  /// 原生保存到系统 Download 目录的通道
  static const MethodChannel _downloadsChannel =
      MethodChannel('cloudreve/downloads');

  /// 进度节流：上次通知时间
  DateTime _lastNotify = DateTime.fromMillisecondsSinceEpoch(0);

  /// 状态变化：立即通知并持久化
  void _notifyImmediate() {
    _lastNotify = DateTime.now();
    notifyListeners();
    _persist();
  }

  /// 进度高频回调：最多每 250ms 通知一次，不触发持久化
  void _notifyThrottled() {
    final now = DateTime.now();
    if (now.difference(_lastNotify).inMilliseconds >= 250) {
      _lastNotify = now;
      notifyListeners();
    }
  }

  /// 恢复历史任务记录（应用启动 / 切换账号时调用）
  Future<void> restore() async {
    final raw = await SpUtils.getString(await _tasksKey());
    if (raw.isEmpty) return;
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      for (final e in list) {
        final t = DownloadTaskModel.fromJson(e as Map<String, dynamic>);
        // 重启后未完成任务无法续传，标记为中断失败
        if (t.status == DownloadStatus.downloading) {
          t.status = DownloadStatus.failed;
          t.error = '下载已中断';
        }
        tasks.add(t);
      }
      notifyListeners();
    } catch (_) {
      // 本地数据损坏时忽略，保留空列表
    }
    // 启动时清理中断 / 残留的下载临时文件（重启后无进行中的下载）
    await _clearTempLeftovers();
  }

  /// 清理下载临时目录（files/CloudReve/.tmp）中的残留文件：
  /// 取消 / 中断的下载会留下半成品，若不清理将持续占用 app 数据空间
  Future<void> _clearTempLeftovers() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final folder = Directory('${dir.path}${Platform.pathSeparator}CloudReve'
          '${Platform.pathSeparator}.tmp');
      if (!await folder.exists()) return;
      await for (final e in folder.list()) {
        try {
          await e.delete();
        } catch (_) {}
      }
    } catch (_) {}
  }

  /// 持久化全部任务记录
  Future<void> _persist() async {
    await SpUtils.setString(await _tasksKey(),
        jsonEncode(tasks.map((t) => t.toJson()).toList()));
  }

  /// 切换账号：停止旧账号进行中的任务并加载新账号的任务记录。
  /// 必须在当前账号上下文（CurrentBaseUrl / currentUserName）已更新后调用；
  /// 停止任务时不触发持久化，避免旧账号任务写入新账号的 key
  Future<void> switchAccount() async {
    for (final t in List.of(tasks)) {
      if (t.status == DownloadStatus.downloading) {
        t.status = DownloadStatus.cancelled;
        _tokens.remove(t)?.cancel();
      }
    }
    tasks.clear();
    notifyListeners();
    await restore();
  }

  /// 应用专属下载目录：/storage/emulated/0/cloudreve（自动创建，Android 11+ 需授权）
  Future<String> _appDir() async {
    final res = await _downloadsChannel
        .invokeMethod<Map<dynamic, dynamic>>('ensureAppDownloadDir');
    if (res != null && res['ok'] == true) {
      return res['path'] as String;
    }
    if (res != null && res['needPermission'] == true) {
      throw _StoragePermissionException(
          '需要开启「所有文件访问」权限才能保存到 /storage/emulated/0/cloudreve');
    }
    throw Exception('无法创建下载目录 /storage/emulated/0/cloudreve');
  }

  /// 系统下载目录模式的临时下载目录（完成后转入系统 Download）
  Future<String> _tempPath(String name) async {
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory(
        '${dir.path}${Platform.pathSeparator}CloudReve${Platform.pathSeparator}.tmp');
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }
    return '${folder.path}${Platform.pathSeparator}$name';
  }

  /// 开始下载（url 为签名临时直链，无需认证头）
  Future<void> startDownload(String name, String url) async {
    final systemDownloads =
        await SpUtils.getString('downloadDirMode', 'system') == 'system';
    final task = DownloadTaskModel(
      name: name,
      savePath: '',
      sourceUrl: url,
      systemDownloads: systemDownloads,
    );
    tasks.add(task);
    _notifyImmediate();
    await _runDownload(task, systemDownloads: systemDownloads);
  }

  /// 取消下载任务
  void cancel(DownloadTaskModel task) {
    if (task.status != DownloadStatus.downloading) return;
    task.status = DownloadStatus.cancelled;
    _tokens.remove(task)?.cancel();
    // 取消系统下载目录模式的任务：删除临时文件，避免残留占用 app 数据空间
    // （app 专属目录模式直接写入 /storage/emulated/0/cloudreve，属于用户资产不删）
    if (task.systemDownloads && task.savePath.isNotEmpty) {
      try {
        final tmp = File(task.savePath);
        if (tmp.existsSync()) tmp.deleteSync();
      } catch (_) {}
    }
    _notifyImmediate();
  }

  /// 重试（失败 / 已取消的任务）
  Future<void> retry(DownloadTaskModel task) async {
    if (task.sourceUrl.isEmpty) return;
    task.status = DownloadStatus.downloading;
    task.error = null;
    task.progress = 0;
    _notifyImmediate();
    await _runDownload(task, systemDownloads: task.systemDownloads);
  }

  Future<void> _runDownload(DownloadTaskModel task,
      {bool systemDownloads = false}) async {
    final token = CancelToken();
    _tokens[task] = token;
    // 解析保存路径：系统下载目录 → 临时目录；应用专属目录 → /storage/emulated/0/cloudreve
    final String workingPath;
    try {
      workingPath = systemDownloads
          ? await _tempPath(task.name)
          : '${await _appDir()}${Platform.pathSeparator}${task.name}';
      task.savePath = workingPath;
    } catch (e) {
      // 目录创建失败（通常为「所有文件访问」权限未开启）：标记失败并引导授权
      task.status = DownloadStatus.failed;
      task.error = e.toString();
      task.savePath = systemDownloads
          ? '/CloudReve/.tmp/${task.name}'
          : '/storage/emulated/0/cloudreve/${task.name}';
      _tokens.remove(task);
      if (e is _StoragePermissionException) {
        _downloadsChannel.invokeMethod('openAllFilesAccess');
        SmartDialog.showToast('下载「${task.name}」失败：${e.message}');
      } else {
        SmartDialog.showToast(
            '下载「${task.name}」失败：${errorText(e, '无法创建下载目录')}');
      }
      _notifyImmediate();
      return;
    }
    try {
      await _dio.download(
        task.sourceUrl,
        workingPath,
        cancelToken: token,
        onReceiveProgress: (received, total) {
          task.totalSize = total;
          task.progress = total > 0 ? received / total : 0;
          _notifyThrottled();
        },
      );
      task.progress = 1;
      if (systemDownloads) {
        task.savePath = await _moveToSystemDownloads(task.name, workingPath);
      }
      task.status = DownloadStatus.finished;
      _notifyImmediate();
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        task.status = DownloadStatus.cancelled;
      } else {
        task.status = DownloadStatus.failed;
        task.error = e.toString();
        SmartDialog.showToast('下载「${task.name}」失败：${errorText(e, '网络错误')}');
      }
      _notifyImmediate();
    } catch (e) {
      task.status = DownloadStatus.failed;
      task.error = e.toString();
      SmartDialog.showToast('下载「${task.name}」失败：${errorText(e, '保存文件失败')}');
      // 转入系统下载目录失败：清理临时文件
      if (systemDownloads) {
        final tmp = File(workingPath);
        if (tmp.existsSync()) tmp.deleteSync();
      }
      _notifyImmediate();
    } finally {
      _tokens.remove(task);
    }
  }

  /// 调用原生将临时文件保存到系统公共 Download 目录
  Future<String> _moveToSystemDownloads(String name, String tempPath) async {
    final path = await _downloadsChannel.invokeMethod<String>(
      'saveToDownloads',
      {'fileName': name, 'sourcePath': tempPath},
    );
    if (path == null || path.isEmpty) {
      throw Exception('保存到系统下载目录失败');
    }
    return path;
  }
}

/// 应用专属目录权限不足异常
class _StoragePermissionException implements Exception {
  final String message;
  _StoragePermissionException(this.message);
  @override
  String toString() => message;
}
