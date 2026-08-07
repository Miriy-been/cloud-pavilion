import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_application_2/api/FileApi.dart';
import 'package:flutter_application_2/model/UploadTaskModel.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'ErrorText.dart';
import 'SpUtils.dart';

/// 后台上传任务管理器（全局单例）
/// 上传在后台执行，不阻塞页面；任务增删 / 状态变化时通知监听者，
/// 进度高频回调时进行节流通知
class UploadManager extends ChangeNotifier {
  UploadManager._();
  static final UploadManager instance = UploadManager._();

  /// 任务记录本地持久化 key
  static const _kTasksKey = 'uploadTasks';

  final List<UploadTaskModel> tasks = [];
  final Map<UploadTaskModel, CancelToken> _tokens = {};

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

  /// 恢复历史任务记录（应用启动时调用）
  Future<void> restore() async {
    final raw = await SpUtils.getString(_kTasksKey);
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
  }

  /// 持久化全部任务记录
  Future<void> _persist() async {
    await SpUtils.setString(
        _kTasksKey, jsonEncode(tasks.map((t) => t.toJson()).toList()));
  }

  /// 开始上传一个文件（后台执行）
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
    _notifyImmediate();
    await _runUpload(task);
  }

  /// 取消上传任务
  void cancel(UploadTaskModel task) {
    if (task.status != UploadStatus.uploading) return;
    task.status = UploadStatus.cancelled;
    _tokens.remove(task)?.cancel();
    _notifyImmediate();
  }

  /// 重试（失败 / 已取消且源文件仍在的任务）
  Future<void> retry(UploadTaskModel task) async {
    if (!File(task.sourcePath).existsSync()) return;
    task.status = UploadStatus.uploading;
    task.error = null;
    task.progress = 0;
    _notifyImmediate();
    await _runUpload(task);
  }

  Future<void> _runUpload(UploadTaskModel task) async {
    final token = CancelToken();
    _tokens[task] = token;
    final f = File(task.sourcePath);
    try {
      final session = await FileApi.createUploadSession(task.uri, task.size);
      final sessionId = session['session_id'] as String;
      final chunkSize = (session['chunk_size'] ?? 0) as int;

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
            _notifyThrottled();
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
            await FileApi.uploadChunk(sessionId, index, bytes,
                cancelToken: token);
            offset += len;
            index++;
            task.progress = offset / task.size;
            _notifyThrottled();
          }
        } finally {
          await raf.close();
        }
      }
      task.status = UploadStatus.finished;
      task.progress = 1;
      // 上传完成：文件列表缓存失效，返回目录时可见新文件
      FileApi.invalidateListCache();
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        task.status = UploadStatus.cancelled;
      } else {
        task.status = UploadStatus.failed;
        task.error = e.toString();
        SmartDialog.showToast('上传「${task.name}」失败：${errorText(e, '网络错误')}');
      }
    } catch (e) {
      task.status = UploadStatus.failed;
      task.error = e.toString();
      SmartDialog.showToast('上传「${task.name}」失败：${errorText(e, '未知错误')}');
    } finally {
      _tokens.remove(task);
      _notifyImmediate();
    }
  }
}
