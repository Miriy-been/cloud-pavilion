import 'package:flutter/material.dart';
import 'package:cloudpavilion/config/AppTheme.dart';
import 'package:cloudpavilion/config/AppWidgets.dart';
import 'package:cloudpavilion/model/DownloadTaskModel.dart';
import 'package:cloudpavilion/model/UploadTaskModel.dart';
import 'package:cloudpavilion/util/DownloadManager.dart';
import 'package:cloudpavilion/util/UploadManager.dart';

/// 传输页（本地下载 + 后台上传任务）
class Download extends StatefulWidget {
  Download({super.key});

  @override
  State<Download> createState() => _DownloadState();
}

class _DownloadState extends State<Download>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// 手动刷新：重新触发下载 / 上传列表重建，
  /// 用于主题切换后 UI 残留旧配色等需要即时重绘的场景
  void _refresh() {
    DownloadManager.instance.notifyListeners();
    UploadManager.instance.notifyListeners();
  }

  /// 弹出「并行上传数量」设置弹窗（参考网页版的并发设置，1~20）
  void _showConcurrencySheet() {
    var value = UploadManager.instance.maxConcurrent;
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AppDialogCard(
          header: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '并行上传数量',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink),
              ),
              const SizedBox(height: 5),
              Text(
                '同时上传的任务数（1~20），调大可加快队列进度',
                style: TextStyle(fontSize: 12.5, color: AppColors.ink3),
              ),
            ],
          ),
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$value 个',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Slider(
                value: value.toDouble(),
                min: 1,
                max: 20,
                divisions: 19,
                label: '$value',
                activeColor: AppColors.primary,
                inactiveColor: AppColors.line,
                onChanged: (v) => setState(() => value = v.toInt()),
              ),
            ],
          ),
          actions: [
            AppDialogButton(
              label: '取消',
              onPressed: () => Navigator.pop(ctx),
            ),
            AppDialogButton(
              label: '保存',
              primary: true,
              onPressed: () {
                UploadManager.instance.setMaxConcurrent(value);
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 订阅主题：深浅色切换时重建页面与任务行图标配色
    Theme.of(context);
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: pagePad),
            child: PageHeader(
              title: '传输',
              subtitle: '下载与上传任务一览',
              actions: [
                // 手动刷新：重新触发传输列表重建（如主题切换后 UI 残留旧配色）
                IconTile(
                  icon: Icons.refresh,
                  onTap: _refresh,
                ),
                // 并行上传数量设置（像网页版一样可自定义并发）
                IconTile(
                  icon: Icons.speed_outlined,
                  onTap: _showConcurrencySheet,
                ),
              ],
            ),
          ),
          // 计数徽标 + 选中高亮：监听任务状态与标签切换，轻量刷新不重建整页
          ListenableBuilder(
            listenable: Listenable.merge([
              DownloadManager.instance,
              UploadManager.instance,
              _tabController,
            ]),
            builder: (context, _) {
              final activeD = DownloadManager.instance.tasks
                  .where((t) => t.status == DownloadStatus.downloading)
                  .length;
              final activeU = UploadManager.instance.tasks
                  .where((t) => t.status == UploadStatus.uploading)
                  .length;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: pagePad),
                child: _Segmented(
                  labels: const ['下载', '上传'],
                  counts: ['$activeD', '$activeU'],
                  index: _tabController.index,
                  onChanged: (i) => _tabController.index = i,
                ),
              );
            },
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [_DownloadTab(), _UploadTab()],
            ),
          ),
        ],
      ),
    );
  }
}

/// 下载任务 Tab：仅监听下载任务变化，独立刷新
class _DownloadTab extends StatefulWidget {
  const _DownloadTab();

  @override
  State<_DownloadTab> createState() => _DownloadTabState();
}

