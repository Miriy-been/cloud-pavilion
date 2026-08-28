import 'package:cloudpavilion/util/DioUtil.dart';
import 'package:dio/dio.dart';

/// 服务器端后台任务 V4 API
class WorkflowApi {
  /// 列出当前用户的服务器端任务
  /// [category]: general（全部后台任务）/ downloading（进行中的离线下载）/ downloaded（完成的离线下载）
  /// 返回 data.tasks
  static Future<List<dynamic>> listTasks(
      {String category = 'general', int pageSize = 20}) async {
    var result = await DioUtil().request('/api/v4/workflow',
        method: DioMethod.get,
        params: {'category': category, 'page_size': pageSize});
    final data = result['data'];
    return data['tasks'] as List? ?? [];
  }

  /// 按 ID 查找后台任务（用于轮询任务状态，找不到返回 null）
  /// 压缩/解压等普通任务在 `general` 分类；离线下载（download 类型）任务在
  /// `downloading` / `downloaded` 分类，因此需要遍历这三个分类才能命中。
  static Future<Map<String, dynamic>?> findTaskById(String id) async {
    for (final category in const ['general', 'downloading', 'downloaded']) {
      final tasks = await listTasks(category: category, pageSize: 100);
      for (final t in tasks) {
        if (t is Map<String, dynamic> && t['id']?.toString() == id) return t;
      }
    }
    return null;
  }

  /// 创建压缩任务（src 文件/文件夹 URI → dst 压缩包 URI），返回任务对象
  static Future<Map<String, dynamic>> createArchive(
      List<String> srcUris, String dstUri) async {
    var result = await DioUtil().request('/api/v4/workflow/archive',
        method: DioMethod.post, data: {'src': srcUris, 'dst': dstUri});
    return result['data'];
  }

  /// 创建解压任务（压缩包 URI → dst 目标文件夹 URI），返回任务对象
  static Future<Map<String, dynamic>> extractArchive(
      String srcUri, String dstUri) async {
    var result = await DioUtil().request('/api/v4/workflow/extract',
        method: DioMethod.post,
        data: {'src': [srcUri], 'dst': dstUri});
    return result['data'];
  }

  /// 创建离线下载任务（服务器后台下载多个链接到目标目录）
  /// [srcUrls] 下载链接列表；[dstUri] 目标文件夹 URI（如 cloudreve://my/...）
  /// 返回创建的任务对象列表（data 为数组）
  static Future<List<dynamic>> createRemoteDownload(
      List<String> srcUrls, String dstUri) async {
    var result = await DioUtil().request('/api/v4/workflow/download',
        method: DioMethod.post, data: {'src': srcUrls, 'dst': dstUri});
    final data = result['data'];
    return data is List ? data : (data == null ? [] : [data]);
  }

  /// 列出离线下载任务
  /// [category]: downloading（进行中）/ downloaded（已完成/失败/已取消）
  /// 返回任务对象列表（TaskResponse）
  static Future<List<Map<String, dynamic>>> listRemoteDownloads(
      {required String category, int pageSize = 50}) async {
    var result = await DioUtil().request('/api/v4/workflow',
        method: DioMethod.get,
        params: {'category': category, 'page_size': pageSize});
    final data = result['data'];
    final tasks = data['tasks'];
    if (tasks is! List) return [];
    return tasks
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  /// 取消离线下载任务
  static Future<void> cancelRemoteDownload(String id) async {
    await DioUtil().request('/api/v4/workflow/download/$id',
        method: DioMethod.delete);
  }
}
