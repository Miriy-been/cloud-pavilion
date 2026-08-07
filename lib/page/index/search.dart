import 'package:flutter/material.dart';
import 'package:cloudpavilion/api/FileApi.dart';
import 'package:cloudpavilion/config/AppTheme.dart';
import 'package:cloudpavilion/config/AppWidgets.dart';
import 'package:cloudpavilion/enums/FileType.dart';
import 'package:cloudpavilion/model/FileItemModel.dart';
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
      if (!_recents.contains(kw)) {
        _recents.insert(0, kw);
        if (_recents.length > 5) _recents.removeLast();
      }
    });
    final uri =
        '${FileApi.myRootUri}?name=${Uri.encodeQueryComponent(kw)}';
    final data = await FileApi.listFiles(uri);
    setState(() {
      _results = _parseFiles(data);
      _loading = false;
    });
  }

  List<FileItemModel> _parseFiles(Map<String, dynamic> data) {
    final files = data['files'];
    if (files is! List) return [];
    return files
        .map((e) => FileItemModel.fromJson(e as Map<String, dynamic>))
        .toList();
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
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(pagePad, 6, pagePad,
          MediaQuery.of(context).padding.bottom + 16),
      itemCount: _results.length,
      itemBuilder: (context, index) {
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
    );
  }
}
