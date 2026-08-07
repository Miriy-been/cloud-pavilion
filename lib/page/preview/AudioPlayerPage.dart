import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_application_2/api/FileApi.dart';
import 'package:flutter_application_2/api/ShareApi.dart';
import 'package:flutter_application_2/config/AppTheme.dart';
import 'package:flutter_application_2/config/AppWidgets.dart';
import 'package:flutter_application_2/model/FileItemModel.dart';
import 'package:flutter_application_2/util/AudioPlayerService.dart';
import 'package:flutter_application_2/util/DownloadManager.dart';
import 'package:flutter_application_2/util/SpUtils.dart';

/// 音乐播放页：播放器 + 播放列表 + 多选管理
/// 播放列表统一来自「全站音频库」（AudioPlayerService 维护），本页仅展示播放状态
class AudioPlayerPage extends StatefulWidget {
  const AudioPlayerPage({super.key});

  @override
  State<AudioPlayerPage> createState() => _AudioPlayerPageState();
}

class _AudioPlayerPageState extends State<AudioPlayerPage> {
  final AudioPlayerService _svc = AudioPlayerService.instance;
  // 多选管理状态
  bool _managing = false;
  final Set<FileItemModel> _selected = {};
  // 进度条拖动中的本地值（松开后才提交 seek）
  double? _dragValue;

  @override
  void dispose() {
    // 不销毁播放器：切出页面后音频继续后台播放
    super.dispose();
  }

  void _exitManage() {
    setState(() {
      _managing = false;
      _selected.clear();
    });
  }

  void _selectAll() {
    setState(() {
      if (_selected.length == _svc.playlist.length) {
        _selected.clear();
      } else {
        _selected.clear();
        _selected.addAll(_svc.playlist);
      }
    });
  }

  void _toggle(FileItemModel f) {
    setState(() {
      if (!_selected.add(f)) _selected.remove(f);
    });
  }

  /// 批量下载
  Future<void> _batchDownload() async {
    final items = _selected.toList();
    var count = 0;
    for (final f in items) {
      try {
        final url = await FileApi.getDownloadUrl(f.path);
        DownloadManager.instance.startDownload(f.name, url);
        count++;
      } catch (_) {}
    }
    _exitManage();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(appSnack('已添加 $count 个下载任务'));
  }

