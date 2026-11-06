import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:cloudpavilion/api/FileApi.dart';
import 'package:cloudpavilion/model/UploadTaskModel.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'ErrorText.dart';
import 'SpUtils.dart';
import 'UploadForegroundService.dart';

/// 后台上传任务管理器（全局单例）
/// 上传在后台执行，不阻塞页面；任务增删 / 状态变化时通知监听者，
/// 进度高频回调时进行节流通知。
/// 多文件支持**并行上传**：按队列依次分发，同时最多并行 _maxConcurrent 个（默认 5，
/// 可自定义 1~20）。排队中的任务状态同为「上传中」，但一次只启动限定的并发数，
/// 避免一次性并发过多导致服务端报错。
class UploadManager extends ChangeNotifier {
  UploadManager._();
  static final UploadManager instance = UploadManager._();

  /// 任务记录本地持久化 key 前缀（按账号隔离，站点+用户名 维度）
  static const _kTasksKey = 'uploadTasks';

  /// 当前账号的任务持久化 key
  Future<String> _tasksKey() async {
    final siteUrl = await SpUtils.getString('CurrentBaseUrl');
    final userName = await SpUtils.getString('currentUserName');
    return siteUrl.isEmpty || userName.isEmpty
        ? _kTasksKey
        : '${_kTasksKey}_$siteUrl|$userName';
  }

  final List<UploadTaskModel> tasks = [];
  final Map<UploadTaskModel, CancelToken> _tokens = {};

  /// 每个任务当前创建的上传会话（session_id），用于取消 / 失败时释放服务器端占用的名称
  final Map<UploadTaskModel, String> _sessions = {};

  /// 待处理（含排队等待）的上传任务
  final List<UploadTaskModel> _queue = [];

  /// 当前正在并发上传的任务数
  int _running = 0;

  /// 最大并行上传数量（默认 5，可自定义 1~20）
  int _maxConcurrent = 5;

  int get maxConcurrent => _maxConcurrent;

  /// 每个任务的上传速度计算状态
  final Map<UploadTaskModel, _SpeedState> _speed = {};

  /// 进度节流：上次通知时间
  DateTime _lastNotify = DateTime.fromMillisecondsSinceEpoch(0);

  /// 上传前台服务是否已启动
  bool _fgActive = false;

  /// 前台通知更新节流：上次更新时间
  DateTime _lastFgUpdate = DateTime.fromMillisecondsSinceEpoch(0);

  /// 任务列表结构变化（上传结束：完成 / 失败 / 取消）时递增的通知。
  ///
  /// 供文件列表页监听以刷新目录。**进度更新不会触发它** ——
  /// 进度回调每 250ms 就会 notifyListeners 一次，若列表页直接监听
  /// [UploadManager] 本身，上传期间会持续以同样频率重新拉取一次目录。
  final ValueNotifier<int> listChanged = ValueNotifier(0);

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

