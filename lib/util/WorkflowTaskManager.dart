import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_application_2/api/FileApi.dart';
import 'package:flutter_application_2/api/WorkflowApi.dart';
import 'package:flutter_application_2/page/tools/customToast.dart';
import 'package:flutter_application_2/util/SpUtils.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

/// 服务器端后台任务跟踪器（压缩 / 解压等，全局单例）
///
/// - 创建任务后调用 [track] 开始后台轮询，不阻塞任何操作；
/// - 完成 / 失败 / 状态未知时全局 toast 提示，并失效列表缓存 + 通知监听方刷新；
/// - 任务记录持久化：App 重启后 [restore] 恢复跟踪，直到出结果。
class WorkflowTaskManager extends ChangeNotifier {
  WorkflowTaskManager._();
  static final WorkflowTaskManager instance = WorkflowTaskManager._();

  /// 跟踪中的任务记录持久化 key
  static const _kTasksKey = 'workflowTasks';

  /// 跟踪中的任务：taskId → 操作描述（如「压缩 archive.zip」）
  final Map<String, String> _tasks = {};
  final Map<String, Timer> _timers = {};

  /// 连续找不到任务的次数（任务可能被服务器清理，达到阈值后放弃跟踪）
  final Map<String, int> _missingCount = {};

  /// 找不到任务的最大连续次数（5s 间隔 × 60 ≈ 5 分钟）
  static const _maxMissing = 60;

  bool _restored = false;

  /// 当前跟踪中的任务数
  int get activeCount => _tasks.length;

  /// 注册一个任务开始跟踪
  void track(String taskId, String description) {
    if (taskId.isEmpty) return;
    if (_tasks.containsKey(taskId)) return;
    _tasks[taskId] = description;
    _missingCount[taskId] = 0;
    _persist();
    notifyListeners();
    _schedulePoll(taskId, first: true);
  }

  /// 恢复历史任务跟踪（应用启动时调用）
  Future<void> restore() async {
    if (_restored) return;
    _restored = true;
    final raw = await SpUtils.getString(_kTasksKey);
    if (raw.isEmpty) return;
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      for (final e in list) {
        final m = e as Map<String, dynamic>;
        final id = m['id']?.toString() ?? '';
        final desc = m['desc']?.toString() ?? '';
        if (id.isEmpty || _tasks.containsKey(id)) continue;
        _tasks[id] = desc;
        _missingCount[id] = 0;
      }
    } catch (_) {}
    if (_tasks.isNotEmpty) {
      notifyListeners();
      for (final id in _tasks.keys) {
        _schedulePoll(id, first: true);
      }
    }
  }

  void _persist() {
    final list = _tasks.entries
        .map((e) => {'id': e.key, 'desc': e.value})
        .toList();
    SpUtils.setString(_kTasksKey, jsonEncode(list));
  }

  void _schedulePoll(String id, {bool first = false}) {
    _timers[id]?.cancel();
    _timers[id] = Timer(Duration(seconds: first ? 1 : 5), () => _poll(id));
  }

  Future<void> _poll(String id) async {
    if (!_tasks.containsKey(id)) return;
    Map<String, dynamic>? task;
    try {
      task = await WorkflowApi.findTaskById(id);
    } catch (_) {}
    if (!_tasks.containsKey(id)) return;

    final status = task?['status']?.toString() ?? '';
    if (status == 'completed') {
      _finish(id, ok: true);
    } else if (status == 'error' ||
        status == 'failed' ||
        status == 'cancelled') {
      _finish(id, ok: false);
    } else if (task == null) {
      // 找不到任务：可能已被服务器清理，连续多次后放弃并提示
      final miss = (_missingCount[id] ?? 0) + 1;
      _missingCount[id] = miss;
      if (miss >= _maxMissing) {
        _finish(id, ok: false, unknown: true);
        return;
      }
      _schedulePoll(id);
    } else {
      // 仍在处理：继续轮询，直到出结果
      _schedulePoll(id);
    }
  }

  void _finish(String id, {required bool ok, bool unknown = false}) {
    final desc = _tasks.remove(id) ?? '';
    _timers[id]?.cancel();
    _timers.remove(id);
    _missingCount.remove(id);
    _persist();
    // 列表缓存失效：压缩包 / 解压结果出现后重新拉取
    FileApi.invalidateListCache();
    final label = desc.isEmpty ? '后台任务' : desc;
    final msg = ok
        ? '$label 已完成'
        : unknown
            ? '$label 状态未知，请稍后查看'
            : '$label 失败';
    // 成功浅绿 / 失败浅红 / 状态未知浅黄
    final type = ok
        ? ToastType.success
        : unknown
            ? ToastType.warning
            : ToastType.error;
    SmartDialog.showToast(msg, builder: (ctx) => CustomToast(msg, type: type));
    notifyListeners();
  }
}
