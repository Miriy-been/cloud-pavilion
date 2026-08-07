import 'dart:convert';

import 'package:file_picker/file_picker.dart' hide FileType;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_application_2/api/FileApi.dart';
import 'package:flutter_application_2/api/WorkflowApi.dart';
import 'package:flutter_application_2/config/AppTheme.dart';
import 'package:flutter_application_2/config/AppWidgets.dart';
import 'package:flutter_application_2/enums/FileType.dart';
import 'package:flutter_application_2/model/FileItemModel.dart';
import 'package:flutter_application_2/page/index/FileSelectionMixin.dart';
import 'package:flutter_application_2/page/index/trash.dart';
import 'package:flutter_application_2/page/index/search.dart';
import 'package:flutter_application_2/page/preview/AudioPlayerPage.dart';
import 'package:flutter_application_2/page/preview/PreviewPage.dart';
import 'package:flutter_application_2/page/tools/FolderPicker.dart';
import '../../util/AudioPlayerService.dart';
import '../../util/DownloadManager.dart';
import '../../util/ErrorText.dart';
import '../../util/SpUtils.dart';
import '../../util/UploadManager.dart';
import '../../util/WorkflowTaskManager.dart';

/// 存储主页（列表 / 网格 / 多选）
class Index extends StatefulWidget {
  /// 多选状态变化回调（用于隐藏底部主导航栏）
  final ValueChanged<bool>? onSelectionChanged;

  Index({super.key, this.onSelectionChanged});

  @override
  State<Index> createState() => _IndexState();
}

