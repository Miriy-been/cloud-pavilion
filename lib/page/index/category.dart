import 'package:flutter/material.dart';
import 'package:cloudpavilion/api/FileApi.dart';
import 'package:cloudpavilion/config/AppTheme.dart';
import 'package:cloudpavilion/config/AppWidgets.dart';
import 'package:cloudpavilion/enums/FileType.dart';
import 'package:cloudpavilion/model/FileItemModel.dart';
import 'package:cloudpavilion/page/index/FileSelectionMixin.dart';
import 'package:cloudpavilion/page/preview/AudioPlayerPage.dart';
import 'package:cloudpavilion/page/preview/PreviewPage.dart';
import 'package:cloudpavilion/util/AudioPlayerService.dart';
import '../../util/SpUtils.dart';

/// 分类页：按文件类型快速筛选（图片 / 视频 / 音乐 / 文档）
class CategoryPage extends StatefulWidget {
  const CategoryPage({super.key});

  @override
  State<CategoryPage> createState() => _CategoryPageState();
}

class _CategoryPageState extends State<CategoryPage>
    with AutomaticKeepAliveClientMixin {
  static const List<_CategoryItem> _items = [
    _CategoryItem(
        cat: 'image',
        title: '图片',
        desc: 'png · jpg · webp · gif',
        type: FileType.IMAGE),
    _CategoryItem(
        cat: 'video',
        title: '视频',
        desc: 'mp4 · mkv · mov',
        type: FileType.VIDEO),
    _CategoryItem(
        cat: 'audio',
        title: '音乐',
        desc: 'mp3 · wav · flac',
        type: FileType.AUDIO),
    _CategoryItem(
        cat: 'document',
        title: '文档',
        desc: 'pdf · doc · txt · md',
        type: FileType.DOC),
  ];

  /// 分类页自身展示：双列卡片 / 列表行（独立持久化，默认卡片网格）
  bool _isGridView = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadView();
  }

  /// 恢复分类页视图模式
  Future<void> _loadView() async {
    final grid = await SpUtils.getBool('categoryView', true);
    if (mounted && grid != _isGridView) {
      setState(() => _isGridView = grid);
    }
  }

  /// 切换分类页视图模式（网格 / 列表），持久化
  void _toggleView() {
    setState(() => _isGridView = !_isGridView);
    SpUtils.setBool('categoryView', _isGridView);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // 订阅主题：深浅色切换时重建页面
    Theme.of(context);
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: pagePad),
            child: PageHeader(
              title: '分类',
              subtitle: '按文件类型快速筛选',
              actions: [
                // 视图切换：当前为网格时显示列表图标，反之显示网格图标（与存储页一致）
                IconTile(
                  icon: _isGridView
                      ? Icons.view_list_outlined
                      : Icons.grid_view_outlined,
                  onTap: _toggleView,
                ),
              ],
            ),
          ),
          Expanded(
            child: _isGridView
                ? _buildGrid()
                : ListView.builder(
                    padding: EdgeInsets.fromLTRB(pagePad, 6, pagePad, 16),
                    itemCount: _items.length,
                    itemBuilder: (context, index) =>
                        _buildCard(_items[index], listMode: true),
                  ),
          ),
        ],
      ),
    );
  }

  /// 双列卡片网格
  Widget _buildGrid() {
    return GridView.count(
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      padding: EdgeInsets.fromLTRB(pagePad, 6, pagePad, 16),
      childAspectRatio: 1.5,
      children: [for (final item in _items) _buildCard(item)],
    );
  }

  /// 分类卡片（网格 / 列表两种形态共用同一视觉组件）
  Widget _buildCard(_CategoryItem item, {bool listMode = false}) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CategoryFilesPage(
            category: item.cat,
            title: item.title,
          ),
        ),
      ),
      child: Container(
        padding: listMode
            ? const EdgeInsets.symmetric(horizontal: 16, vertical: 12)
            : const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.line),
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [
            BoxShadow(
              color: AppColors.shadow,
              blurRadius: 16,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: item.type.bg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(item.type.icon, size: 24, color: item.type.fg),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.desc,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: AppColors.ink3),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 20, color: AppColors.ink3),
          ],
        ),
      ),
    );
  }
}

class _CategoryItem {
  final String cat;
  final String title;
  final String desc;
  final FileType type;

  const _CategoryItem({
    required this.cat,
    required this.title,
    required this.desc,
    required this.type,
  });
}

/// 分类筛选结果列表页（复用存储文件夹的视图切换 + 排序功能）
class CategoryFilesPage extends StatefulWidget {
  final String category; // image / video / audio / document
  final String title;

  const CategoryFilesPage({
    super.key,
    required this.category,
    required this.title,
  });

  @override
  State<CategoryFilesPage> createState() => _CategoryFilesPageState();
}

