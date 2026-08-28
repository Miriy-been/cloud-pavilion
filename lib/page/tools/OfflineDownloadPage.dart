import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloudpavilion/api/FileApi.dart';
import 'package:cloudpavilion/api/WorkflowApi.dart';
import 'package:cloudpavilion/config/AppTheme.dart';
import 'package:cloudpavilion/config/AppWidgets.dart';
import 'package:cloudpavilion/model/RemoteDownloadTaskModel.dart';
import 'package:cloudpavilion/page/tools/FolderPicker.dart';
import 'package:cloudpavilion/util/ErrorText.dart';
import 'package:cloudpavilion/util/SpUtils.dart';
import 'package:cloudpavilion/util/WorkflowTaskManager.dart';

/// 离线下载页：查看服务器后台离线下载任务（进行中 + 已完成）
///
/// 功能对齐网页版 /downloads 页：
/// - 进行中任务实时展示进度（速度 · 已下载/总量），可取消；
/// - 已完成 / 失败 / 已取消任务归入「已完成」区；
/// - 有进行中任务时每 5s 自动轮询刷新，也可手动刷新 / 下拉刷新；
/// - 右上「新建」与悬浮按钮均可发起新的离线下载。
class OfflineDownloadPage extends StatefulWidget {
  const OfflineDownloadPage({super.key});

  @override
  State<OfflineDownloadPage> createState() => _OfflineDownloadPageState();
}

class _OfflineDownloadPageState extends State<OfflineDownloadPage> {
  List<RemoteDownloadTaskModel> _active = [];
  List<RemoteDownloadTaskModel> _finished = [];
  bool _loading = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// 加载进行中 + 已完成的离线下载任务
  Future<void> _load() async {
    // 首次加载显示全屏加载态；后台轮询静默更新，避免频繁闪烁
    final first = _active.isEmpty && _finished.isEmpty;
    if (first && mounted) setState(() => _loading = true);
    try {
      final results = await Future.wait([
        WorkflowApi.listRemoteDownloads(category: 'downloading'),
        WorkflowApi.listRemoteDownloads(category: 'downloaded'),
      ]);
      if (!mounted) return;
      setState(() {
        _active = results[0]
            .map(RemoteDownloadTaskModel.fromJson)
            .toList();
        _finished = results[1]
            .map(RemoteDownloadTaskModel.fromJson)
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      if (first) {
        ScaffoldMessenger.of(context)
            .showSnackBar(appSnack('加载失败，请下拉刷新重试'));
      }
    }
    _schedulePoll();
  }

  /// 有进行中任务时每 5s 自动轮询刷新进度
  void _schedulePoll() {
    _timer?.cancel();
    if (!_active.any((t) => t.isActive)) return;
    _timer = Timer(const Duration(seconds: 5), _load);
  }

  /// 发起新的离线下载（默认目标为当前浏览目录）
  Future<void> _create() async {
    final dir = await SpUtils.getString('currentMenu');
    if (!mounted) return;
    final created = await showCreateRemoteDownloadDialog(
      context,
      startUri: dir.isEmpty ? FileApi.myRootUri : dir,
    );
    if (created && mounted) _load();
  }

  /// 取消进行中的离线下载任务
  Future<void> _cancel(RemoteDownloadTaskModel task) async {
    final ok = await showAppConfirm(
      context: context,
      title: '取消下载',
      content: '确定取消「${task.displayName}」的离线下载吗？',
      confirmText: '取消下载',
      danger: true,
    );
    if (!ok || !mounted) return;
    try {
      await WorkflowApi.cancelRemoteDownload(task.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(appSnack('已取消「${task.displayName}」'));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(appSnack('取消失败：${errorText(e, '请稍后重试')}'));
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    // 订阅主题：深浅色切换时重建页面与任务行配色
    Theme.of(context);
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: pagePad),
            child: PageHeader(
              leading: IconTile(
                icon: Icons.arrow_back_ios_new,
                filled: false,
                compact: true,
                onTap: () => Navigator.pop(context),
              ),
              title: '离线下载',
              secondary: true,
              actions: [
                IconTile(icon: Icons.add_link, onTap: _create),
              ],
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return RefreshIndicator(
      onRefresh: _load,
      child: _loading
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 180),
                Center(child: CircularProgressIndicator(strokeWidth: 3)),
              ],
            )
          : _active.isEmpty && _finished.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: const [
                    SizedBox(height: 60),
                    EmptyState(
                      icon: Icons.download_for_offline_outlined,
                      title: '暂无离线下载任务',
                      subtitle: '点击右上角「新建」按钮，粘贴链接即可下载到云盘',
                    ),
                  ],
                )
              : ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(pagePad, 6, pagePad, 16),
                  children: [
                    if (_active.isNotEmpty) ...[
                      SectionHeader(
                        title: '进行中',
                        count: '${_active.length}',
                      ),
                      const SizedBox(height: 2),
                      for (final t in _active)
                        _ActiveRow(task: t, onCancel: () => _cancel(t)),
                    ],
                    if (_active.isNotEmpty && _finished.isNotEmpty)
                      const SizedBox(height: 14),
                    if (_finished.isNotEmpty) ...[
                      SectionHeader(
                        title: '已完成',
                        count: '${_finished.length}',
                      ),
                      const SizedBox(height: 2),
                      for (final t in _finished) _FinishedRow(task: t),
                    ],
                  ],
                ),
    );
  }
}