  /// 同步上传前台服务：有任务上传中时启动 / 更新常驻通知，全部结束后自动停止。
  /// [force] 用于状态变化（任务增删、完成）时的即时同步；进度更新走下面的 1s 节流。
  void _syncForeground({bool force = false}) {
    final active =
        tasks.where((t) => t.status == UploadStatus.uploading).toList();
    if (active.isEmpty) {
      if (_fgActive) {
        _fgActive = false;
        UploadForegroundService.stop();
      }
      return;
    }
    // 进度更新最多每秒通知一次，避免频繁刷新系统通知
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
      UploadForegroundService.update(count, file, percent);
    } else {
      _fgActive = true;
      UploadForegroundService.start(count, file);
    }
  }

  /// 恢复历史任务记录（应用启动 / 切换账号时调用）
  Future<void> restore() async {
    // 加载自定义并行数量（全局设置）
    final saved = await SpUtils.getInt('uploadConcurrency', 5);
    _maxConcurrent = saved.clamp(1, 20).toInt();
    final raw = await SpUtils.getString(await _tasksKey());
    if (raw.isEmpty) return;
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      for (final e in list) {
        final t = UploadTaskModel.fromJson(e as Map<String, dynamic>);
        // 重启后未完成任务无法续传，标记为中断失败
        if (t.status == UploadStatus.uploading) {
          t.status = UploadStatus.failed;
          t.error = '上传已中断';
        }
        tasks.add(t);
      }
      notifyListeners();
    } catch (_) {
      // 本地数据损坏时忽略，保留空列表
    }
    // 恢复出的任务可能含新完成项，令目录刷新一次
    listChanged.value++;
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
      if (t.status == UploadStatus.uploading) {
        t.status = UploadStatus.cancelled;
        _tokens.remove(t)?.cancel();
      }
    }
    tasks.clear();
    _queue.clear();
    _speed.clear();
    _sessions.clear();
    notifyListeners();
    listChanged.value++;
    _syncForeground(force: true);
    await restore();
  }

  /// 清空已完成 / 已取消 / 失败的历史记录（保留进行中的任务）
  Future<void> clearFinished() async {
    tasks.removeWhere((t) => t.status != UploadStatus.uploading);
    _speed.removeWhere((t, _) => t.status != UploadStatus.uploading);
    _sessions.removeWhere((t, _) => t.status != UploadStatus.uploading);
    _notifyImmediate();
  }

  /// 开始上传一个文件（后台执行，加入队列，由并行分发器按并发数调度）
  Future<void> startUpload({
    required String name,
    required String uri,
    required String sourcePath,
    required int size,
  }) async {
    final task = UploadTaskModel(
      name: name,
      uri: uri,
      sourcePath: sourcePath,
      size: size,
    );
    tasks.add(task);
    _queue.add(task);
    _notifyImmediate();
    _pump();
  }

  /// 取消上传任务（排队中的任务被跳过，进行中的任务中断）
  void cancel(UploadTaskModel task) {
    if (task.status != UploadStatus.uploading) return;
    task.status = UploadStatus.cancelled;
    _tokens.remove(task)?.cancel();
    _speed.remove(task);
    _notifyImmediate();
  }

  /// 重试（失败 / 已取消且源文件仍在的任务）
  Future<void> retry(UploadTaskModel task) async {
    if (!File(task.sourcePath).existsSync()) return;
    task.status = UploadStatus.uploading;
    task.error = null;
    task.progress = 0;
    task.uploaded = 0;
    task.speed = 0;
    _notifyImmediate();
    _queue.add(task);
    _pump();
  }

  /// 并行分发队列：在未达到并发上限时，从队列取出任务开始上传。
  /// 每个任务上传结束（含失败 / 取消）后自动补跑一次，继续填满并发额度。
  void _pump() {
    while (_queue.isNotEmpty && _running < _maxConcurrent) {
      final task = _queue.removeAt(0);
      // 排队期间可能被取消（换个账号 / 用户主动取消），此时跳过
      if (task.status != UploadStatus.uploading) continue;
      _running++;
      _runUpload(task).whenComplete(() {
        _running--;
        _pump();
      });
    }
  }

  /// 设置最大并行上传数量（1~20），持久化并立即应用
  void setMaxConcurrent(int n) {
    final v = n.clamp(1, 20).toInt();
    if (v == _maxConcurrent) return;
    _maxConcurrent = v;
    SpUtils.setInt('uploadConcurrency', _maxConcurrent);
    notifyListeners();
    // 并发数调大时，让仍排队的任务立即补位；调小时无需干预（自动限流）
    _pump();
  }

  /// 更新任务已上传字节数与实时速度（并节流通知）
  void _updateProgress(UploadTaskModel task, int uploaded) {
    task.uploaded = uploaded;
    final s = _speed[task] ??= _SpeedState();
    final now = DateTime.now();
    final dt = now.difference(s.lastTime).inMilliseconds;
    if (dt >= 400) {
      final delta = (uploaded - s.lastBytes) / (dt / 1000);
      // 指数滑动平均：平滑抖动，实时反馈当前速率
      s.speed = s.speed > 0 ? s.speed * 0.7 + delta * 0.3 : delta;
      s.lastBytes = uploaded.toDouble();
      s.lastTime = now;
      task.speed = s.speed;
    }
    _notifyThrottled();
  }

  /// 通知服务器释放指定任务的上传会话（取消 / 失败后调用）。
  /// 若不上报，目标名称持续被服务器占用，重试或再次上传同名文件会提示「同名对象已存在」。
  /// 已完成的上传不调用（会话已结束，无需释放）。
  void _releaseSession(UploadTaskModel task, {int delayMs = 0}) {
    final sessionId = _sessions.remove(task);
    if (sessionId == null || sessionId.isEmpty) return;
    // 取消时稍作延迟，等本地中断的请求先松开，避免与服务端处理冲突
    Future.delayed(Duration(milliseconds: delayMs), () async {
      try {
        await FileApi.deleteUploadSession(sessionId, task.uri);
      } catch (_) {
        // 释放失败不阻塞：残留会话由服务端 TTL 过期自动回收
      }
    });
  }

  Future<void> _runUpload(UploadTaskModel task) async {
    final token = CancelToken();
    _tokens[task] = token;
    _speed[task] = _SpeedState();
    final f = File(task.sourcePath);
    try {
      final session = await FileApi.createUploadSession(task.uri, task.size);
      final sessionId = session['session_id'] as String;
      final chunkSize = (session['chunk_size'] ?? 0) as int;
      _sessions[task] = sessionId;

      if (chunkSize <= 0) {
        // 不分片：整文件作为 index 0 一次上传
        final bytes = await f.readAsBytes();
        await FileApi.uploadChunk(
          sessionId,
          0,
          bytes,
          cancelToken: token,
          onSendProgress: (sent, total) {
            task.progress = total > 0 ? sent / total : 0;
            _updateProgress(task, sent);
          },
        );
      } else {
        final raf = await f.open();
        try {
          var index = 0;
          var offset = 0;
          while (offset < task.size) {
            final len = (offset + chunkSize > task.size)
                ? (task.size - offset)
                : chunkSize;
            await raf.setPosition(offset);
            final bytes = await raf.read(len);
            // 分片内实时回调：chunk_size 可能很大（一个大分片即整段上传），
            // 若不传 onSendProgress，进度只能在该分片整体完成后更新一次，
            // 表现为进度条长期停留在 0% 直到最后直接变成「上传完成」。
            // 用 offset + sent 折算全局已上传字节，保证整个上传过程实时刷新。
            await FileApi.uploadChunk(
              sessionId,
              index,
              bytes,
              cancelToken: token,
              onSendProgress: (sent, _) {
                task.progress =
                    task.size > 0 ? (offset + sent) / task.size : 0;
                _updateProgress(task, offset + sent);
              },
            );
            offset += len;
            index++;
            task.progress = offset / task.size;
            _updateProgress(task, offset);
          }
        } finally {
          await raf.close();
        }
      }
      task.status = UploadStatus.finished;
      task.progress = 1;
      task.uploaded = task.size;
      task.speed = 0;
      // 上传完成：文件列表缓存失效，返回目录时可见新文件
      FileApi.invalidateListCache();
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        task.status = UploadStatus.cancelled;
        // 用户取消：释放服务器会话，避免同名文件重试时提示「同名对象已存在」
        _releaseSession(task, delayMs: 500);
      } else {
        task.status = UploadStatus.failed;
        task.error = errorText(e, '网络错误');
        // 上传失败：释放会话，让重试可以重新创建同名会话
        _releaseSession(task);
        SmartDialog.showToast('上传「${task.name}」失败：${task.error}');
      }
    } catch (e) {
      task.status = UploadStatus.failed;
      task.error = errorText(e, '未知错误');
      _releaseSession(task);
      SmartDialog.showToast('上传「${task.name}」失败：${task.error}');
    } finally {
      _tokens.remove(task);
      _speed.remove(task);
      _sessions.remove(task); // 上传成功时仅清引用，不删服务端会话
      _notifyImmediate();
      // 任务已进入终态：目录内容可能已变化，通知文件列表页刷新一次
      listChanged.value++;
    }
  }
}

/// 单个任务的实时速度计算状态
class _SpeedState {
  double lastBytes = 0;
  DateTime lastTime = DateTime.now();
  double speed = 0;
}