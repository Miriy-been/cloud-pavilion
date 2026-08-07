import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:cloudpavilion/exception/DebugReportException.dart';
import 'package:cloudpavilion/util/DioUtil.dart';
import 'package:cloudpavilion/util/SpUtils.dart';
import 'package:cloudpavilion/util/TimeFlowDecoder.dart';

/// 文件相关 V4 API（URI 定位）
class FileApi {
  /// 用户文件根目录 URI
  static const String myRootUri = 'cloudreve://my';

  // ---------- 内存缓存（切页秒开，数据变更时失效） ----------

  /// 文件列表缓存（目录+排序 维度，短 TTL）
  static const Duration _listTtl = Duration(seconds: 60);
  static final Map<String, _ListCacheEntry> _listCache = {};

  /// 文件信息缓存（music:* 等元数据，避免播放切歌反复请求）
  static const Duration _infoTtl = Duration(minutes: 10);
  static final Map<String, _InfoCacheEntry> _infoCache = {};

  /// 使指定目录（或全部）的列表缓存失效（上传/删除/移动/重命名后调用）
  static void invalidateListCache({String? uri}) {
    if (uri == null) {
      _listCache.clear();
      return;
    }
    _listCache.removeWhere((key, _) => key.startsWith('$uri|'));
  }

  /// 账号切换 / 重新登录时清空全部缓存，避免跨账号数据串用
  static void clearAllCache() {
    _listCache.clear();
    _infoCache.clear();
    // 直链 URL 缓存随账号一并清空，防止跨账号复用
    _urlCache.clear();
    _urlCacheExpiryAt.clear();
    _urlCacheLoaded = false;
    // 重置落盘链，避免 pending 写把旧账号直链缓存写回
    _urlCacheWriteChain = Future.value();
    SpUtils.remove(_urlCachePrefKey);
  }

  // ---------- 下载直链缓存（持久化：有效期内复用同一 URL） ----------
  //
  // Cloudreve 直链带有效期（默认 1 小时），每次请求都会签发新 URL；
  // just_audio 的整曲缓存 key = sha256(URL)，URL 一旦变化缓存即失效、整曲重下。
  // 这里把 URL 持久化到本地，有效期内复用同一 URL，保证缓存 key 稳定。

  static const String _urlCachePrefKey = 'download_url_cache_v1';
  static final Map<String, String> _urlCache = {};
  static final Map<String, int> _urlCacheExpiryAt = {};
  static bool _urlCacheLoaded = false;
  /// 落盘串行链，避免并发写同一 key 互相覆盖
  static Future<void> _urlCacheWriteChain = Future.value();

  /// 站点前缀：不同服务器不共享直链缓存
  static Future<String> _sitePrefix() async {
    final base = await SpUtils.getString('CurrentBaseUrl');
    return base.isEmpty ? 'default' : base;
  }

  static Future<void> _loadUrlCache() async {
    if (_urlCacheLoaded) return;
    _urlCacheLoaded = true;
    try {
      final raw = await SpUtils.getString(_urlCachePrefKey);
      if (raw.isEmpty) return;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final now = DateTime.now().millisecondsSinceEpoch;
      map.forEach((key, v) {
        final e = v as Map<String, dynamic>;
        final exp = (e['expiresAt'] as num?)?.toInt() ?? 0;
        if (exp > now) {
          _urlCache[key] = e['url'] as String;
          _urlCacheExpiryAt[key] = exp;
        }
      });
    } catch (_) {}
  }

  /// 写入一条直链缓存并异步落盘（失败不影响主流程）
  static void _saveUrlCache(String key, String url, int expiresAtMs) {
    _urlCache[key] = url;
    _urlCacheExpiryAt[key] = expiresAtMs;
    _urlCacheWriteChain = _urlCacheWriteChain.then((_) async {
      try {
        final now = DateTime.now().millisecondsSinceEpoch;
        final map = <String, dynamic>{};
        _urlCache.forEach((k, u) {
          final exp = _urlCacheExpiryAt[k];
          if (exp != null && exp > now) {
            map[k] = {'url': u, 'expiresAt': exp};
          }
        });
        await SpUtils.setString(_urlCachePrefKey, jsonEncode(map));
      } catch (_) {}
    });
  }

  /// 获取单个文件信息（含 metadata，如 music:title / music:artist 等）
  /// [extended] 为 true 时请求扩展信息（所有者 / 共享状态 / 存储实体等），用于详情展示
  static Future<Map<String, dynamic>> getFileInfo(String uri,
      {bool extended = false}) async {
    final key = '$uri|extended:$extended';
    final cached = _infoCache[key];
    if (cached != null && !cached.isExpired) return cached.data;
    var result = await DioUtil().request('/api/v4/file/info',
        method: DioMethod.get,
        params: {'uri': uri, if (extended) 'extended': 'true'});
    final data = result['data'];
    final map = data is Map
        ? Map<String, dynamic>.from(data)
        : <String, dynamic>{};
    _infoCache[key] = _InfoCacheEntry(map, DateTime.now());
    return map;
  }