/// 进行中的离线下载任务行（进度条 + 速度 + 已下载/总量 + 取消）
class _ActiveRow extends StatelessWidget {
  final RemoteDownloadTaskModel task;
  final VoidCallback onCancel;

  const _ActiveRow({required this.task, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        children: [
          FileTile(type: 0, name: task.displayName, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.displayName,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(
                  task.statusText,
                  style: TextStyle(fontSize: 11.5, color: AppColors.ink3),
                ),
                const SizedBox(height: 9),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: task.progress.clamp(0.0, 1.0),
                    minHeight: 5,
                    color: AppColors.primary,
                    backgroundColor: AppColors.line,
                  ),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Text(
                      _formatSpeed(task.downloadSpeed),
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppColors.ink3,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${formatBytes(task.downloaded)} / ${formatBytes(task.total)}',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppColors.ink3,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            children: [
              Text(
                task.total <= 0
                    ? '--'
                    : '${(task.progress * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppColors.ink3,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 8),
              _CancelButton(onTap: onCancel),
            ],
          ),
        ],
      ),
    );
  }

  /// 下载速率格式化（B/s、KB/s、MB/s、GB/s）
  String _formatSpeed(int bytesPerSec) {
    if (bytesPerSec <= 0) return '--/s';
    if (bytesPerSec < 1024) return '$bytesPerSec B/s';
    if (bytesPerSec < 1024 * 1024) {
      return '${(bytesPerSec / 1024).toStringAsFixed(1)} KB/s';
    }
    if (bytesPerSec < 1024 * 1024 * 1024) {
      return '${(bytesPerSec / 1024 / 1024).toStringAsFixed(1)} MB/s';
    }
    return '${(bytesPerSec / 1024 / 1024 / 1024).toStringAsFixed(1)} GB/s';
  }
}

/// 已结束的离线下载任务行（完成 / 失败 / 已取消）
class _FinishedRow extends StatelessWidget {
  final RemoteDownloadTaskModel task;

  const _FinishedRow({required this.task});

  @override
  Widget build(BuildContext context) {
    final ok = task.status == 'completed';
    final canceled = task.status == 'canceled';
    final color = ok ? AppColors.success : (canceled ? AppColors.ink3 : AppColors.danger);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        children: [
          FileTile(type: 0, name: task.displayName, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.displayName,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  canceled
                      ? '已取消'
                      : ok
                          ? '已完成 · ${formatBytes(task.total)}'
                          : '失败：${task.failReason}',
                  style: TextStyle(fontSize: 12, color: color),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Icon(
            ok
                ? Icons.check_circle
                : canceled
                    ? Icons.remove_circle_outline
                    : Icons.error_outline,
            size: 22,
            color: color,
          ),
        ],
      ),
    );
  }
}

/// 取消按钮（进行中任务）
class _CancelButton extends StatelessWidget {
  final VoidCallback onTap;

  const _CancelButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.line),
        ),
        child: Icon(Icons.close, size: 18, color: AppColors.ink3),
      ),
    );
  }
}

