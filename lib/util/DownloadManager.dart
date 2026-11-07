import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:cloudpavilion/model/DownloadTaskModel.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:path_provider/path_provider.dart';
import 'ErrorText.dart';
import 'AppCache.dart';
import 'SpUtils.dart';
import 'DownloadForegroundService.dart';

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

  /// 每个任务的下载速度计算状态
  final Map<DownloadTaskModel, _DownloadSpeedState> _speed = {};

  /// 下载前台服务是否已启动
  bool _fgActive = false;

  /// 前台通知更新节流：上次更新时间
  DateTime _lastFgUpdate = DateTime.fromMillisecondsSinceEpoch(0);

  /// 状态变化：立即通知并持久化
  void _notifyImmediate() {
    _lastNotify = DateTime.now();
    notifyListeners();
    _persist();
    _syncForeground(force: true);
  }

  /// 进度高频回调：最多每 250ms 通知一次，不触发持久化
  void _notifyThrottled() {
    final now = DateTime.now();
    if (now.difference(_lastNotify).inMilliseconds >= 250) {
      _lastNotify = now;
      notifyListeners();
    }
    _syncForeground();
  }

  /// 同步下载前台服务：有任务下载中时启动 / 更新常驻通知，全部结束后自动停止。
  void _syncForeground({bool force = false}) {
    final active = tasks
        .where((t) => t.status == DownloadStatus.downloading)
        .toList();
    if (active.isEmpty) {
      if (_fgActive) {
        _fgActive = false;
        DownloadForegroundService.stop();
      }
      return;
    }
    final now = DateTime.now();
    if (!force && now.difference(_lastFgUpdate).inMilliseconds < 1000) {
      return;
    }
    _lastFgUpdate = now;
    final count = active.length;
    final file = active.first.name;
    final avg = active.fold<double>(0, (a, t) => a + t.progress) / count;
    final percent = (avg * 100).round().clamp(0, 100);
    if (_fgActive) {
      DownloadForegroundService.update(count, file, percent);
    } else {
      _fgActive = true;
      DownloadForegroundService.start(count, file);
    }
  }

  /// 更新任务已下载字节数与实时速度（指数滑动平均，平滑抖动）
  void _updateProgress(DownloadTaskModel task, int received) {
    task.downloaded = received;
    final s = _speed[task] ??= _DownloadSpeedState();
    final now = DateTime.now();
    final dt = now.difference(s.lastTime).inMilliseconds;
    if (dt >= 400) {
      final delta = (received - s.lastBytes) / (dt / 1000);
      s.speed = s.speed > 0 ? s.speed * 0.7 + delta * 0.3 : delta;
      s.lastBytes = received.toDouble();
      s.lastTime = now;
      task.speed = s.speed;
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
        if (t.status == DownloadStatus.downloading) {
          // 重启后下载已中断：部分文件若仍在，保留断点供手动「继续」
          t.status = DownloadStatus.failed;
          final partial = File(t.savePath);
          final exists = t.savePath.isNotEmpty && partial.existsSync();
          if (exists && partial.lengthSync() > 0) {
            t.downloaded = partial.lengthSync();
            if (t.totalSize > 0) {
              t.progress = t.downloaded / t.totalSize;
            }
            final mb = (t.downloaded / 1024 / 1024).toStringAsFixed(1);
            t.error = '下载中断（已下载 $mb MB，可继续）';
          } else {
            t.error = '下载已中断';
          }
        }
        tasks.add(t);
      }
      notifyListeners();
    } catch (_) {
      // 本地数据损坏时忽略，保留空列表
    }
    // 清理无主临时文件：仅删除没有对应任务的残留，
    // 有任务在跟踪的文件必须保留，否则断点续传失效。
    await _clearTempLeftovers();
  }

  /// 清理下载临时目录（files/CloudReve/.tmp）中的**无主**残留文件。
  ///
  /// 有任务在跟踪的部分文件必须保留，否则断点续传失效：
  /// 只删除那些路径没有出现在任何任务 savePath 中的文件。
  Future<void> _clearTempLeftovers() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final folder = Directory('${dir.path}${Platform.pathSeparator}CloudReve'
          '${Platform.pathSeparator}.tmp');
      if (!await folder.exists()) return;
      // 所有任务仍在使用的路径（含已完成，避免误删尚未转存的文件）
      final inUse = tasks.map((t) => _norm(t.savePath)).toSet();
      await for (final e in folder.list()) {
        if (e is! File) continue;
        if (inUse.contains(_norm(e.path))) continue;
        try {
          await e.delete();
        } catch (_) {}
      }
    } catch (_) {}
  }

  /// 路径归一（Windows 反斜杠与 Android 正斜杠统一比较）
  String _norm(String p) => p.replaceAll('\\', '/');

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
        t.status = DownloadStatus.paused;
        _tokens.remove(t)?.cancel();
      }
    }
    tasks.clear();
    _speed.clear();
    notifyListeners();
    _syncForeground(force: true);
    await restore();
  }

  /// 清空已完成 / 已取消 / 失败的历史记录（保留进行中的任务）
  Future<void> clearFinished() async {
    tasks.removeWhere((t) => t.status != DownloadStatus.downloading);
    _speed.removeWhere((t, _) => t.status != DownloadStatus.downloading);
    _notifyImmediate();
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
  ///
  /// [sourceUri] 为该文件在云端的 URI（cloudreve://...），仅用于展示缩略图；
  /// 缺失时列表回退为类型图标。
  Future<void> startDownload(String name, String url,
      {String sourceUri = ''}) async {
    final systemDownloads =
        await SpUtils.getString('downloadDirMode', 'system') == 'system';
    final task = DownloadTaskModel(
      name: name,
      savePath: '',
      sourceUrl: url,
      sourceUri: sourceUri,
      systemDownloads: systemDownloads,
    );
    tasks.add(task);
    _notifyImmediate();
    await _runDownload(task, systemDownloads: systemDownloads);
  }

  /// 暂停下载
  ///
  /// 保留已下载的部分文件，之后点「继续」可断点续传。
  /// 若不再需要该任务，用 [remove] 彻底删除并清理临时文件。
  void cancel(DownloadTaskModel task) {
    if (task.status != DownloadStatus.downloading) return;
    task.status = DownloadStatus.paused;
    _tokens.remove(task)?.cancel();
    _notifyImmediate();
  }

  /// 从列表彻底移除任务（用户放弃续传时调用）
  ///
  /// 未完成的临时文件一并清理，避免残留占用空间。
  Future<void> remove(DownloadTaskModel task) async {
    _tokens.remove(task)?.cancel();
    _speed.remove(task);
    tasks.remove(task);
    // 仅清理未完成的临时文件；已完成的下载属于用户资产，不删除
    if (task.status != DownloadStatus.finished && task.savePath.isNotEmpty) {
      try {
        final f = File(task.savePath);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
    _notifyImmediate();
  }

  /// 继续（失败 / 已暂停的任务）
  ///
  /// 已落盘的部分文件若仍存在，用 Range 从断点续传；否则从头下载。
  Future<void> retry(DownloadTaskModel task) async {
    if (task.sourceUrl.isEmpty) return;
    task.status = DownloadStatus.downloading;
    task.error = null;
    task.speed = 0;
    // 判断能否续传：部分文件仍存在且已有落盘字节
    final partial = File(task.savePath);
    final exists = task.savePath.isNotEmpty && partial.existsSync();
    var resumeFrom = 0;
    if (exists) {
      final onDisk = partial.lengthSync();
      if (onDisk > 0) {
        resumeFrom = onDisk;
        task.downloaded = onDisk;
        if (task.totalSize > 0) {
          task.progress = onDisk / task.totalSize;
        }
      }
    }
    if (resumeFrom == 0) {
      // 文件不存在或被清空：从头开始
      task.downloaded = 0;
      task.progress = 0;
      task.totalSize = 0;
    }
    _notifyImmediate();
    await _runDownload(task,
        systemDownloads: task.systemDownloads, resumeFrom: resumeFrom);
  }

  Future<void> _runDownload(DownloadTaskModel task,
      {bool systemDownloads = false, int resumeFrom = 0}) async {
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
    // 登记为「正在写入」：清理缓存时跳过该文件，避免下载中途被删
    AppCache.markActive(workingPath);
    try {
      // 断点续传：已有部分文件时用 Range 请求剩余字节，并以追加方式写入。
      // dio.download 只能整个文件覆盖写，无法追加，因此续传必须走手工流式写入。
      final canRange = resumeFrom > 0 && File(workingPath).existsSync();
      if (canRange) {
        await _downloadWithRange(task, workingPath, resumeFrom, token);
      } else {
        await _dio.download(
          task.sourceUrl,
          workingPath,
          cancelToken: token,
          // 必须显式关闭：dio 默认 true，会在失败/取消时删除已下载的部分文件，
          // 导致「继续」时无文件可续、只能从头下载。
          deleteOnError: false,
          onReceiveProgress: (received, total) {
            task.totalSize = total;
            task.progress = total > 0 ? received / total : 0;
            _updateProgress(task, received);
            _notifyThrottled();
          },
        );
      }
      task.progress = 1;
      task.downloaded = task.totalSize;
      task.speed = 0;
      if (systemDownloads) {
        task.savePath = await _moveToSystemDownloads(task.name, workingPath);
      }
      task.status = DownloadStatus.finished;
      _notifyImmediate();
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        task.status = DownloadStatus.paused;
      } else {
        task.status = DownloadStatus.failed;
        task.error = errorText(e, '网络错误');
        SmartDialog.showToast('下载「${task.name}」失败：${task.error}');
      }
      _notifyImmediate();
    } catch (e) {
      task.status = DownloadStatus.failed;
      task.error = errorText(e, '保存文件失败');
      SmartDialog.showToast('下载「${task.name}」失败：${task.error}');
      // 转入系统下载目录失败：清理临时文件
      if (systemDownloads) {
        final tmp = File(workingPath);
        if (tmp.existsSync()) tmp.deleteSync();
      }
      _notifyImmediate();
    } finally {
      AppCache.unmarkActive(workingPath);
      _tokens.remove(task);
      _speed.remove(task);
    }
  }

  /// 从指定字节偏移继续下载（Range 续传）。
  ///
  /// dio 的 `download` 只能整文件覆盖写，无法追加；这里手工发起请求并把
  /// 响应流追加到已存在的部分文件末尾。
  Future<void> _downloadWithRange(DownloadTaskModel task, String path,
      int resumeFrom, CancelToken token) async {
    final response = await _dio.get<ResponseBody>(
      task.sourceUrl,
      cancelToken: token,
      options: Options(
        headers: {'Range': 'bytes=$resumeFrom-'},
        responseType: ResponseType.stream,
      ),
    );

    final status = response.statusCode ?? 0;
    // 206 = 部分内容，符合续传预期
    if (status != 206) {
      // 服务端不支持 Range（或直链已变更）：退回整体重下
      final total = int.tryParse(
              response.headers.value(Headers.contentLengthHeader) ?? '') ??
          0;
      await _dio.download(
        task.sourceUrl,
        path,
        cancelToken: token,
        onReceiveProgress: (received, t) {
          task.totalSize = t;
          task.progress = t > 0 ? received / t : 0;
          _updateProgress(task, received);
          _notifyThrottled();
        },
      );
      if (total == 0) {
        task.totalSize = File(path).lengthSync();
      }
      return;
    }

    // 从 Content-Range 解析完整文件大小，用于进度换算
    final cr = response.headers.value('content-range') ?? '';
    var totalSize = task.totalSize;
    final m = RegExp(r'/\s*(\d+)').firstMatch(cr);
    if (m != null) {
      totalSize = int.tryParse(m.group(1) ?? '') ?? totalSize;
    }
    task.totalSize = totalSize;

    final raf = await File(path).open(mode: FileMode.append);
    var received = resumeFrom;
    try {
      await for (final chunk in response.data!.stream) {
        raf.writeFromSync(chunk);
        received += chunk.length;
        task.downloaded = received;
        task.progress = totalSize > 0 ? received / totalSize : 0;
        _updateProgress(task, received);
        _notifyThrottled();
      }
      await raf.flush();
    } finally {
      await raf.close();
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

/// 单个任务的实时下载速度计算状态
class _DownloadSpeedState {
  double lastBytes = 0;
  DateTime lastTime = DateTime.now();
  double speed = 0;
}
