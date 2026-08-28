/// 离线下载任务模型（服务器端 remote_download 任务）
///
/// 数据来自 /api/v4/workflow 列表与创建接口返回的 TaskResponse：
/// ```
/// { id, status, type, summary: {
///     phase: monitor|transfer|seeding,
///     props: {
///       src_str: 下载链接, src: 种子文件 URI, dst: 目标目录,
///       download: { name, state, total, downloaded, download_speed, error_message }
///     }
/// } }
/// ```
class RemoteDownloadTaskModel {
  final String id;
  final String status; // queued / processing / suspending / error / canceled / completed
  final String type;
  final String? error;
  final String? phase; // monitor（下载中）/ transfer（传输中）/ seeding（做种中）
  final String? srcStr; // 下载链接（src_str）
  final String? srcFile; // 种子文件 URI（src）
  final String? dst; // 目标目录
  final String? name; // 下载任务名（download.name）
  final int total;
  final int downloaded;
  final int downloadSpeed;
  final String? errorMessage;

  const RemoteDownloadTaskModel({
    required this.id,
    required this.status,
    required this.type,
    this.error,
    this.phase,
    this.srcStr,
    this.srcFile,
    this.dst,
    this.name,
    this.total = 0,
    this.downloaded = 0,
    this.downloadSpeed = 0,
    this.errorMessage,
  });

  factory RemoteDownloadTaskModel.fromJson(Map<String, dynamic> json) {
    final summary = json['summary'];
    final s = summary is Map ? summary : const <String, dynamic>{};
    final props = s['props'];
    final p = props is Map ? props : const <String, dynamic>{};
    final download = p['download'];
    final dl = download is Map ? download : const <String, dynamic>{};
    return RemoteDownloadTaskModel(
      id: json['id']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      error: json['error']?.toString(),
      phase: s['phase']?.toString(),
      srcStr: p['src_str']?.toString(),
      srcFile: p['src']?.toString(),
      dst: p['dst']?.toString(),
      name: dl['name']?.toString(),
      total: _intOf(dl['total']),
      downloaded: _intOf(dl['downloaded']),
      downloadSpeed: _intOf(dl['download_speed']),
      errorMessage: dl['error_message']?.toString(),
    );
  }

  /// 是否进行中（排队 / 处理 / 挂起）
  bool get isActive =>
      const {'queued', 'processing', 'suspending'}.contains(status);

  /// 下载进度 0~1（未知总大小时为 0）
  double get progress =>
      total <= 0 ? 0 : (downloaded / total).clamp(0.0, 1.0);

  /// 展示名：优先下载任务名，其次链接最后一段，其次目标目录
  String get displayName {
    if (name != null && name!.isNotEmpty) return name!;
    final raw = srcStr ?? srcFile ?? '';
    if (raw.isNotEmpty) {
      final idx = raw.lastIndexOf('/');
      final seg = Uri.decodeComponent(idx < 0 ? raw : raw.substring(idx + 1));
      if (seg.isNotEmpty && seg != raw) return seg;
    }
    return '离线下载任务';
  }

  /// 状态文案
  String get statusText {
    switch (status) {
      case 'queued':
        return '排队中';
      case 'processing':
      case 'suspending':
        switch (phase) {
          case 'monitor':
            return '下载中';
          case 'transfer':
            return '传输中';
          case 'seeding':
            return '做种中';
          default:
            return '处理中';
        }
      case 'completed':
        return '已完成';
      case 'error':
        return '失败';
      case 'canceled':
        return '已取消';
      default:
        return '未知状态';
    }
  }

  /// 失败原因（优先 download.error_message，其次任务级 error）
  String get failReason {
    final m = (errorMessage ?? '').isNotEmpty
        ? errorMessage!
        : (error ?? '');
    return m.isEmpty ? '未知错误' : m;
  }

  static int _intOf(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return 0;
  }
}
