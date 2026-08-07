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
  static Future<Map<String, dynamic>?> findTaskById(String id) async {
    final tasks = await listTasks(category: 'general', pageSize: 100);
    for (final t in tasks) {
      if (t is Map<String, dynamic> && t['id'] == id) return t;
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
}
