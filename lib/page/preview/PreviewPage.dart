import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloudpavilion/api/FileApi.dart';
import 'package:cloudpavilion/api/ShareApi.dart';
import 'package:cloudpavilion/config/AppTheme.dart';
import 'package:cloudpavilion/config/AppWidgets.dart';
import 'package:cloudpavilion/model/FileItemModel.dart';
import 'package:cloudpavilion/page/tools/ShareSheet.dart';
import 'package:cloudpavilion/util/DownloadManager.dart';
import 'package:cloudpavilion/util/SpUtils.dart';
import 'package:video_player/video_player.dart';

/// 文件在线预览页（图片 / 视频 / 文本；音频由 AudioPlayerPage 处理）
/// 支持：同目录左右滑动切换、图片沉浸式单击收起/恢复控制栏、底部快捷操作栏
class PreviewPage extends StatefulWidget {
  final String fileUri;
  final String fileName;

  /// 同目录可预览文件列表（为空则单文件预览，无滑动切换）
  final List<FileItemModel>? siblings;

  /// 当前文件在 siblings 中的位置
  final int initialIndex;

  const PreviewPage({
    super.key,
    required this.fileUri,
    required this.fileName,
    this.siblings,
    this.initialIndex = 0,
  });

  @override
  State<PreviewPage> createState() => _PreviewPageState();
}

class _PreviewPageState extends State<PreviewPage> {
  late List<FileItemModel> _items;
  late int _index;
  late PageController _pageController;
  VideoPlayerController? _videoController;
  final TextEditingController _editController = TextEditingController();
  final Map<String, Future<String>> _urls = {};
  bool _editing = false;
  bool _editLoading = false;
  bool _immersive = false;

  /// 是否有修改（重命名 / 删除），返回列表时通知刷新
  bool _changed = false;

  /// 文本阅读设置（字号 / 行距）
  double _fontSize = 16;
  double _lineHeight = 1.7;

  static const _imageExts = ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'];
  static const _videoExts = ['mp4', 'webm', 'mkv', 'avi', 'mov', '3gp'];
  static const _textExts = [
    'txt', 'md', 'json', 'js', 'css', 'html', 'xml', 'yaml', 'yml',
    'log', 'csv', 'conf', 'ini', 'sh', 'java', 'py', 'go', 'c', 'cpp',
    'h', 'dart', 'ts', 'php', 'rb',
  ];

  FileItemModel get _current => _items[_index];
  String get _ext => _current.name.split('.').last.toLowerCase();
  bool get _isImage => _imageExts.contains(_ext);
  bool get _isVideo => _videoExts.contains(_ext);
  bool get _hasSiblings => _items.length > 1;

  /// 获取文件预览地址（带缓存）
  Future<String> _urlOf(String path) =>
      _urls.putIfAbsent(path, () => FileApi.getDownloadUrl(path, download: false));