class _DownloadTabState extends State<_DownloadTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    Theme.of(context);
    // 主题切换时强制重建：EmptyState 的配色由 AppColors 静态令牌计算，
    // 若不复建会在切换瞬间残留旧主题颜色（文字变淡等错乱）
    final brightness = Theme.of(context).brightness;
    return ListenableBuilder(
      key: ValueKey(brightness),
      listenable: DownloadManager.instance,
      builder: (context, _) {
        final tasks = DownloadManager.instance.tasks;
        if (tasks.isEmpty) {
          return const EmptyState(
            icon: Icons.download_for_offline_outlined,
            title: '暂无下载任务',
            subtitle: '从「存储」页选择文件即可开始下载',
          );
        }
        final active =
            tasks.where((t) => t.status == DownloadStatus.downloading).toList();
        final done =
            tasks.where((t) => t.status != DownloadStatus.downloading).toList();
        return ListView(
          padding: const EdgeInsets.fromLTRB(pagePad, 14, pagePad, 16),
          children: [
            for (final t in active) _DownloadRow(task: t),
            if (active.isNotEmpty && done.isNotEmpty) const SizedBox(height: 14),
            if (done.isNotEmpty) ...[
              SectionHeader(
                title: '已完成',
                count: '${done.length}',
                trailing: _ClearButton(
                  onTap: () => DownloadManager.instance.clearFinished(),
                ),
              ),
              const SizedBox(height: 2),
              for (final t in done) _DownloadRow(task: t),
            ],
          ],
        );
      },
    );
  }
}

/// 上传任务 Tab：仅监听上传任务变化，独立刷新
class _UploadTab extends StatefulWidget {
  const _UploadTab();

  @override
  State<_UploadTab> createState() => _UploadTabState();
}

class _UploadTabState extends State<_UploadTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    Theme.of(context);
    // 主题切换时强制重建，避免 EmptyState 残留旧主题配色
    final brightness = Theme.of(context).brightness;
    return ListenableBuilder(
      key: ValueKey(brightness),
      listenable: UploadManager.instance,
      builder: (context, _) {
        final tasks = UploadManager.instance.tasks;
        if (tasks.isEmpty) {
          return const EmptyState(
            icon: Icons.file_upload_outlined,
            title: '暂无上传任务',
            subtitle: '从「存储」页点击上传即可开始',
          );
        }
        final active =
            tasks.where((t) => t.status == UploadStatus.uploading).toList();
        final done =
            tasks.where((t) => t.status != UploadStatus.uploading).toList();
        return ListView(
          padding: const EdgeInsets.fromLTRB(pagePad, 14, pagePad, 16),
          children: [
            for (final t in active) _UploadRow(task: t),
            if (active.isNotEmpty && done.isNotEmpty) const SizedBox(height: 14),
            if (done.isNotEmpty) ...[
              SectionHeader(
                title: '已完成',
                count: '${done.length}',
                trailing: _ClearButton(
                  onTap: () => UploadManager.instance.clearFinished(),
                ),
              ),
              const SizedBox(height: 2),
              for (final t in done) _UploadRow(task: t),
            ],
          ],
        );
      },
    );
  }
}

/// 下载任务行
class _DownloadRow extends StatelessWidget {
  final DownloadTaskModel task;

  const _DownloadRow({required this.task});

  @override
  Widget build(BuildContext context) {
    final downloading = task.status == DownloadStatus.downloading;
    final ok = task.status == DownloadStatus.finished;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        children: [
          FileTile(type: 0, name: task.name, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.name,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 9),
                if (downloading)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: task.progress.clamp(0.0, 1.0),
                      minHeight: 5,
                      color: AppColors.primary,
                      backgroundColor: AppColors.line,
                    ),
                  )
                else
                  Text(
                    ok
                        ? task.savePath
                        : task.status == DownloadStatus.cancelled
                            ? '已取消'
                            : '下载失败：${task.error ?? '未知错误'}',
                    style: TextStyle(
                      fontSize: 12,
                      color: ok ? AppColors.ink3 : AppColors.danger,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (downloading)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${(task.progress * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.ink3,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 6),
                _CancelButton(
                  onTap: () => DownloadManager.instance.cancel(task),
                ),
              ],
            )
          else if (ok)
            const Icon(Icons.check_circle, size: 22, color: AppColors.success)
          else
            _RetryButton(
              onTap: () => DownloadManager.instance.retry(task),
            ),
        ],
      ),
    );
  }
}