  /// 文件列表
  /// 返回响应中的 data（含 files/parent/pagination）
  /// [orderBy]: name/size/updated_at/created_at
  /// [useCache] 为 false 时强制刷新（下拉刷新场景），成功后同样写入缓存
  static Future<Map<String, dynamic>> listFiles(String uri,
      {int page = 1,
      int pageSize = 100,
      String? orderBy,
      String? orderDirection,
      bool useCache = true}) async {
    final key = '$uri|$page|$pageSize|$orderBy|$orderDirection';
    if (useCache) {
      final cached = _listCache[key];
      if (cached != null && !cached.isExpired) return cached.data;
    }
    var result = await DioUtil().request('/api/v4/file',
        method: DioMethod.get,
        params: {
          'uri': uri,
          'page': page,
          'page_size': pageSize,
          if (orderBy != null && orderBy.isNotEmpty) 'order_by': orderBy,
          if (orderDirection != null && orderDirection.isNotEmpty)
            'order_direction': orderDirection,
        });
    final data = result['data'];
    final map = data is Map
        ? Map<String, dynamic>.from(data)
        : <String, dynamic>{};
    _listCache[key] = _ListCacheEntry(map, DateTime.now());
    return map;
  }

  /// 新建文件/文件夹（type: 'file' | 'folder'）
  static Future<void> createFile(String uri, String type,
      {bool errOnConflict = false}) async {
    await DioUtil().request('/api/v4/file/create',
        method: DioMethod.post,
        data: {'uri': uri, 'type': type, 'err_on_conflict': errOnConflict});
    invalidateListCache();
  }

  /// 新建文件夹
  static Future<void> createFolder(String parentUri, String name) async {
    final uri =
        parentUri.endsWith('/') ? '$parentUri$name' : '$parentUri/$name';
    await createFile(uri, 'folder');
  }

  /// 重命名
  static Future<void> renameFile(String uri, String newName) async {
    await DioUtil().request('/api/v4/file/rename',
        method: DioMethod.post, data: {'uri': uri, 'new_name': newName});
    invalidateListCache();
  }

  /// 删除（默认进回收站；skipSoftDelete=true 为彻底删除）
  static Future<void> deleteFiles(List<String> uris,
      {bool skipSoftDelete = false}) async {
    await DioUtil().request('/api/v4/file',
        method: DioMethod.delete,
        data: {'uris': uris, 'skip_soft_delete': skipSoftDelete});
    invalidateListCache();
  }

  /// 移动 / 复制文件到目标文件夹
  /// [copy] 为 true 时复制，false 时移动
  static Future<void> moveOrCopyFiles(List<String> uris, String dst,
      {bool copy = false}) async {
    await DioUtil().request('/api/v4/file/move',
        method: DioMethod.post,
        data: {'uris': uris, 'dst': dst, 'copy': copy});
    invalidateListCache();
  }

  /// 获取图片缩略图 URL
  /// 自动处理混淆 URL 解码与相对路径补全；非图片或失败时返回 null。
  /// 缩略图直链带有效期（默认 1 小时）：持久化复用同一 URL，
  /// 保证 CachedImage 缓存 key（url）稳定，避免每次浏览列表重复下载缩略图。
  static Future<String?> getThumbnailUrl(String uri) async {
    await _loadUrlCache();
    final key = '${await _sitePrefix()}|thumb|$uri';
    final cached = _urlCache[key];
    if (cached != null) return cached;

    var result = await DioUtil().request('/api/v4/file/thumb',
        method: DioMethod.get, params: {'uri': uri});
    final data = result['data'];
    if (data == null) return null;
    var url = data['url']?.toString() ?? '';
    if (url.isEmpty) return null;
    if (data['obfuscated'] == true) {
      final decoded = TimeFlowDecoder.decode(url);
      if (decoded == null || decoded.isEmpty) return null;
      url = decoded;
    }
    if (url.startsWith('/')) {
      final base = await SpUtils.getString('CurrentBaseUrl');
      url = '$base$url';
    }

    // 与下载直链同机制：有效期取接口 expires，缺省按 1 小时，预留安全余量
    DateTime? expires;
    final rawExpires = data['expires'];
    if (rawExpires is String && rawExpires.isNotEmpty) {
      expires = DateTime.tryParse(rawExpires);
    }
    final now = DateTime.now();
    final ttlMs = expires == null
        ? const Duration(hours: 1).inMilliseconds
        : expires.difference(now).inMilliseconds;
    final marginMs = (ttlMs * 0.1).clamp(10000, 60000).toInt();
    _saveUrlCache(key, url, now.millisecondsSinceEpoch + ttlMs - marginMs);
    return url;
  }