class _IndexState extends State<Index>
    with AutomaticKeepAliveClientMixin, FileSelectionMixin<Index> {
  late List<FileItemModel> currentList = [];
  // 视图与排序
  bool _isGridView = false;
  String _orderBy = '';
  String _orderDirection = '';
  // 文件夹导航栈（用于面包屑与返回上级）
  final List<FileItemModel> _folderStack = [];

  @override
  ValueChanged<bool>? get onSelectionChanged => widget.onSelectionChanged;

  /// 批量操作完成后的列表刷新
  @override
  void afterAction() => _refresh();

  // 控件被创建的时候，会执行 initState
  @override
  void initState() {
    super.initState();
    // 文件夹打包下载（服务器压缩后自动下载）
    onFolderDownload = _downloadFolder;
    getRootFileList();
    _loadGridView();
    // 上传任务状态变化（新增/完成/取消）时刷新当前目录列表
    UploadManager.instance.addListener(_onUploadChanged);
    // 服务器端压缩/解压任务完成时刷新当前目录列表
    WorkflowTaskManager.instance.addListener(_onWorkflowTaskChanged);
  }

  /// 恢复全局视图模式
  Future<void> _loadGridView() async {
    final grid = await SpUtils.getBool('gridView');
    if (mounted && grid != _isGridView) {
      setState(() => _isGridView = grid);
    }
  }

  @override
  void dispose() {
    UploadManager.instance.removeListener(_onUploadChanged);
    WorkflowTaskManager.instance.removeListener(_onWorkflowTaskChanged);
    super.dispose();
  }

  /// 上传任务变化时刷新当前目录列表
  void _onUploadChanged() {
    if (mounted) _refresh();
  }

  /// 服务器端压缩/解压任务完成时刷新当前目录列表
  void _onWorkflowTaskChanged() {
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return PopScope(
      canPop: !selectionMode && _folderStack.isEmpty,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (selectionMode) {
          // 多选模式下返回键优先退出多选
          setSelectionMode(false);
        } else if (_folderStack.isNotEmpty) {
          // 子目录内按系统返回键 → 返回上级
          _goUp();
        }
      },
      child: Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: pagePad),
            child: _buildHeader(),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  if (currentList.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(pagePad,
                            _folderStack.isEmpty ? 20 : 0, pagePad, 6),
                        child: SectionHeader(
                          title: '全部文件',
                          count: '${currentList.length}',
                          trailing: SortChip(
                            options: const [
                              SortOption('', '默认排序'),
                              SortOption('name', '按名称'),
                              SortOption('size', '按大小'),
                              SortOption('updated_at', '按修改时间'),
                            ],
                            value: _orderBy,
                            direction: _orderDirection,
                            onChanged: _setOrder,
                            onToggleDirection: () {
                              setState(() {
                                _orderDirection = _orderDirection == 'desc'
                                    ? 'asc'
                                    : 'desc';
                              });
                              _refresh();
                            },
                          ),
                        ),
                      ),
                    ),
                  if (currentList.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: EmptyState(
                        icon: Icons.cloud_outlined,
                        title: '这里空空如也',
                        subtitle: '上传你的第一个文件，开启云端之旅',
                        actionLabel: '上传文件',
                        onAction: onUpload,
                      ),
                    )
                  else if (_isGridView)
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                          pagePad, 6, pagePad, 16),
                      sliver: SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 14,
                          crossAxisSpacing: 12,
                          childAspectRatio: 0.82,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          _buildGridItem,
                          childCount: currentList.length,
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                          pagePad, 6, pagePad, 16),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          _buildListItem,
                          childCount: currentList.length,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: selectionMode
          ? null
          : FloatingActionButton(
              onPressed: _showQuickMenu,
              backgroundColor: AppColors.primarySoft,
              foregroundColor: AppColors.primary,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18)),
              child: const Icon(Icons.add, size: 26),
            ),
      bottomNavigationBar: selectionMode ? buildActionBar() : null,
      ),
    );
  }

  /// 自定义头部
  Widget _buildHeader() {
    if (selectionMode) {
      return PageHeader(
        leading: IconTile(
          icon: Icons.close,
          onTap: exitSelection,
        ),
        title: '已选 ${selected.length} 项',
        actions: [
          TextButton(
            onPressed: () => selectAll(currentList),
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
    // 顶部两行布局：上行返回箭头 + 右侧功能图标；下行独立面包屑
    return Padding(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 12,
        bottom: 8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (_folderStack.isEmpty)
                Text(
                  '存储',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                    color: AppColors.ink,
                  ),
                )
              else
                IconTile(
                  icon: Icons.arrow_back_ios_new,
                  filled: false,
                  compact: true,
                  onTap: _goUp,
                ),
              const Spacer(),
              // 音乐悬浮入口：仅后台播放时显示，节省顶部空间
              ListenableBuilder(
                listenable: AudioPlayerService.instance,
                builder: (context, _) {
                  if (!AudioPlayerService.instance.isActive) {
                    return const SizedBox.shrink();
                  }
                  return _headerAction(
                    IconTile(
                      icon: Icons.music_note,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const AudioPlayerPage()),
                      ),
                      child: Icon(Icons.music_note,
                          size: 22, color: AppColors.primary),
                    ),
                  );
                },
              ),
              _headerAction(
                IconTile(
                  icon: Icons.search,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SearchPage()),
                  ),
                ),
              ),
              // 视图切换：当前为网格时显示列表图标，反之显示网格图标
              _headerAction(
                IconTile(
                  icon: _isGridView
                      ? Icons.view_list_outlined
                      : Icons.grid_view_outlined,
                  onTap: () => _setGridView(!_isGridView),
                ),
              ),
              // 回收站入口（原三点菜单功能已分散到排序胶囊 / 悬浮按钮）
              _headerAction(
                IconTile(
                  icon: Icons.delete_outline,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const TrashPage()),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // 面包屑独立成行，单行可横向滑动查看完整路径
          _buildBreadcrumb(),
        ],
      ),
    );
  }

  /// 头部操作项（与 PageHeader 一致的行间距）
  Widget _headerAction(Widget child) {
    return Padding(padding: const EdgeInsets.only(left: 6), child: child);
  }

  /// 悬浮按钮快捷菜单
  void _showQuickMenu() {
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
              Text(
                '快速操作',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink3),
              ),
              const SizedBox(height: 12),
              _QuickAction(
                icon: Icons.file_upload_outlined,
                color: AppColors.primary,
                bg: AppColors.primarySoft,
                label: '上传文件',
                onTap: () {
                  Navigator.pop(ctx);
                  onUpload();
                },
              ),
              _QuickAction(
                icon: Icons.create_new_folder_outlined,
                color: FileType.IMAGE.fg,
                bg: FileType.IMAGE.bg,
                label: '新建文件夹',
                onTap: () {
                  Navigator.pop(ctx);
                  onCreateFolder();
                },
              ),
              _QuickAction(
                icon: Icons.note_add_outlined,
                color: FileType.AUDIO.fg,
                bg: FileType.AUDIO.bg,
                label: '新建文件',
                onTap: () {
                  Navigator.pop(ctx);
                  onCreateFile();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void getRootFileList() async {
    String menu = await SpUtils.getString('currentMenu');
    if (menu.isEmpty) {
      menu = FileApi.myRootUri;
      await SpUtils.setString('currentMenu', menu);
    }
    // 恢复上次浏览路径（面包屑栈）
    final restored = await _loadFolderStack();
    if (restored.isNotEmpty && restored.last.path != menu) {
      // 与当前目录不一致（如切换账号），丢弃旧栈
      restored.clear();
    }
    setState(() {
      _folderStack
        ..clear()
        ..addAll(restored);
    });
    _saveFolderStack();
    try {
      final data = await FileApi.listFiles(menu,
          orderBy: _orderBy, orderDirection: _orderDirection);
      if (!mounted) return;
      setState(() {
        currentList = _parseFiles(data);
      });
    } catch (e) {
      _showLoadError(e);
    }
  }

  void inDir(FileItemModel obj) async {
    if (!obj.isDir) return;
    await SpUtils.setString('currentMenu', obj.path);
    try {
      final data = await FileApi.listFiles(obj.path,
          orderBy: _orderBy, orderDirection: _orderDirection);
      if (!mounted) return;
      setState(() {
        _folderStack.add(obj);
        currentList = _parseFiles(data);
      });
      _saveFolderStack();
    } catch (e) {
      _showLoadError(e);
    }
  }

  /// 返回上级目录
  void _goUp() {
    if (_folderStack.isEmpty) return;
    final parent = _folderStack.length > 1
        ? _folderStack[_folderStack.length - 2]
        : null;
    _folderStack.removeLast();
    final menu = parent == null ? FileApi.myRootUri : parent.path;
    SpUtils.setString('currentMenu', menu);
    FileApi.listFiles(menu,
            orderBy: _orderBy, orderDirection: _orderDirection)
        .then((data) {
      if (!mounted) return;
      setState(() {
        currentList = _parseFiles(data);
      });
    }).catchError((Object e) {
      _showLoadError(e);
    });
    _saveFolderStack();
  }

  /// 面包屑导航（置于头部，每段可点击跳转；根目录显示「我的存储」）
  Widget _buildBreadcrumb() {
    final segments = <Widget>[
      _BreadcrumbSegment(
        label: '我的存储',
        active: _folderStack.isEmpty,
        onTap: _folderStack.isEmpty ? null : () => _jumpToLevel(0),
      ),
    ];
    for (var i = 0; i < _folderStack.length; i++) {
      final isLast = i == _folderStack.length - 1;
      segments.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Text('›',
            style: TextStyle(
                fontSize: 16,
                height: 1,
                color: AppColors.ink3.withValues(alpha: 0.7))),
      ));
      segments.add(_BreadcrumbSegment(
        label: _folderStack[i].name,
        active: isLast,
        onTap: isLast ? null : () => _jumpToLevel(i + 1),
      ));
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: segments),
    );
  }

  /// 跳转到面包屑指定层级（index 为段序号，0 = 根目录）
  void _jumpToLevel(int index) {
    if (index < 0 || index > _folderStack.length) return;
    if (index == _folderStack.length) return;
    final target = index == 0 ? null : _folderStack[index - 1];
    _folderStack.removeRange(index, _folderStack.length);
    final menu = target == null ? FileApi.myRootUri : target.path;
    SpUtils.setString('currentMenu', menu);
    FileApi.listFiles(menu,
            orderBy: _orderBy, orderDirection: _orderDirection)
        .then((data) {
      if (!mounted) return;
      setState(() {
        currentList = _parseFiles(data);
      });
    }).catchError((Object e) {
      _showLoadError(e);
    });
    _saveFolderStack();
  }

  /// 持久化面包屑栈（保存 {name, path} 列表，重启后恢复）
  Future<void> _saveFolderStack() {
    final data =
        _folderStack.map((e) => {'name': e.name, 'path': e.path}).toList();
    return SpUtils.setString('folderStack', jsonEncode(data));
  }

  /// 读取持久化的面包屑栈
  Future<List<FileItemModel>> _loadFolderStack() async {
    final raw = await SpUtils.getString('folderStack');
    if (raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) {
        final m = e as Map<String, dynamic>;
        return FileItemModel(
          type: 1,
          id: '',
          name: m['name']?.toString() ?? '',
          size: 0,
          path: m['path']?.toString() ?? '',
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _refresh() async {
    String menu = await SpUtils.getString('currentMenu');
    if (menu.isEmpty) menu = FileApi.myRootUri;
    // 下拉刷新：绕过列表缓存，成功后自动更新缓存
    try {
      final data = await FileApi.listFiles(menu,
          orderBy: _orderBy,
          orderDirection: _orderDirection,
          useCache: false);
      if (!mounted) return;
      setState(() {
        currentList = _parseFiles(data);
      });
    } catch (e) {
      _showLoadError(e);
    }
  }

  /// 列表加载失败提示（如登录态失效 / 网络异常），不打断页面状态
  void _showLoadError(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(appSnack('加载失败：${errorText(e, '请下拉刷新重试')}'));
  }

  List<FileItemModel> _parseFiles(Map<String, dynamic> data) {
    final files = data['files'];
    if (files is! List) return [];
    return files
        .map((e) => FileItemModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 设置排序字段并刷新
  void _setOrder(String field) {
    setState(() {
      _orderBy = field;
      if (field.isEmpty) _orderDirection = '';
    });
    _refresh();
  }

  /// 切换视图模式（全局生效并持久化）
  void _setGridView(bool grid) {
    setState(() => _isGridView = grid);
    SpUtils.setBool('gridView', grid);
  }

  /// 列表视图项
  Widget _buildListItem(BuildContext context, int index) {
    final obj = currentList[index];
    final isSelected = selectionMode && selected.contains(obj);
    return ItemEnter(
      child: FileRow(
      type: obj.type,
      name: obj.name,
      meta: _metaOf(obj),
      selected: isSelected,
      leading: selectionMode
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () => toggleSelect(obj),
                  child: RoundCheck(on: isSelected),
                ),
                const SizedBox(width: 12),
                FileTile(type: obj.type, name: obj.name),
              ],
            )
          : null,
      trailing: selectionMode
          ? null
          : Icon(Icons.chevron_right, size: 20, color: AppColors.ink3),
      onTap: () {
        if (selectionMode) {
          toggleSelect(obj);
        } else {
          _openFile(obj);
        }
      },
      onLongPress: (details) {
        // 与网格页一致：长按直接进入多选并选中当前项，底部展示操作栏
        if (!selectionMode) {
          setSelectionMode(true);
        }
        toggleSelect(obj);
      },
      ),
    );
  }

  /// 网格视图项
  Widget _buildGridItem(BuildContext context, int index) {
    final obj = currentList[index];
    final isSelected = selectionMode && selected.contains(obj);
    return ItemEnter(
      child: GestureDetector(
        onLongPressStart: (details) {
          if (!selectionMode) {
            setSelectionMode(true);
          }
          toggleSelect(obj);
        },
        onTap: () {
          if (selectionMode) {
            toggleSelect(obj);
          } else {
            _openFile(obj);
          }
        },
        child: Container(
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primarySoft : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                children: [
                  GridThumb(key: ValueKey(obj.path), file: obj, size: 58),
                  if (selectionMode)
                    Positioned(
                      right: -2,
                      top: -2,
                      child: RoundCheck(on: isSelected),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                obj.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12, color: AppColors.ink, height: 1.3),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _metaOf(FileItemModel obj) {
    if (obj.isDir) {
      return '文件夹 · ${_formatTime(obj.updatedAt)}';
    }
    return '${formatBytes(obj.size)} · ${_formatTime(obj.updatedAt)}';
  }

  /// 打开文件（文件夹进入，文件预览；音频进入播放页）
  void _openFile(FileItemModel obj) {
    if (obj.isDir) {
      inDir(obj);
      return;
    }
    if (FileType.isAudio(obj.type, obj.name)) {
      // 音频：以全站音频库为播放列表，定位到当前歌曲开始播放
      AudioPlayerService.instance.playFromLibrary(obj);
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AudioPlayerPage()),
      );
      return;
    }
    _openPreview(obj);
  }

  /// 打开文件预览（传入同目录列表以支持左右滑动切换；删除后返回刷新）
  Future<void> _openPreview(FileItemModel obj) async {
    final refreshed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => PreviewPage(
          fileUri: obj.path,
          fileName: obj.name,
          siblings: currentList,
          initialIndex: currentList.indexOf(obj),
        ),
      ),
    );
    if (refreshed == true && mounted) _refresh();
  }

  /// 批量压缩为 ZIP
  Future<void> _batchCompress() async {
    final items = selected.toList();
    exitSelection();
    await onCompress(items);
  }

  /// 低频操作弹窗：压缩 / 解压
  void showMoreActions() {
    final hasArchive = selected.any((e) => _isArchiveFile(e.name));
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
              Text(
                '更多操作',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink3),
              ),
              const SizedBox(height: 12),
              _QuickAction(
                icon: Icons.drive_file_rename_outline,
                color: AppColors.primary,
                bg: AppColors.primarySoft,
                label: '重命名',
                onTap: () {
                  Navigator.pop(ctx);
                  batchRename(selected.toList());
                },
              ),
              _QuickAction(
                icon: Icons.drive_file_move_outline,
                color: FileType.IMAGE.fg,
                bg: FileType.IMAGE.bg,
                label: '移动 / 复制',
                onTap: () {
                  Navigator.pop(ctx);
                  batchMove(selected.toList());
                },
              ),
              _QuickAction(
                icon: Icons.archive_outlined,
                color: FileType.DOC.fg,
                bg: FileType.DOC.bg,
                label: '压缩为 ZIP',
                onTap: () {
                  Navigator.pop(ctx);
                  _batchCompress();
                },
              ),
              if (hasArchive)
                _QuickAction(
                  icon: Icons.unarchive_outlined,
                  color: FileType.AUDIO.fg,
                  bg: FileType.AUDIO.bg,
                  label: '解压',
                  onTap: () {
                    Navigator.pop(ctx);
                    _batchExtract();
                  },
                ),
              _QuickAction(
                icon: Icons.info_outline,
                color: AppColors.info,
                bg: AppColors.infoBg,
                label: '详情',
                onTap: () {
                  Navigator.pop(ctx);
                  if (selected.length != 1) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context)
                        .showSnackBar(appSnack('详情仅支持选择单个文件'));
                    return;
                  }
                  final obj = selected.first;
                  showFileDetailSheet(context, obj.path, obj.name);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 批量解压（选中的压缩包解压到当前目录）
  Future<void> _batchExtract() async {
    final archives =
        selected.where((e) => _isArchiveFile(e.name)).toList();
    if (archives.isEmpty) return;
    final confirmed = await showConfirmDialog(
        '解压', '确定将选中的 ${archives.length} 个压缩包解压到所选目录吗？');
    if (confirmed != true) return;
    final dir = await SpUtils.getString('currentMenu');
    // 选择解压目标目录（默认当前目录）
    final pick = await FolderPicker.pick(
      context,
      startUri: dir.isEmpty ? FileApi.myRootUri : dir,
      allowCopy: false,
      title: '解压到',
      confirmLabel: '解压到此',
    );
    if (pick == null) return;
    exitSelection();
    for (final obj in archives) {
      try {
        final task = await WorkflowApi.extractArchive(obj.path, pick.uri);
        final id = task['id']?.toString() ?? '';
        WorkflowTaskManager.instance.track(id, '解压 ${obj.name}');
      } catch (_) {}
    }
    _refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        appSnack('已创建解压任务，后台处理中，完成后将通知你'));
  }

  /// 是否为可解压的压缩包
  bool _isArchiveFile(String name) {
    final dot = name.lastIndexOf('.');
    if (dot == -1 || dot == name.length - 1) return false;
    return const {'zip', '7z', 'rar'}
        .contains(name.substring(dot + 1).toLowerCase());
  }

  /// 轮询后台任务直到完成（超时返回 false）
  Future<bool> _pollTask(String id, {int timeoutSeconds = 120}) async {
    final deadline = DateTime.now().add(Duration(seconds: timeoutSeconds));
    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(seconds: 2));
      try {
        final task = await WorkflowApi.findTaskById(id);
        if (task == null) continue;
        final status = task['status']?.toString() ?? '';
        if (status == 'completed') return true;
        if (status == 'error' || status == 'failed' || status == 'cancelled') {
          return false;
        }
      } catch (_) {}
    }
    return false;
  }

  String _formatTime(String? time) {
    if (time == null || time.isEmpty) return '';
    final dt = DateTime.tryParse(time);
    if (dt == null) return '';
    final local = dt.toLocal();
    return '${local.month.toString().padLeft(2, '0')}/${local.day.toString().padLeft(2, '0')}';
  }

  /// 文件夹打包下载：服务器压缩为 zip → 任务完成后自动下载
  Future<void> _downloadFolder(FileItemModel obj) async {
    final confirmed = await showConfirmDialog(
        '打包下载', '将「${obj.name}」压缩为 zip 后自动下载到本地？');
    if (confirmed != true) return;
    final dir = await SpUtils.getString('currentMenu');
    if (dir.isEmpty) return;
    final zipUri = '$dir/${Uri.encodeComponent('${obj.name}.zip')}';
    try {
      final task = await WorkflowApi.createArchive([obj.path], zipUri);
      final taskId = task['id']?.toString() ?? '';
      ScaffoldMessenger.of(context)
          .showSnackBar(appSnack('已创建打包任务，完成后将自动开始下载'));
      if (taskId.isNotEmpty) {
        final ok = await _pollTask(taskId);
        if (!mounted) return;
        if (!ok) {
          ScaffoldMessenger.of(context)
              .showSnackBar(appSnack('打包失败，请稍后重试'));
          return;
        }
      }
      final url = await FileApi.getDownloadUrl(zipUri);
      DownloadManager.instance.startDownload('${obj.name}.zip', url);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(appSnack('开始下载 ${obj.name}.zip'));
      _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(appSnack('打包下载失败：$e'));
    }
  }

  /// 压缩为 ZIP（单个或批量，可选输出目录）
  Future<void> onCompress(List<FileItemModel> items) async {
    final dir = await SpUtils.getString('currentMenu');
    final pick = await FolderPicker.pick(
      context,
      startUri: dir.isEmpty ? FileApi.myRootUri : dir,
      allowCopy: false,
      title: '压缩到',
      confirmLabel: '压缩到此',
    );
    if (pick == null) return;
    var name = await showInputDialog('压缩为 ZIP', '压缩包名称',
        initial: 'archive.zip');
    if (name == null || name.isEmpty) return;
    if (!name.toLowerCase().endsWith('.zip')) name = '$name.zip';
    final dst = '${pick.uri}/${Uri.encodeComponent(name)}';
    try {
      final task = await WorkflowApi.createArchive(
          items.map((e) => e.path).toList(), dst);
      final id = task['id']?.toString() ?? '';
      WorkflowTaskManager.instance.track(id, '压缩 $name');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(appSnack('压缩任务创建失败：$e'));
      return;
    }
    _refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(appSnack('已创建压缩任务，后台处理中，完成后将通知你'));
  }

  /// 新建文件夹
  void onCreateFolder() async {
    final name = await showInputDialog('新建文件夹', '文件夹名称');
    if (name == null || name.isEmpty) return;
    final menu = await SpUtils.getString('currentMenu');
    if (menu.isEmpty) return;
    await FileApi.createFolder(menu, name);
    _refresh();
  }

  /// 上传文件（后台静默，任务进入「传输」页，不阻塞操作）
  void onUpload() async {
    final picked = await FilePicker.platform
        .pickFiles(allowMultiple: true, withData: false);
    if (picked == null || picked.files.isEmpty) return;
    final menu = await SpUtils.getString('currentMenu');
    if (menu.isEmpty) return;

    var added = 0;
    for (final f in picked.files) {
      final path = f.path;
      if (path == null) continue;
      final uri = '$menu/${Uri.encodeComponent(f.name)}';
      UploadManager.instance.startUpload(
        name: f.name,
        uri: uri,
        sourcePath: path,
        size: f.size,
      );
      added++;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(appSnack('已添加 $added 个上传任务，可在「传输」页查看进度'));
  }

  /// 新建文件（创建空文本文件）
  void onCreateFile() async {
    final name = await showInputDialog('新建文件', '文件名（如：笔记.txt）',
        initial: '新建文件.txt');
    if (name == null || name.isEmpty) return;
    final menu = await SpUtils.getString('currentMenu');
    if (menu.isEmpty) return;
    final uri = '$menu/${Uri.encodeComponent(name)}';
    try {
      await FileApi.updateFileContent(uri, '');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(appSnack('新建文件失败：$e'));
      return;
    }
    _refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(appSnack('已创建「$name」'));
  }

  /// 保持页面状态
  @override
  bool get wantKeepAlive => true;
}

/// 面包屑段（可点击跳转；当前层级为高亮不可点）
class _BreadcrumbSegment extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback? onTap;

  const _BreadcrumbSegment({
    required this.label,
    this.active = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        // 所有段（含选中态胶囊）水平内边距一律归零，保证面包屑与
        // 标题、「全部文件」等统计行保持同一左对齐边距，全页面无错位
        padding: const EdgeInsets.symmetric(vertical: 5),
        decoration: active
            ? BoxDecoration(
                color: AppColors.primarySoft.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(999),
              )
            : null,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: active ? FontWeight.w600 : FontWeight.w500,
            color: active ? AppColors.primary : AppColors.ink2,
          ),
        ),
      ),
    );
  }
}

/// 快捷操作行
class _QuickAction extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color bg;
  final String label;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.color,
    required this.bg,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 21, color: color),
            ),
            const SizedBox(width: 14),
            Text(
              label,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: AppColors.ink),
            ),
          ],
        ),
      ),
    );
  }
}