class _CategoryFilesPageState extends State<CategoryFilesPage>
    with FileSelectionMixin<CategoryFilesPage> {
  List<FileItemModel> _items = [];
  bool _loading = true;
  // 与存储页共用的全局文件视图模式（列表 / 网格）
  bool _isGridView = false;
  // 排序
  String _orderBy = '';
  String _orderDirection = '';

  /// 批量操作完成后的列表刷新
  @override
  void afterAction() => _load(showLoading: false);

  @override
  void initState() {
    super.initState();
    _loadView();
    _load();
  }

  /// 恢复全局文件视图模式
  Future<void> _loadView() async {
    final grid = await SpUtils.getBool('gridView');
    if (mounted && grid != _isGridView) {
      setState(() => _isGridView = grid);
    }
  }

  /// 切换视图模式（全局生效并持久化，与存储页一致）
  void _setGridView(bool grid) {
    setState(() => _isGridView = grid);
    SpUtils.setBool('gridView', grid);
  }

  /// 设置排序字段并重新加载
  void _setOrder(String field) {
    setState(() {
      _orderBy = field;
      if (field.isEmpty) _orderDirection = '';
    });
    _load(showLoading: false);
  }

  Future<void> _load({bool showLoading = true, bool useCache = true}) async {
    if (showLoading) setState(() => _loading = true);
    try {
      final uri = '${FileApi.myRootUri}?category=${widget.category}';
      final data = await FileApi.listFiles(uri,
          pageSize: 200,
          orderBy: _orderBy,
          orderDirection: _orderDirection,
          useCache: useCache);
      if (!mounted) return;
      setState(() {
        _items = _parseFiles(data);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  List<FileItemModel> _parseFiles(Map<String, dynamic> data) {
    final files = data['files'];
    if (files is! List) return [];
    return files
        .map((e) => FileItemModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> _open(FileItemModel obj) async {
    if (obj.isDir) return;
    if (widget.category == 'audio' && FileType.isAudio(obj.type, obj.name)) {
      // 音乐分类：以全站音频库为播放列表，定位到当前歌曲开始播放
      AudioPlayerService.instance.playFromLibrary(obj);
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AudioPlayerPage()),
      );
      return;
    }
    final refreshed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => PreviewPage(
          fileUri: obj.path,
          fileName: obj.name,
          siblings: _items,
          initialIndex: _items.indexOf(obj),
        ),
      ),
    );
    if (refreshed == true && mounted) afterAction();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return PopScope(
      canPop: !selectionMode,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        // 多选模式下返回键优先退出多选
        exitSelection();
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: pagePad),
              child: selectionMode
                  ? PageHeader(
                      leading: IconTile(
                        icon: Icons.close,
                        onTap: exitSelection,
                      ),
                      title: '已选 ${selected.length} 项',
                      actions: [
                        TextButton(
                          onPressed: () => selectAll(_items),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            textStyle: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                          child: const Text('全选'),
                        ),
                      ],
                    )
                  : PageHeader(
                      title: widget.title,
                      secondary: true,
                      leading: IconTile(
                        icon: Icons.arrow_back_ios_new,
                        filled: false,
                        compact: true,
                        onTap: () => Navigator.pop(context),
                      ),
                      actions: [
                        // 视图切换：当前为网格时显示列表图标，反之显示网格图标（与存储页一致）
                        IconTile(
                          icon: _isGridView
                              ? Icons.view_list_outlined
                              : Icons.grid_view_outlined,
                          onTap: () => _setGridView(!_isGridView),
                        ),
                      ],
                    ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                    ? const EmptyState(
                        icon: Icons.folder_off_outlined,
                        title: '暂无文件',
                        subtitle: '当前分类下还没有文件',
                      )
                    : RefreshIndicator(
                        onRefresh: () =>
                            _load(showLoading: false, useCache: false),
                        child: CustomScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          slivers: [
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: EdgeInsets.fromLTRB(
                                    pagePad, 16, pagePad, 6),
                                child: SectionHeader(
                                  title: '全部文件',
                                  count: '${_items.length}',
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
                                        _orderDirection =
                                            _orderDirection == 'desc'
                                                ? 'asc'
                                                : 'desc';
                                      });
                                      _load(showLoading: false);
                                    },
                                  ),
                                ),
                              ),
                            ),
                            if (_isGridView)
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
                                    (context, index) {
                                      final obj = _items[index];
                                      return _buildGridItem(obj);
                                    },
                                    childCount: _items.length,
                                  ),
                                ),
                              )
                            else
                              SliverPadding(
                                padding: EdgeInsets.fromLTRB(
                                    pagePad,
                                    6,
                                    pagePad,
                                    MediaQuery.of(context).padding.bottom + 16),
                                sliver: SliverList(
                                  delegate: SliverChildBuilderDelegate(
                                    (context, index) {
                                      final obj = _items[index];
                                      final isSelected =
                                          selectionMode && selected.contains(obj);
                                      return ItemEnter(
                                        child: FileRow(
                                          type: obj.type,
                                          name: obj.name,
                                          meta: formatBytes(obj.size),
                                          selected: isSelected,
                                          leading: selectionMode
                                              ? Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    GestureDetector(
                                                      onTap: () =>
                                                          toggleSelect(obj),
                                                      child: RoundCheck(
                                                          on: isSelected),
                                                    ),
                                                    const SizedBox(width: 12),
                                                    FileTile(
                                                        type: obj.type,
                                                        name: obj.name),
                                                  ],
                                                )
                                              : null,
                                          trailing: selectionMode
                                              ? null
                                              : Icon(Icons.chevron_right,
                                                  size: 20,
                                                  color: AppColors.ink3),
                                          onTap: () {
                                            if (selectionMode) {
                                              toggleSelect(obj);
                                            } else {
                                              _open(obj);
                                            }
                                          },
                                          onLongPress: (details) {
                                            if (!selectionMode) {
                                              setSelectionMode(true);
                                            }
                                            toggleSelect(obj);
                                          },
                                        ),
                                      );
                                    },
                                    childCount: _items.length,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
          ),
        ],
      ),
      bottomNavigationBar: selectionMode ? buildActionBar() : null,
      ),
    );
  }

  /// 网格视图项（与存储页网格一致，支持多选）
  Widget _buildGridItem(FileItemModel obj) {
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
            _open(obj);
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
                style:
                    TextStyle(fontSize: 12, color: AppColors.ink, height: 1.3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