  /// 回收站根 URI
  static const String trashUri = 'cloudreve://trash';

  /// 从回收站恢复文件
  static Future<void> restoreFiles(List<String> uris) async {
    await DioUtil().request('/api/v4/file/restore',
        method: DioMethod.post, data: {'uris': uris});
    invalidateListCache();
  }

  /// 获取下载/预览临时直链（无需认证头即可访问）
  /// [download] 为 true 时浏览器会下载而不是直接预览
  static Future<String> getDownloadUrl(String uri,
      {bool download = true}) async {
    // 直链带有效期（默认 1 小时）：有效期内复用同一 URL，保证
    // just_audio 缓存 key（sha256(url)）稳定，避免 app 重启 / 直链过期后整曲重下
    await _loadUrlCache();
    final key = '${await _sitePrefix()}|$uri|$download';
    final cached = _urlCache[key];
    if (cached != null) return cached;

    var result = await DioUtil().request('/api/v4/file/url',
        method: DioMethod.post, data: {'uris': [uri], 'download': download});
    final urls = result['data']['urls'] as List;
    final url = urls.first['url'] as String;

    // 过期时间：优先取接口返回的 expires（RFC3339），缺失时按默认 1 小时兜底；
    // 预留安全余量（TTL 的 10%，10s~60s），避免在直链失效边缘复用旧 URL
    DateTime? expires;
    final rawExpires = (result['data'] as Map?)?['expires'];
    if (rawExpires is String && rawExpires.isNotEmpty) {
      expires = DateTime.tryParse(rawExpires);
    }
    final now = DateTime.now();
    final ttlMs = expires == null
        ? const Duration(hours: 1).inMilliseconds
        : expires.difference(now).inMilliseconds;
    final marginMs = (ttlMs * 0.1).clamp(10000, 60000).toInt();
    _saveUrlCache(key, url, now.millisecondsSinceEpoch + ttlMs - marginMs);
    return url;
  }

  /// 创建上传会话
  /// 返回 data（含 session_id / chunk_size / expires）
  /// [mimeType]/[lastModified] 为空时不传，由服务器自动推断
  static Future<Map<String, dynamic>> createUploadSession(String uri, int size,
      {String? mimeType, int? lastModified}) async {
    final result = await DioUtil().request('/api/v4/file/upload',
        method: DioMethod.put,
        data: {
          'uri': uri,
          'size': size,
          if (mimeType != null && mimeType.isNotEmpty) 'mime_type': mimeType,
          if (lastModified != null) 'last_modified': lastModified,
        });
    final data = result['data'];
    if (data == null) {
      // 服务器拒绝了上传会话创建，透出具体原因
      throw DebugReportException(
          result['msg']?.toString() ?? '创建上传会话失败');
    }
    return data;
  }

  /// 上传分片（octet-stream，dio 自动设置 Content-Length）
  static Future<void> uploadChunk(
    String sessionId,
    int index,
    Uint8List bytes, {
    ProgressCallback? onSendProgress,
    CancelToken? cancelToken,
  }) async {
    await DioUtil().request('/api/v4/file/upload/$sessionId/$index',
        method: DioMethod.post,
        data: bytes,
        cancelToken: cancelToken,
        onSendProgress: onSendProgress,
        options: Options(
          contentType: 'application/octet-stream',
        ));
  }

  /// 写入文件内容（文件不存在时自动创建；用于新建文件 / 编辑文本）
  static Future<void> updateFileContent(String uri, String content) async {
    await DioUtil().request('/api/v4/file/content',
        method: DioMethod.put,
        params: {'uri': uri},
        data: Uint8List.fromList(utf8.encode(content)),
        options: Options(contentType: 'application/octet-stream'));
    invalidateListCache();
  }
}

/// 文件列表缓存条目
class _ListCacheEntry {
  final Map<String, dynamic> data;
  final DateTime at;
  bool get isExpired =>
      DateTime.now().difference(at) > FileApi._listTtl;

  _ListCacheEntry(this.data, this.at);
}

/// 文件信息缓存条目
class _InfoCacheEntry {
  final Map<String, dynamic> data;
  final DateTime at;
  bool get isExpired =>
      DateTime.now().difference(at) > FileApi._infoTtl;

  _InfoCacheEntry(this.data, this.at);
}