/// 新建离线下载弹窗：输入链接（每行一个）+ 选择目标目录。
/// 返回是否成功创建了任务。
Future<bool> showCreateRemoteDownloadDialog(
  BuildContext context, {
  required String startUri,
}) async {
  final created = await showDialog<bool>(
    context: context,
    builder: (_) => _CreateRemoteDownloadDialog(startUri: startUri),
  );
  return created ?? false;
}

/// 离线下载 URI → 可读路径（根目录显示「我的存储」）
String _friendlyPath(String uri) {
  if (uri == FileApi.myRootUri) return '我的存储';
  const prefix = '${FileApi.myRootUri}/';
  final sub = uri.startsWith(prefix) ? uri.substring(prefix.length) : uri;
  return sub.split('/').map(Uri.decodeComponent).join(' / ');
}

class _CreateRemoteDownloadDialog extends StatefulWidget {
  final String startUri;

  const _CreateRemoteDownloadDialog({required this.startUri});

  @override
  State<_CreateRemoteDownloadDialog> createState() =>
      _CreateRemoteDownloadDialogState();
}

class _CreateRemoteDownloadDialogState
    extends State<_CreateRemoteDownloadDialog> {
  late final TextEditingController _urlController;
  late String _dst = widget.startUri;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController();
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  /// 选择下载目标目录
  Future<void> _pickDst() async {
    final pick = await FolderPicker.pick(
      context,
      startUri: _dst,
      allowCopy: false,
      title: '下载到',
      confirmLabel: '选择此目录',
    );
    if (pick != null && mounted) setState(() => _dst = pick.uri);
  }

  Future<void> _submit() async {
    final urls = _urlController.text
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (urls.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(appSnack('请输入至少一个下载链接'));
      return;
    }
    setState(() => _creating = true);
    try {
      final tasks = await WorkflowApi.createRemoteDownload(urls, _dst);
      if (!mounted) return;
      // 与压缩任务对齐：创建成功用 SnackBar 提示（先取 messenger，避免弹窗关闭后 context 失效）
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context, true);
      messenger.showSnackBar(appSnack(urls.length > 1
          ? '已添加 ${urls.length} 个离线下载任务，后台处理中，完成后将通知你'
          : '已创建离线下载任务，后台处理中，完成后将通知你'));
      // 跟踪任务：完成 / 失败时全局 toast 通知（带任务名，便于区分）
      for (final t in tasks) {
        final m = t is Map ? t : const <String, dynamic>{};
        final id = m['id']?.toString() ?? '';
        if (id.isNotEmpty) {
          final name = RemoteDownloadTaskModel.fromJson(
            Map<String, dynamic>.from(m),
          ).displayName;
          WorkflowTaskManager.instance.track(id, '离线下载「$name」');
        }
      }
      // 新文件出现在目标目录，失效列表缓存
      FileApi.invalidateListCache();
    } catch (e) {
      if (!mounted) return;
      setState(() => _creating = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(appSnack('创建失败：${errorText(e, '请稍后重试')}'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppDialogCard(
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '新建离线下载',
            style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.ink),
          ),
          const SizedBox(height: 5),
          Text(
            '服务器后台下载链接到云盘，支持 http / 磁力 / BT 等',
            style: TextStyle(fontSize: 12.5, color: AppColors.ink3),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _urlController,
            maxLines: 4,
            minLines: 3,
            decoration: appFieldDecoration(
              '下载链接',
              hint: '输入下载链接，每行一个',
            ),
          ),
          const SizedBox(height: 12),
          // 目标目录：可点击重新选择
          InkWell(
            onTap: _pickDst,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.bg,
                border: Border.all(color: AppColors.line),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.folder_outlined,
                      size: 19, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _friendlyPath(_dst),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: AppColors.ink2),
                    ),
                  ),
                  Text(
                    '更换',
                    style: TextStyle(
                        fontSize: 12.5,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      actions: [
        AppDialogButton(
          label: '取消',
          onPressed: () => Navigator.pop(context),
        ),
        AppDialogButton(
          label: '创建',
          primary: true,
          onPressed: _creating ? null : _submit,
        ),
      ],
    );
  }
}
