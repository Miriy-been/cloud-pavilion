import 'package:flutter/material.dart';
import 'package:cloudpavilion/api/FileApi.dart';
import 'package:cloudpavilion/config/AppTheme.dart';
import 'package:cloudpavilion/config/AppWidgets.dart';
import 'package:cloudpavilion/enums/FileType.dart';
import 'package:cloudpavilion/model/FileItemModel.dart';
import 'package:cloudpavilion/model/FileListPage.dart';
import 'package:cloudpavilion/page/preview/AudioPlayerPage.dart';
import 'package:cloudpavilion/page/preview/PreviewPage.dart';
import 'package:cloudpavilion/util/AudioPlayerService.dart';

/// 文件搜索页（V4 list files 支持 name 查询条件）
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _controller = TextEditingController();
  List<FileItemModel> _results = [];
  final List<String> _recents = [];
  bool _searched = false;
  bool _loading = false;
  /// 当前搜索关键词（加载更多时复用，避免用户改动输入框导致翻页错乱）
  String _keyword = '';
  /// 下一页游标（搜索走游标分页，翻页必须回传 next_token）
  String _nextToken = '';
  /// 是否正在加载下一页（防重复触发）
  bool _loadingMore = false;

  /// 是否还有更多结果可加载
  bool get _hasMore => _nextToken.isNotEmpty;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search(String keyword) async {
    final kw = keyword.trim();
    if (kw.isEmpty) return;
    setState(() {
      _loading = true;
      _searched = true;
      _keyword = kw;
      if (!_recents.contains(kw)) {
        _recents.insert(0, kw);
        if (_recents.length > 5) _recents.removeLast();
      }
    });
    final uri =
        '${FileApi.myRootUri}?name=${Uri.encodeQueryComponent(kw)}';
    try {
      final data = await FileApi.listFiles(uri, useCache: false);
      if (!mounted) return;
      final page = FileListPage.fromData(data);
      setState(() {
        _results = page.items;
        _nextToken = page.nextToken;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _results = [];
        _nextToken = '';
        _loading = false;
      });
    }
  }

  /// 加载下一页搜索结果（滚动到底部时触发）
  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _keyword.isEmpty) return;
    _loadingMore = true;
    try {
      final uri =
          '${FileApi.myRootUri}?name=${Uri.encodeQueryComponent(_keyword)}';
      final data = await FileApi.listFiles(uri,
          nextPageToken: _nextToken, useCache: false);
      if (!mounted) return;
      final page =
          FileListPage.fromData(data, loadedBefore: _results.length);
      setState(() {
        _results = [..._results, ...page.items];
        _nextToken = page.nextToken;
      });
      // 空页但仍有 token：防止无限续拉
      if (page.items.isEmpty) setState(() => _nextToken = '');
    } catch (_) {
      // 加载更多失败不打断已有结果
    } finally {
      _loadingMore = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    // 订阅主题：深浅色切换时重建页面
    Theme.of(context);
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
                pagePad, MediaQuery.of(context).padding.top + 8, pagePad, 0),
            child: Row(
              children: [
                IconTile(
                  icon: Icons.arrow_back_ios_new,
                  filled: false,
                  onTap: () => Navigator.pop(context),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      border: Border.all(color: AppColors.line),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [
                        BoxShadow(
                          color: AppColors.shadow,
                          blurRadius: 12,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: _controller,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      onSubmitted: _search,
                      style: TextStyle(
                          fontSize: 14.5, color: AppColors.ink),
                      decoration: InputDecoration(
                        hintText: '搜索文件名',
                        hintStyle: TextStyle(color: AppColors.ink3),
                        border: InputBorder.none,
                        prefixIcon: Icon(Icons.search,
                            size: 22, color: AppColors.ink3),
                        contentPadding: EdgeInsets.symmetric(vertical: 13),
                      ),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    textStyle: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  child: const Text('取消'),
                ),
              ],
            ),
          ),
          Expanded(
            child: _buildBody(),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!_searched) {
      if (_recents.isEmpty) {
        return const EmptyState(
          icon: Icons.search,
          title: '输入关键词搜索文件',
          subtitle: '支持搜索当前站点下的所有文件',
        );
      }
      return ListView(
        padding: EdgeInsets.fromLTRB(pagePad, 16, pagePad,
            MediaQuery.of(context).padding.bottom + 16),
        children: [
          const SectionHeader(title: '最近搜索'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _recents
                .map((kw) => GestureDetector(
                      onTap: () => _search(kw),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          border: Border.all(color: AppColors.line),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          kw,
                          style: TextStyle(
                              fontSize: 12.5, color: AppColors.ink2),
                        ),
                      ),
                    ))
                .toList(),
          ),
        ],
      );
    }
    if (_results.isEmpty) {
      return const EmptyState(
        icon: Icons.search_off,
        title: '未找到匹配的文件',
        subtitle: '换个关键词试试',
      );
    }
    return NotificationListener<ScrollNotification>(
      // 滚动到底部自动续拉下一页（搜索走游标分页）
      onNotification: (n) {
        if (n.metrics.extentAfter < 400) _loadMore();
        return false;
      },
      child: ListView.builder(
      padding: EdgeInsets.fromLTRB(pagePad, 6, pagePad,
          MediaQuery.of(context).padding.bottom + 16),
      // 末尾多一项：还有下一页时显示加载指示
      itemCount: _results.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _results.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final obj = _results[index];
        return FileRow(
          type: obj.type,
          name: obj.name,
          meta: obj.isDir ? '文件夹' : formatBytes(obj.size),
          onTap: () {
            if (obj.isDir) return;
            if (FileType.isAudio(obj.type, obj.name)) {
              // 音频：以全站音频库为播放列表，定位到当前歌曲开始播放
              AudioPlayerService.instance.playFromLibrary(obj);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AudioPlayerPage()),
              );
              return;
            }
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PreviewPage(
                  fileUri: obj.path,
                  fileName: obj.name,
                  siblings: _results,
                  initialIndex: index,
                ),
              ),
            );
          },
        );
      },
      ),
    );
  }
}