  @override
  void initState() {
    super.initState();
    if (widget.siblings != null && widget.siblings!.isNotEmpty) {
      _items = List.of(widget.siblings!);
      _index = widget.initialIndex.clamp(0, _items.length - 1);
    } else {
      _items = [
        FileItemModel(
            type: 0, id: '', name: widget.fileName, size: 0, path: widget.fileUri)
      ];
      _index = 0;
    }
    _pageController = PageController(initialPage: _index);
    _setupVideo();
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _editController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  /// 为当前文件初始化视频播放器（切换文件时重建）
  void _setupVideo() {
    _videoController?.dispose();
    _videoController = null;
    if (!_isVideo) return;
    _urlOf(_current.path).then((url) {
      if (!mounted) return;
      _videoController = VideoPlayerController.networkUrl(Uri.parse(url));
      _videoController!.initialize().then((_) {
        if (!mounted) return;
        setState(() {});
        _videoController!.play();
      }).catchError((_) {});
    });
  }

  /// 沉浸模式：仅收起 / 恢复应用内顶栏 + 操作栏（系统状态栏保持可见）
  void _setImmersive(bool value) {
    setState(() => _immersive = value);
  }

  /// 退出文本编辑
  void _exitEdit() {
    setState(() => _editing = false);
  }

  /// 进入文本编辑模式（隐藏顶部栏，底部保留取消 / 保存）
  Future<void> _startEdit() async {
    setState(() {
      _editing = true;
      _editLoading = true;
    });
    try {
      final url = await _urlOf(_current.path);
      final r = await Dio()
          .get(url, options: Options(responseType: ResponseType.plain));
      _editController.text = r.data?.toString() ?? '';
    } catch (_) {
      _editController.text = '';
    } finally {
      if (mounted) setState(() => _editLoading = false);
    }
  }

  Future<void> _saveEdit() async {
    try {
      await FileApi.updateFileContent(_current.path, _editController.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(appSnack('已保存'));
      _exitEdit();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(appSnack('保存失败：$e'));
    }
  }

  /// 下载当前文件
  Future<void> _downloadCurrent() async {
    try {
      final url = await FileApi.getDownloadUrl(_current.path);
      DownloadManager.instance.startDownload(_current.name, url);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(appSnack('开始下载 ${_current.name}'));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(appSnack('下载失败：$e'));
    }
  }

  /// 分享当前文件（完整配置弹窗）
  Future<void> _shareCurrent() async {
    final share = await showShareDialog(context, _current.name);
    if (share == null || !mounted) return;
    try {
      final siteUrl = await SpUtils.getString('CurrentBaseUrl');
      final path = await ShareApi.createShare(
        _current.path,
        isPrivate: share.password.isNotEmpty,
        expireSeconds: share.expireSeconds,
        password: share.password.isEmpty ? null : share.password,
        remainDownloads: share.remainDownloads,
      );
      final fullUrl = ShareApi.buildFullUrl(siteUrl, path);
      await Clipboard.setData(ClipboardData(text: fullUrl));
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(appSnack('分享链接已复制：$fullUrl'));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(appSnack('创建分享失败：$e'));
    }
  }

  /// 删除当前文件（进回收站，返回列表）
  Future<void> _deleteCurrent() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除'),
        content: Text('确定将「${_current.name}」移入回收站吗？'),
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
    if (confirmed != true || !mounted) return;
    try {
      await FileApi.deleteFiles([_current.path]);
      if (!mounted) return;
      // 返回列表并通知刷新
      _changed = true;
      Navigator.pop(context, _changed);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(appSnack('删除失败：$e'));
    }
  }

  /// 视频播放 / 暂停
  void _togglePlay() {
    final c = _videoController;
    if (c == null || !c.value.isInitialized) return;
    setState(() {
      c.value.isPlaying ? c.pause() : c.play();
    });
  }

  /// 阅读设置弹窗：字号 / 行距
  void _showReaderSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(pagePad),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 6),
                const SheetHandle(),
                const SizedBox(height: 16),
                Text('字号',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink3)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  children: [
                    for (final s in const [14.0, 16.0, 18.0, 20.0])
                      ChoiceChip(
                        label: Text('${s.round()}'),
                        selected: _fontSize == s,
                        showCheckmark: false,
                        selectedColor: AppColors.primarySoft,
                        labelStyle: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _fontSize == s
                              ? AppColors.primary
                              : AppColors.ink2,
                        ),
                        onSelected: (_) {
                          setSheet(() {});
                          setState(() => _fontSize = s);
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                Text('行距',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink3)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  children: [
                    for (final h in const [1.4, 1.7, 2.0])
                      ChoiceChip(
                        label: Text(
                            h == 1.4 ? '紧凑' : (h == 1.7 ? '标准' : '宽松')),
                        selected: _lineHeight == h,
                        showCheckmark: false,
                        selectedColor: AppColors.primarySoft,
                        labelStyle: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _lineHeight == h
                              ? AppColors.primary
                              : AppColors.ink2,
                        ),
                        onSelected: (_) {
                          setSheet(() {});
                          setState(() => _lineHeight = h);
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 更多弹窗：重命名 / 详情
  void _showMore() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(pagePad),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 6),
              const SheetHandle(),
              const SizedBox(height: 16),
              ListTile(
                leading: Icon(Icons.drive_file_rename_outline,
                    color: AppColors.primary),
                title: const Text('重命名'),
                onTap: () {
                  Navigator.pop(ctx);
                  _renameCurrent();
                },
              ),
              ListTile(
                leading: Icon(Icons.info_outline, color: AppColors.ink3),
                title: const Text('详情'),
                onTap: () {
                  Navigator.pop(ctx);
                  showFileDetailSheet(context, _current.path, _current.name);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 重命名当前文件
  Future<void> _renameCurrent() async {
    final name = await _promptRename();
    if (name == null || name.isEmpty || name == _current.name) return;
    try {
      await FileApi.renameFile(_current.path, name);
      if (!mounted) return;
      final old = _current;
      final slash = old.path.lastIndexOf('/');
      final newPath =
          slash <= 0 ? name : '${old.path.substring(0, slash)}/$name';
      setState(() {
        _items[_index] = FileItemModel(
          type: old.type,
          id: old.id,
          name: name,
          size: old.size,
          path: newPath,
          createdAt: old.createdAt,
          updatedAt: old.updatedAt,
          metadata: old.metadata,
        );
        _changed = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(appSnack('已重命名'));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(appSnack('重命名失败：$e'));
    }
  }

  /// 重命名输入弹窗
  Future<String?> _promptRename() {
    final controller = TextEditingController(text: _current.name);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '输入新名称'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('确定')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 订阅主题：深浅色切换时重建预览页配色
    Theme.of(context);
    // 顶栏 / 操作栏作为浮层叠加在内容之上（沉浸时滑出），
    // 内容区始终占满屏幕，避免收起控制栏时图片发生位移
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          Positioned.fill(
            child: _editing
                ? _buildTextEditor()
                : (_hasSiblings
                    ? PageView.builder(
                        controller: _pageController,
                        onPageChanged: (i) {
                          _setImmersive(false);
                          setState(() => _index = i);
                          _setupVideo();
                        },
                        itemCount: _items.length,
                        itemBuilder: (context, i) => _buildPage(_items[i]),
                      )
                    : _buildPage(_current)),
          ),
          if (!_editing) _buildTopBar(),
          _buildActionBar(),
        ],
      ),
    );
  }

  /// 顶部浮层：返回 + 文件名 + 详情（沉浸时滑出屏幕）
  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 200),
        offset: _immersive ? const Offset(0, -1) : Offset.zero,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: _immersive ? 0 : 1,
          child: IgnorePointer(
            ignoring: _immersive,
            child: Material(
              color: AppColors.surface,
              elevation: 0.5,
              child: SafeArea(
                bottom: false,
                child: SizedBox(
                  height: kToolbarHeight,
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                        color: AppColors.ink,
                        onPressed: () => Navigator.pop(context, _changed),
                      ),
                      Expanded(
                        child: Text(
                          _current.name,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: AppColors.ink),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 单页内容（图片 / 视频 / 文本 / 其他），非图片类型点击同样切换沉浸
  Widget _buildPage(FileItemModel item) {
    final ext = item.name.split('.').last.toLowerCase();
    final Widget child;
    if (_imageExts.contains(ext)) {
      child = _buildImagePage(item);
    } else if (_videoExts.contains(ext)) {
      child = _buildVideoPage(item);
    } else if (_textExts.contains(ext)) {
      child = _buildTextViewer(item);
    } else {
      child = Center(
        child: Text('暂不支持该类型预览，请下载后查看',
            style: TextStyle(color: AppColors.ink3)),
      );
    }
    // 图片页已自带点击切换沉浸，其余类型统一包裹点击手势
    if (_imageExts.contains(ext)) return child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _setImmersive(!_immersive),
      child: child,
    );
  }

  Widget _buildImagePage(FileItemModel item) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _setImmersive(!_immersive),
      child: FutureBuilder<String>(
        future: _urlOf(item.path),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return InteractiveViewer(
            maxScale: 5,
            child: Center(
              child: Image.network(snapshot.data!, fit: BoxFit.contain),
            ),
          );
        },
      ),
    );
  }

  Widget _buildVideoPage(FileItemModel item) {
    final c = _videoController;
    if (item.path != _current.path || c == null || !c.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    return Center(
      child: AspectRatio(
        aspectRatio: c.value.aspectRatio,
        child: VideoPlayer(c),
      ),
    );
  }

  Widget _buildTextViewer(FileItemModel item) {
    return FutureBuilder<String>(
      future: _urlOf(item.path).then((url) => Dio()
          .get(url, options: Options(responseType: ResponseType.plain))
          .then((r) => r.data?.toString() ?? '')),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
              child: Text('文本加载失败', style: TextStyle(color: AppColors.ink3)));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return SingleChildScrollView(
          // 上下加大留白，避免文字贴边 / 底部大段空白
          padding: const EdgeInsets.fromLTRB(20, 32, 20, 48),
          child: SelectableText(
            snapshot.data!,
            style: TextStyle(
              color: AppColors.ink,
              fontSize: _fontSize,
              height: _lineHeight,
            ),
          ),
        );
      },
    );
  }

  Widget _buildTextEditor() {
    if (_editLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    return Padding(
      padding: const EdgeInsets.all(4),
      child: TextField(
        controller: _editController,
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        autofocus: true,
        style: TextStyle(fontSize: 14, height: 1.6, color: AppColors.ink),
        cursorColor: AppColors.primary,
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: '输入内容…',
          hintStyle: TextStyle(color: AppColors.ink3),
          contentPadding: const EdgeInsets.all(12),
        ),
      ),
    );
  }

  /// 底部快捷操作栏（样式参考多选功能栏，按文件类型差异化展示）
  /// 文本编辑态替换为「取消 / 保存」；沉浸时滑出屏幕
  Widget _buildActionBar() {
    final Widget bar;
    if (_editing) {
      bar = Row(
        children: [
          Expanded(
            child: _PreviewAction(
              icon: Icons.close,
              label: '取消',
              onTap: _exitEdit,
            ),
          ),
          Expanded(
            child: _PreviewAction(
              icon: Icons.check,
              label: '保存',
              onTap: _saveEdit,
            ),
          ),
        ],
      );
    } else {
      final items = <Widget>[
        if (_textExts.contains(_ext)) ...[
          _PreviewAction(
            icon: Icons.edit_outlined,
            label: '编辑',
            onTap: _startEdit,
          ),
          _PreviewAction(
            icon: Icons.format_size,
            label: '字号',
            onTap: _showReaderSettings,
          ),
        ],
        if (_isVideo)
          _PreviewAction(
            icon: _videoController?.value.isPlaying == true
                ? Icons.pause
                : Icons.play_arrow,
            label: '播放',
            onTap: _togglePlay,
          ),
        _PreviewAction(
          icon: Icons.download_outlined,
          label: '下载',
          onTap: _downloadCurrent,
        ),
        if (_isImage || _isVideo) ...[
          _PreviewAction(
            icon: Icons.share_outlined,
            label: '分享',
            onTap: _shareCurrent,
          ),
          _PreviewAction(
            icon: Icons.delete_outline,
            label: '删除',
            danger: true,
            onTap: _deleteCurrent,
          ),
        ],
        _PreviewAction(
          icon: Icons.more_horiz,
          label: '更多',
          onTap: _showMore,
        ),
      ];
      bar = Row(
        children: [for (final it in items) Expanded(child: it)],
      );
    }
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 200),
        offset: _immersive ? const Offset(0, 1) : Offset.zero,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: _immersive ? 0 : 1,
          child: IgnorePointer(
            ignoring: _immersive,
            child: Container(
              color: AppColors.surface,
              child: SafeArea(
                top: false,
                child: SizedBox(height: 62, child: bar),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 预览页底部操作项（样式与存储页多选功能栏保持一致）
class _PreviewAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool danger;
  final VoidCallback onTap;

  const _PreviewAction({
    required this.icon,
    required this.label,
    this.danger = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.danger : AppColors.ink2;
    return InkWell(
      onTap: onTap,
      child: SizedBox.expand(
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
      ),
    );
  }
}