  /// 批量分享
  Future<void> _batchShare() async {
    final siteUrl = await SpUtils.getString('CurrentBaseUrl');
    final links = <String>[];
    for (final f in _selected) {
      try {
        final path = await ShareApi.createShare(f.path);
        links.add('$siteUrl$path');
      } catch (_) {}
    }
    _exitManage();
    if (links.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: links.first));
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(appSnack('已创建 ${links.length} 个分享，第一个链接已复制'));
    }
  }

  /// 批量删除（进回收站）
  Future<void> _batchDelete() async {
    final items = _selected.toList();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除'),
        content: Text('确定将选中的 ${items.length} 首歌曲移入回收站吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await FileApi.deleteFiles(items.map((e) => e.path).toList());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(appSnack('删除失败：$e'));
      return;
    }
    _svc.removeFromPlaylist(items);
    _exitManage();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(appSnack('已删除 ${items.length} 项'));
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: pagePad),
            child: _buildHeader(),
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: _svc,
              builder: (context, _) {
                if (_svc.playlist.isEmpty) {
                  return const EmptyState(
                    icon: Icons.music_off_outlined,
                    title: '暂无播放内容',
                    subtitle: '去「存储」页选择一首音乐开始播放',
                  );
                }
                return Column(
                  children: [
                    _buildPlayer(),
                    const SizedBox(height: 10),
                    _buildPlaylistHeader(),
                    const SizedBox(height: 4),
                    Expanded(child: _buildPlaylist()),
                  ],
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: _managing ? _buildManageBar() : null,
    );
  }

  Widget _buildHeader() {
    if (_managing) {
      return PageHeader(
        leading: IconTile(icon: Icons.close, onTap: _exitManage),
        title: '已选 ${_selected.length} 项',
        actions: [
          TextButton(
            onPressed: _selectAll,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
              textStyle: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600),
            ),
            child: const Text('全选'),
          ),
        ],
      );
    }
    return PageHeader(
      title: '音乐播放器',
      secondary: true,
      leading: IconTile(
        icon: Icons.arrow_back_ios_new,
        filled: false,
        compact: true,
        onTap: () => Navigator.pop(context),
      ),
      actions: [
        IconTile(
          icon: Icons.checklist_rounded,
          onTap: _svc.playlist.isEmpty
              ? null
              : () => setState(() => _managing = true),
        ),
      ],
    );
  }

  /// 封面缩略图（加载失败回退音符图标）
  Widget _buildCover() {
    final cover = _svc.currentCover;
    Widget fallback() => Container(
          width: 160,
          height: 160,
          decoration: BoxDecoration(
            color: AppColors.primarySoft,
            borderRadius: BorderRadius.circular(26),
          ),
          child: Icon(Icons.music_note_rounded,
              size: 74, color: AppColors.primary),
        );
    if (cover == null || cover.isEmpty) return fallback();
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: CachedImage(
        url: cover,
        width: 160,
        height: 160,
        fit: BoxFit.cover,
        // 磁盘缓存 + 换歌时保留旧封面直到新封面就绪，避免空白/占位闪烁
        placeholder: fallback(),
        errorBuilder: (_, __) => fallback(),
      ),
    );
  }

  /// 播放器主体（绑定全局播放服务）
  Widget _buildPlayer() {
    // 仅首次加载（尚无播放内容）时显示全屏加载；切歌/缓冲用播放键小菊花提示
    if (_svc.loading && _svc.currentIndex < 0) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_svc.error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.error_outline, size: 42, color: AppColors.danger),
              const SizedBox(height: 10),
              Text(_svc.error!,
                  style: TextStyle(fontSize: 13, color: AppColors.ink3)),
              const SizedBox(height: 14),
              OutlinedButton(
                onPressed: () => _svc.jumpTo(_svc.currentIndex),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    final dur = _svc.duration.inSeconds > 0
        ? _svc.duration.inSeconds.toDouble()
        : 1.0;
    final pos = _svc.position.inSeconds.toDouble().clamp(0.0, dur);
    return Column(
      children: [
        const SizedBox(height: 12),
        _buildCover(),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            _svc.currentTitle ?? _svc.currentName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: AppColors.ink),
          ),
        ),
        if ((_svc.currentArtist ?? '').isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            _svc.currentArtist!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.ink3),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          '${_fmt(Duration(seconds: (_dragValue ?? pos).round()))} / ${_fmt(_svc.duration)}',
          style: TextStyle(fontSize: 12, color: AppColors.ink3),
        ),
        Slider(
          value: _dragValue ?? pos,
          max: dur,
          // 拖动过程中仅更新本地值，松开后才跳转，避免被播放进度拉回
          onChangeStart: (v) => setState(() => _dragValue = v),
          onChanged: (v) => setState(() => _dragValue = v),
          onChangeEnd: (v) {
            _svc.seekTo(Duration(seconds: v.round()));
            setState(() => _dragValue = null);
          },
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              iconSize: 34,
              icon: const Icon(Icons.skip_previous_rounded),
              color: AppColors.ink,
              onPressed: _svc.playlist.length > 1
                  ? () => _svc.switchTrack(-1)
                  : null,
            ),
            const SizedBox(width: 20),
            GestureDetector(
              onTap: _svc.buffering ? null : _svc.togglePlay,
              child: Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF0B1220),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x330B1220),
                      blurRadius: 20,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: _svc.buffering
                    ? const Padding(
                        padding: EdgeInsets.all(19),
                        child: CircularProgressIndicator(
                            strokeWidth: 3, color: Colors.white),
                      )
                    : Icon(
                        _svc.playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        size: 34,
                        color: Colors.white,
                      ),
              ),
            ),
            const SizedBox(width: 20),
            IconButton(
              iconSize: 34,
              icon: const Icon(Icons.skip_next_rounded),
              color: AppColors.ink,
              onPressed: _svc.playlist.length > 1
                  ? () => _svc.switchTrack(1)
                  : null,
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Icon(Icons.volume_down, size: 20, color: AppColors.ink3),
              Expanded(
                child: Slider(
                  value: _svc.volume,
                  onChanged: _svc.setVolume,
                ),
              ),
              Icon(Icons.volume_up, size: 20, color: AppColors.ink3),
              const SizedBox(width: 4),
              IconButton(
                icon: Icon(_svc.loop == 1
                    ? Icons.repeat_one_on_rounded
                    : _svc.loop == 0
                        ? Icons.repeat_on_rounded
                        : Icons.repeat_rounded),
                color: _svc.loop == 2 ? AppColors.ink3 : AppColors.primary,
                onPressed: _svc.toggleLoop,
                tooltip: _svc.loop == 0
                    ? '列表循环'
                    : _svc.loop == 1
                        ? '单曲循环'
                        : '顺序播放',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPlaylistHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(pagePad, 10, pagePad, 0),
      child: SectionHeader(
        title: '播放列表',
        count: '${_svc.playlist.length}',
        trailing: _managing
            ? null
            : Text(
                '长按可多选',
                style: TextStyle(fontSize: 11.5, color: AppColors.ink3),
              ),
      ),
    );
  }

  Widget _buildPlaylist() {
    final list = _svc.playlist;
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(pagePad, 4, pagePad,
          MediaQuery.of(context).padding.bottom + 16),
      itemCount: list.length,
      itemBuilder: (context, index) {
        final f = list[index];
        final isCurrent = index == _svc.currentIndex;
        final selected = _selected.contains(f);
        return InkWell(
          onTap: _managing
              ? () => _toggle(f)
              : () => _svc.jumpTo(index),
          onLongPress: _managing
              ? () => _toggle(f)
              : () => setState(() {
                    _managing = true;
                    _selected.add(f);
                  }),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 2),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.primarySoft
                  : isCurrent
                      ? AppColors.primarySoft.withValues(alpha: .45)
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                if (_managing) ...[
                  RoundCheck(on: selected),
                  const SizedBox(width: 12),
                ],
                FileTile(type: 0, name: f.name, size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        f.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight:
                              isCurrent ? FontWeight.w600 : FontWeight.w500,
                          color: isCurrent ? AppColors.primary : AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        formatBytes(f.size),
                        style: TextStyle(
                            fontSize: 12, color: AppColors.ink3),
                      ),
                    ],
                  ),
                ),
                if (!_managing)
                  Icon(
                    isCurrent
                        ? Icons.graphic_eq
                        : Icons.play_arrow_rounded,
                    size: 20,
                    color:
                        isCurrent ? AppColors.primary : AppColors.ink3,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 多选底部操作条
  Widget _buildManageBar() {
    return Container(
      color: AppColors.surface,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 58,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _ManageItem(
                icon: Icons.download,
                label: '下载',
                onTap: _selected.isEmpty ? null : _batchDownload,
              ),
              _ManageItem(
                icon: Icons.share,
                label: '分享',
                onTap: _selected.isEmpty ? null : _batchShare,
              ),
              _ManageItem(
                icon: Icons.delete,
                label: '删除',
                danger: true,
                onTap: _selected.isEmpty ? null : _batchDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 多选底部操作项
class _ManageItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool danger;
  final VoidCallback? onTap;

  const _ManageItem({
    required this.icon,
    required this.label,
    this.danger = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = danger
        ? AppColors.danger
        : (onTap == null ? AppColors.ink3 : AppColors.ink2);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 21, color: color),
          const SizedBox(height: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11.5,
                  color: danger ? AppColors.danger : AppColors.ink2)),
        ],
      ),
    );
  }
}
