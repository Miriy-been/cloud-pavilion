import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:cloudpavilion/api/FileApi.dart';
import 'package:cloudpavilion/exception/BusinessException.dart';
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

  // ---------- 断点续传 ----------
  //
  // 断网 / 失败后**不自动重连续传**，只保留会话与进度，由用户手动点「重试」
  // 时从断点继续。自动恢复会在用户已经转向其它事情时突然开始传输，
  // 占用带宽并打断当前操作，体验上更差。

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
        if (t.status == UploadStatus.uploading) {
          // 重启后会话仍在有效期内且有传输进展 → 保留断点，等用户手动重试；
          // 否则彻底中断、从头开始。
          // 不要求「至少完成一片」：大分片下可能一片未完成但进度有效。
          if (t.canResume && t.resumeDisplayedBytes > 0) {
            t.status = UploadStatus.failed;
            final mb = (t.resumeDisplayedBytes / 1024 / 1024)
                .toStringAsFixed(1);
            t.error = '上传中断（已传 $mb MB，可重试继续）';
          } else {
            t.status = UploadStatus.failed;
            t.error = '上传已中断';
            t.clearResumeContext();
          }
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

  /// 持久化串行链：分片级持久化频率较高（每片一次），且多个任务并发
  /// 上传时会同时调用 _persist。串行化避免整表 JSON 交错写入导致数据损坏。
  Future<void> _persistChain = Future.value();

  /// 持久化全部任务记录
  Future<void> _persist() {
    _persistChain = _persistChain.then((_) async {
      try {
        await SpUtils.setString(await _tasksKey(),
            jsonEncode(tasks.map((t) => t.toJson()).toList()));
      } catch (_) {
        // 落盘失败不影响上传本身：内存中的进度仍可用于本次续传
      }
    });
    return _persistChain;
  }

  /// 切换账号：停止旧账号进行中的任务并加载新账号的任务记录。
  /// 必须在当前账号上下文（CurrentBaseUrl / currentUserName）已更新后调用；
  /// 停止任务时不触发持久化，避免旧账号任务写入新账号的 key
  Future<void> switchAccount() async {
    for (final t in List.of(tasks)) {
      if (t.status == UploadStatus.uploading) {
        t.status = UploadStatus.paused;
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

  /// 暂停上传（排队中的任务被跳过，进行中的任务中断）
  ///
  /// 暂停保留服务端会话与已传分片，之后点「继续」可从断点续传。
  /// 若不再需要该任务，用 [remove] 彻底删除。
  void cancel(UploadTaskModel task) {
    if (task.status != UploadStatus.uploading) return;
    task.status = UploadStatus.paused;
    _tokens.remove(task)?.cancel();
    _speed.remove(task);
    _notifyImmediate();
  }

  /// 从列表彻底移除任务（用户放弃续传时调用）
  ///
  /// 会释放服务端会话，避免目标文件名被长期占用。
  Future<void> remove(UploadTaskModel task) async {
    _tokens.remove(task)?.cancel();
    _speed.remove(task);
    final sessionId = task.sessionId;
    tasks.remove(task);
    _queue.remove(task);
    // 释放服务端会话：放弃续传后目标 URI 不应再被占用
    if (sessionId != null && sessionId.isNotEmpty) {
      try {
        await FileApi.deleteUploadSession(sessionId, task.uri);
      } catch (_) {
        // 释放失败不阻塞：残留会话由服务端 TTL 过期回收
      }
    }
    _notifyImmediate();
  }

  /// 继续（失败 / 已暂停且源文件仍在的任务）
  ///
  /// 若会话仍有效，保留已上传分片从断点续传；否则清空上下文从头传。
  Future<void> retry(UploadTaskModel task) async {
    if (!File(task.sourcePath).existsSync()) return;
    task.status = UploadStatus.uploading;
    task.error = null;
    task.speed = 0;
    // 会话过期则重置进度；仍有效则保留 uploadedChunks 以便续传
    if (!task.canResume) {
      task.clearResumeContext();
      task.progress = 0;
      task.uploaded = 0;
    }
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
      // 续传判定：会话仍有效则复用，跳过已上传分片；否则新建会话从头传
      UploadSessionInfo session;
      if (task.canResume) {
        session = UploadSessionInfo(
          sessionId: task.sessionId!,
          chunkSize: task.chunkSize,
          expiresAtMs: task.sessionExpiresAt!,
        );
        // 恢复进度显示：已完成分片 + 中断时本片已发部分，
        // 避免续传瞬间进度条从 10% 跳回 0%
        _updateProgress(task, task.resumeDisplayedBytes);
      } else {
        task.clearResumeContext();
        session = await _createSession(task);
        task
          ..sessionId = session.sessionId
          ..chunkSize = session.chunkSize
          ..sessionExpiresAt = session.expiresAtMs;
        await _persist();
      }
      _sessions[task] = session.sessionId;

      if (session.chunkSize <= 0) {
        // 不分片：整文件作为 index 0 一次上传（该模式下无法按分片续传）
        final bytes = await f.readAsBytes();
        await FileApi.uploadChunk(
          session.sessionId,
          0,
          bytes,
          cancelToken: token,
          onSendProgress: (sent, total) {
            task.progress = total > 0 ? sent / total : 0;
            _updateProgress(task, sent);
          },
        );
        task.uploadedChunks = [0];
      } else {
        await _uploadChunked(task, f, session, token);
      }

      task.status = UploadStatus.finished;
      task.progress = 1;
      task.uploaded = task.size;
      task.speed = 0;
      // 上传完成：会话已在服务端结束，本地续传上下文不再需要
      task.clearResumeContext();
      // 上传完成：文件列表缓存失效，返回目录时可见新文件
      FileApi.invalidateListCache();
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        task.status = UploadStatus.paused;
        // 用户主动取消 = 暂停：**保留**会话与已传分片，允许之后从断点续传。
        // 会话本身有服务端 TTL，过期后 canResume 会自然失效并从头开始。
        _sessions.remove(task);
      } else {
        await _handleFailure(task, e, errorText(e, '网络错误'));
      }
    } catch (e) {
      await _handleFailure(task, e, errorText(e, '未知错误'));
    } finally {
      _tokens.remove(task);
      _speed.remove(task);
      _sessions.remove(task); // 上传成功时仅清引用，不删服务端会话
      _notifyImmediate();
      // 任务已进入终态：目录内容可能已变化，通知文件列表页刷新一次
      listChanged.value++;
    }
  }

  /// 创建上传会话（含过期时间解析）
  Future<UploadSessionInfo> _createSession(UploadTaskModel task) async {
    final raw = await FileApi.createUploadSession(task.uri, task.size);
    final expiresRaw = raw['expires'];
    // 服务端 expires 可能是秒级 unix 时间戳或毫秒时间戳，统一归一到毫秒
    int expiresAtMs = 0;
    if (expiresRaw is num) {
      expiresAtMs = expiresRaw > 100000000000
          ? expiresRaw.toInt()
          : expiresRaw.toInt() * 1000;
    }
    debugPrint('[上传] 会话 chunk_size=${raw['chunk_size']} '
        '剩余有效 ${(expiresAtMs - DateTime.now().millisecondsSinceEpoch) ~/ 1000}s');
    return UploadSessionInfo(
      sessionId: raw['session_id'] as String,
      chunkSize: (raw['chunk_size'] ?? 0) as int,
      expiresAtMs: expiresAtMs,
    );
  }

  /// 分片上传：逐片上传、每片完成后持久化进度、失败按片重试
  Future<void> _uploadChunked(UploadTaskModel task, File f,
      UploadSessionInfo session, CancelToken token) async {
    final raf = await f.open();
    try {
      final total = (task.size + session.chunkSize - 1) ~/ session.chunkSize;
      // 本轮实际发送的分片数：用于区分「刚传完」与「上次已传完需收尾」
      var uploadedThisRound = 0;
      for (var index = 0; index < total; index++) {
        // 续传：跳过已确认上传的分片
        if (task.uploadedChunks.contains(index)) continue;

        final offset = index * session.chunkSize;
        final len = (offset + session.chunkSize > task.size)
            ? (task.size - offset)
            : session.chunkSize;
        await raf.setPosition(offset);
        final bytes = await raf.read(len);

        // 分片内实时回调：chunk_size 可能很大（一个大分片即整段上传），
        // 若不传 onSendProgress，进度只能在该分片整体完成后更新一次，
        // 表现为进度条长期停留在 0% 直到最后直接变成「上传完成」。
        // 片内进度归零：本片即将从头发送
        task.currentChunkSent = 0;
        await _uploadChunkWithRetry(
          task,
          session.sessionId,
          index,
          bytes,
          token,
          onProgress: (sent) {
            // 记录片内进度：中断后重试时据此恢复显示，不让进度跳回 0%
            task.currentChunkSent = sent;
            // 用 offset + sent 折算全局已上传字节，保证整个上传过程实时刷新
            task.progress =
                task.size > 0 ? (offset + sent) / task.size : 0;
            _updateProgress(task, offset + sent);
          },
        );

        // 该片完成：把已发字节计入已完成分片，清零片内进度
        task.currentChunkSent = 0;

        // 每片成功即记账并落盘：中断后可从该片之后继续
        task.uploadedChunks.add(index);
        uploadedThisRound++;
        task.progress = (offset + len) / task.size;
        _updateProgress(task, offset + len);
        await _persist();
      }

      // 所有分片都已在本地记账，且**本轮没有真正上传任何分片**：
      // 说明上次已传完但收尾请求失败（服务端只在收到缺失分片时才触发
      // CompleteUpload），此时重传最后一片以触发收尾。
      //
      // 注意必须限定「本轮零上传」：若最后一片是本次刚传的，服务端已
      // 完成上传并销毁会话，再发一次会得到 400（会话不存在）。
      if (uploadedThisRound == 0 &&
          total > 0 &&
          task.uploadedChunks.length >= total) {
        final lastIndex = total - 1;
        final offset = lastIndex * session.chunkSize;
        final len = (offset + session.chunkSize > task.size)
            ? (task.size - offset)
            : session.chunkSize;
        await raf.setPosition(offset);
        final bytes = await raf.read(len);
        await _uploadChunkWithRetry(
          task,
          session.sessionId,
          lastIndex,
          bytes,
          token,
          onProgress: (_) {},
        );
      }
    } finally {
      await raf.close();
    }
  }

  /// 单个分片上传，失败时按指数退避重试（与官方 Web 端一致：最多 3 次）
  Future<void> _uploadChunkWithRetry(
    UploadTaskModel task,
    String sessionId,
    int index,
    Uint8List bytes,
    CancelToken token, {
    required void Function(int sent) onProgress,
  }) async {
    const maxRetries = 3;
    for (var attempt = 0;; attempt++) {
      try {
        await FileApi.uploadChunk(
          sessionId,
          index,
          bytes,
          cancelToken: token,
          onSendProgress: (sent, _) => onProgress(sent),
        );
        return;
      } catch (e) {
        if (e is DioException && CancelToken.isCancel(e)) rethrow;
        // 分片重试期间网络抖动：指数退避 1s / 2s / 4s
        final retryable = _isRetryableChunkError(e);
        if (!retryable || attempt >= maxRetries) rethrow;
        await Future.delayed(Duration(seconds: 1 << attempt));
        if (token.isCancelled) {
          // 退避等待期间被取消：抛出可被上层识别的取消异常
          throw DioException(
            requestOptions: RequestOptions(path: ''),
            type: DioExceptionType.cancel,
            error: 'cancelled',
          );
        }
      }
    }
  }

  /// 分片错误是否值得重试：网络类错误重试；会话过期 / 分片越界等业务错误不重试，
  /// 交由上层重建会话
  bool _isRetryableChunkError(Object e) {
    if (e is! DioException) return false;
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
      case DioExceptionType.unknown:
        return true;
      case DioExceptionType.badResponse:
        // 5xx 可重试；4xx（会话过期 40011 / 分片越界 40012 等）不重试
        final code = e.response?.statusCode ?? 0;
        return code >= 500;
      default:
        return false;
    }
  }

  /// 上传失败处理：保留可续传的会话，仅当会话已失效时才丢弃
  Future<void> _handleFailure(
      UploadTaskModel task, Object e, String message) async {
    task.status = UploadStatus.failed;
    task.error = message;
    // 会话过期 / 分片越界：本地记账已不可信，清空上下文让下次重试重建会话
    if (_isSessionInvalid(e)) {
      task.clearResumeContext();
      _releaseSession(task);
    }
    // 其它失败（断网、超时）**不释放会话**：保留 session_id + 已传分片，
    // 用户点重试即可从断点继续，而不是从头再传一遍。
    final canResume = task.canResume;
    // 已传字节 = 已完成分片 + 中断时本片已发部分。
    // 注意：本片未完成时服务端未接收，重试需整片重传，这里仅用于展示。
    final sentBytes = task.resumeDisplayedBytes;
    // 只要会话仍有效且有过任何传输进展，就提示可续传。
    // 不能要求「至少完成一片」：大分片（如 25MB）下断网时可能一片都没完成，
    // 但会话与已传进度依然有效，重试会从最近的分片边界继续。
    if (canResume && sentBytes > 0) {
      final sentMb = (sentBytes / 1024 / 1024).toStringAsFixed(1);
      final totalMb = (task.size / 1024 / 1024).toStringAsFixed(1);
      task.error = '$message（已传 $sentMb/$totalMb MB，可重试继续）';
    }
    await _persist();
    SmartDialog.showToast('上传「${task.name}」失败：${task.error}');
  }

  /// 是否为「会话已失效」类错误（服务端业务码 40011 / 40012）
  bool _isSessionInvalid(Object e) {
    if (e is BusinessException) {
      return e.code == 40011 || e.code == 40012;
    }
    if (e is DioException) {
      final body = e.response?.data;
      if (body is Map) {
        final code = body['code'];
        return code == 40011 || code == 40012;
      }
    }
    return false;
  }
}

/// 单个任务的实时速度计算状态
class _SpeedState {
  double lastBytes = 0;
  DateTime lastTime = DateTime.now();
  double speed = 0;
}

/// 上传会话信息（从服务端创建会话响应中提取的最小集合）
class UploadSessionInfo {
  final String sessionId;
  final int chunkSize;

  /// 过期时间（毫秒时间戳；0 表示服务端未返回）
  final int expiresAtMs;

  const UploadSessionInfo({
    required this.sessionId,
    required this.chunkSize,
    required this.expiresAtMs,
  });
}