/// 上传字节速率格式化（B/s、KB/s、MB/s、GB/s）
String _formatSpeed(double bytesPerSec) {
  if (bytesPerSec <= 0) return '--/s';
  if (bytesPerSec < 1024) return '${bytesPerSec.toStringAsFixed(0)} B/s';
  if (bytesPerSec < 1024 * 1024) {
    return '${(bytesPerSec / 1024).toStringAsFixed(1)} KB/s';
  }
  if (bytesPerSec < 1024 * 1024 * 1024) {
    return '${(bytesPerSec / 1024 / 1024).toStringAsFixed(1)} MB/s';
  }
  return '${(bytesPerSec / 1024 / 1024 / 1024).toStringAsFixed(1)} GB/s';
}

/// 上传任务行
class _UploadRow extends StatelessWidget {
  final UploadTaskModel task;

  const _UploadRow({required this.task});

  @override
  Widget build(BuildContext context) {
    final uploading = task.status == UploadStatus.uploading;
    final ok = task.status == UploadStatus.finished;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        children: [
          FileTile(type: 0, name: task.name, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.name,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 9),
                if (uploading) ...[
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
                        _formatSpeed(task.speed),
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppColors.ink3,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${formatBytes(task.uploaded)} / ${formatBytes(task.size)}',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppColors.ink3,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ] else
                  Text(
                    ok
                        ? '上传完成'
                        : task.status == UploadStatus.cancelled
                            ? '已取消'
                            : '上传失败：${task.error ?? '未知错误'}',
                    style: TextStyle(
                      fontSize: 12,
                      color: ok ? AppColors.ink3 : AppColors.danger,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (uploading)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${(task.progress * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.ink3,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 6),
                _CancelButton(
                  onTap: () => UploadManager.instance.cancel(task),
                ),
              ],
            )
          else if (ok)
            const Icon(Icons.check_circle, size: 22, color: AppColors.success)
          else
            _RetryButton(
              onTap: () => UploadManager.instance.retry(task),
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

/// 重试按钮（失败 / 已取消任务）
class _RetryButton extends StatelessWidget {
  final VoidCallback onTap;

  const _RetryButton({required this.onTap});

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
        child: Icon(Icons.refresh, size: 18, color: AppColors.primary),
      ),
    );
  }
}

/// 清空已完成记录按钮（仅在已有完成记录时展示）
class _ClearButton extends StatelessWidget {
  final VoidCallback onTap;

  const _ClearButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      // 弹确认框：批量清空不可撤销，先让用户确认，也避免误触
      onTap: () async {
        final ok = await showAppConfirm(
          context: context,
          title: '清空记录',
          content: '确定清空所有已完成（含失败/取消）的记录吗？进行中的任务不会被清除。',
          confirmText: '清空',
          danger: true,
        );
        if (ok) onTap();
      },
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_sweep_outlined, size: 15, color: AppColors.ink3),
            const SizedBox(width: 4),
            Text(
              '清空',
              style: TextStyle(fontSize: 12, color: AppColors.ink3),
            ),
          ],
        ),
      ),
    );
  }
}

/// 胶囊分段控件
class _Segmented extends StatelessWidget {
  final List<String> labels;
  final List<String> counts;
  final int index;
  final ValueChanged<int> onChanged;

  const _Segmented({
    required this.labels,
    required this.counts,
    required this.index,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: List.generate(labels.length, (i) {
          final active = i == index;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(i),
              child: Container(
                height: 36,
                decoration: BoxDecoration(
                  color: active ? AppColors.primarySoft : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      labels[i],
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: active ? AppColors.primary : AppColors.ink2,
                      ),
                    ),
                    if (counts[i].isNotEmpty) ...[
                      const SizedBox(width: 5),
                      Text(
                        counts[i],
                        style: TextStyle(
                          fontSize: 10.5,
                          color: active
                              ? AppColors.primary.withValues(alpha: .75)
                              : AppColors.ink3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
