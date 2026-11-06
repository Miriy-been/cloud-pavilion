import 'FileItemModel.dart';

/// 一页文件列表 + 下一页游标
///
/// Cloudreve V4 默认开启游标分页（`use_cursor_pagination=1`），此时 `page`
/// 参数被服务端忽略，翻页唯一可靠的方式是把上一页返回的
/// `pagination.next_token` 原样回传。关闭游标分页的站点则回退为
/// `pagination.total_items` + 已加载数量判断。
///
/// 供各列表页（存储 / 分类 / 搜索 / 回收站）共用，避免每个页面重复解析
/// `files` 与 `pagination` 字段。
class FileListPage {
  /// 本页条目
  final List<FileItemModel> items;

  /// 下一页游标；空串表示已到末页
  final String nextToken;

  /// 服务端返回的总条数（游标分页下通常缺省为 0）
  final int totalItems;

  /// 累计已加载条数（含本页，回退判断用）
  final int loaded;

  const FileListPage({
    required this.items,
    this.nextToken = '',
    this.totalItems = 0,
    this.loaded = 0,
  });

  /// 是否还有下一页
  bool get hasMore =>
      nextToken.isNotEmpty || (totalItems > 0 && loaded < totalItems);

  static const FileListPage empty = FileListPage(items: []);

  /// 解析接口返回的 `data`（含 files / pagination）
  ///
  /// [loadedBefore] 为本次加载前已累计的条数，用于 offset 分页回退判断。
  factory FileListPage.fromData(Map<String, dynamic> data,
      {int loadedBefore = 0}) {
    final files = data['files'];
    final items = files is List
        ? files
            .whereType<Map<String, dynamic>>()
            .map(FileItemModel.fromJson)
            .toList()
        : <FileItemModel>[];

    var nextToken = '';
    var totalItems = 0;
    final pagination = data['pagination'];
    if (pagination is Map) {
      nextToken = pagination['next_token']?.toString() ?? '';
      totalItems = (pagination['total_items'] as num?)?.toInt() ?? 0;
    }
    return FileListPage(
      items: items,
      nextToken: nextToken,
      totalItems: totalItems,
      loaded: loadedBefore + items.length,
    );
  }
}
