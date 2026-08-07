import 'package:flutter/material.dart';
import 'package:cloudpavilion/api/FileApi.dart';
import 'package:cloudpavilion/config/AppTheme.dart';
import 'package:cloudpavilion/config/AppWidgets.dart';
import 'package:cloudpavilion/model/FileItemModel.dart';

/// 回收站管理页
class TrashPage extends StatefulWidget {
  const TrashPage({super.key});

  @override
  State<TrashPage> createState() => _TrashPageState();
}

class _TrashPageState extends State<TrashPage> {
  List<FileItemModel> _items = [];
  bool _loading = true;
  // 排序
  String _orderBy = '';
  String _orderDirection = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool showLoading = true, bool useCache = true}) async {
    if (showLoading) setState(() => _loading = true);
    try {
      final data = await FileApi.listFiles(FileApi.trashUri,
          orderBy: _orderBy, orderDirection: _orderDirection, useCache: useCache);
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

  /// 设置排序字段并刷新
  void _setOrder(String field) {
    setState(() {
      _orderBy = field;
      if (field.isEmpty) _orderDirection = '';
    });
    _load(showLoading: false);
  }

  List<FileItemModel> _parseFiles(Map<String, dynamic> data) {
    final files = data['files'];
    if (files is! List) return [];
    return files
        .map((e) => FileItemModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 恢复文件
  Future<void> _restore(FileItemModel obj) async {
    await FileApi.restoreFiles([obj.path]);
    _load(showLoading: false, useCache: false);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(appSnack('已恢复「${obj.name}」'));
  }

  /// 彻底删除
  Future<void> _deleteForever(FileItemModel obj) async {
    final confirmed = await _confirm('彻底删除',
        '确定永久删除「${obj.name}」吗？此操作不可恢复');
    if (confirmed != true) return;
    await FileApi.deleteFiles([obj.path], skipSoftDelete: true);
    _load(showLoading: false, useCache: false);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(appSnack('已永久删除「${obj.name}」'));
  }

  /// 一键清空
  Future<void> _emptyTrash() async {
    if (_items.isEmpty) return;
    final confirmed = await _confirm('清空回收站',
        '确定永久删除回收站中的全部 ${_items.length} 项吗？此操作不可恢复');
    if (confirmed != true) return;
    await FileApi.deleteFiles(
        _items.map((e) => e.path).toList(),
        skipSoftDelete: true);
    _load(showLoading: false, useCache: false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(appSnack('已清空回收站'));
  }

  Future<bool?> _confirm(String title, String content) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
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
            padding: const EdgeInsets.symmetric(horizontal: pagePad),
            child: PageHeader(
              title: '回收站',
              secondary: true,
              leading: IconTile(
                icon: Icons.arrow_back_ios_new,
                filled: false,
                compact: true,
                onTap: () => Navigator.pop(context),
              ),
              actions: [
                GestureDetector(
                  onTap: _items.isEmpty ? null : _emptyTrash,
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Text(
                      '清空',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _items.isEmpty
                            ? AppColors.ink3
                            : AppColors.danger,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 第二行：列表头 + 排序（顶栏保持标题 + 清空，信息下沉）
          if (!_loading)
            Padding(
              padding: EdgeInsets.fromLTRB(pagePad, 0, pagePad, 6),
              child: SectionHeader(
                title: '全部文件',
                count: '${_items.length}',
                trailing: SortChip(
                  options: const [
                    SortOption('', '默认排序'),
                    SortOption('name', '按名称'),
                    SortOption('size', '按大小'),
                    SortOption('updated_at', '按删除时间'),
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
                    _load(showLoading: false);
                  },
                ),
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                    ? const EmptyState(
                        icon: Icons.delete_outline,
                        title: '回收站为空',
                        subtitle: '删除的文件会先进入这里，30 天后自动清除',
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: EdgeInsets.fromLTRB(pagePad, 6, pagePad,
                              MediaQuery.of(context).padding.bottom + 16),
                          itemCount: _items.length,
                          itemBuilder: (context, index) {
                            final obj = _items[index];
                            return FileRow(
                              type: obj.type,
                              name: obj.name,
                              meta: '${formatBytes(obj.size)} · ${_dateOf(obj)}',
                              leading: Opacity(
                                opacity: 0.55,
                                child: FileTile(
                                    type: obj.type, name: obj.name),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: Icon(Icons.restore,
                                        size: 20, color: AppColors.primary),
                                    onPressed: () => _restore(obj),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_forever,
                                        size: 20, color: AppColors.danger),
                                    onPressed: () => _deleteForever(obj),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  String _dateOf(FileItemModel obj) {
    final t = obj.updatedAt ?? obj.createdAt;
    if (t == null || t.isEmpty) return '';
    final dt = DateTime.tryParse(t);
    if (dt == null) return '';
    final local = dt.toLocal();
    return '${local.month.toString().padLeft(2, '0')}/${local.day.toString().padLeft(2, '0')}';
  }
}
