import 'package:cloudpavilion/util/DioUtil.dart';

/// 分享相关 V4 API
class ShareApi {
  /// 校验响应业务码，非 0 时抛出带服务端提示的异常
  static dynamic _checkData(dynamic result) {
    if (result is Map && result['code'] != 0) {
      throw Exception(result['msg']?.toString() ?? '请求失败');
    }
    return result['data'];
  }

  /// 创建分享链接
  /// 返回分享链接 url（可能为相对路径 /s/xxx，或服务端直接返回完整链接），
  /// 调用方需用 _buildShareUrl 拼接站点地址
  static Future<String> createShare(String uri,
      {bool isPrivate = false,
      int? expireSeconds,
      String? password,
      int? remainDownloads}) async {
    var result = await DioUtil().request('/api/v4/share',
        method: DioMethod.put,
        data: {
          'uri': uri,
          'is_private': isPrivate,
          'password': password,
          // 后端字段名为 downloads（下载后自动过期），0 表示不限次数
          'downloads': remainDownloads ?? 0,
          // expire 单位为秒，0 表示永久有效
          'expire': expireSeconds ?? 0,
          'permissions': {
            'anonymous': 'AQ==',
            'everyone': 'AQ==',
          },
        });
    final data = _checkData(result);
    // 兼容服务端返回 Map（含 url 字段）或字符串两种形态
    return data is Map ? (data['url']?.toString() ?? '') : data.toString();
  }

  /// 获取分享详情（owner_extended 后返回 source_uri 等私有字段）
  /// 私有分享需携带 password，否则后端解析分享 URI 时密码校验失败
  static Future<Map<String, dynamic>> getShareInfo(String shareId,
      {String? password}) async {
    var result = await DioUtil().request('/api/v4/share/info/$shareId',
        method: DioMethod.get,
        params: {
          'owner_extended': true,
          if (password != null && password.isNotEmpty) 'password': password,
        });
    final data = _checkData(result);
    return data is Map ? Map<String, dynamic>.from(data) : {};
  }

  /// 编辑分享链接（修改有效期 / 下载次数）
  /// uri 为分享源文件 URI，需通过 getShareInfo 获取
  /// 注：V4 后端编辑接口仅更新有效期与下载次数，不支持修改访问密码
  static Future<String> updateShare(String shareId,
      {required String uri, int? expireSeconds, int? remainDownloads}) async {
    var result = await DioUtil().request('/api/v4/share/$shareId',
        method: DioMethod.post,
        data: {
          'uri': uri,
          'downloads': remainDownloads ?? 0,
          'expire': expireSeconds ?? 0,
        });
    final data = _checkData(result);
    return data is Map ? (data['url']?.toString() ?? '') : data.toString();
  }

  /// 拼接完整分享链接（兼容服务端返回相对路径或完整链接两种形态）
  static String buildFullUrl(String siteUrl, dynamic url) {
    var p = url is Map ? (url['url']?.toString() ?? '') : url.toString();
    if (p.startsWith('http://') || p.startsWith('https://')) return p;
    if (p.isEmpty) return siteUrl;
    return p.startsWith('/') ? '$siteUrl$p' : '$siteUrl/$p';
  }

  /// 我的分享列表（返回 data.shares）
  /// orderBy 支持：id（创建时间）/ views（访问量）等；orderDirection：asc / desc
  static Future<List<dynamic>> listMyShares(
      {int pageSize = 50, String? orderBy, String? orderDirection}) async {
    var result = await DioUtil().request('/api/v4/share',
        method: DioMethod.get,
        params: {
          'page_size': pageSize,
          if (orderBy != null && orderBy.isNotEmpty) 'order_by': orderBy,
          if (orderDirection != null && orderDirection.isNotEmpty)
            'order_direction': orderDirection,
        });
    final data = result['data'];
    return data['shares'] as List? ?? [];
  }

  /// 删除分享链接
  static Future<void> deleteShare(String shareId) async {
    await DioUtil().request('/api/v4/share/$shareId',
        method: DioMethod.delete);
  }
}
