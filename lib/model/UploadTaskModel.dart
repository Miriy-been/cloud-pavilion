/// 后台上传任务状态
///
/// [paused] 表示用户主动暂停：会话与已传分片保留，可随时从断点继续。
enum UploadStatus { uploading, finished, failed, paused }

/// 后台上传任务模型
class UploadTaskModel {
  final String name;
  final String uri; // 目标云端 URI
  final String sourcePath; // 本地源文件路径
  final int size;
  double progress = 0;

  /// 已上传字节数（实时进度展示用）
  int uploaded = 0;

  /// 当前上传速度（字节/秒，实时进度展示用）
  double speed = 0;
  UploadStatus status = UploadStatus.uploading;
  String? error;

  // ---------- 断点续传上下文 ----------
  //
  // 思路与官方 Web 端一致（Uploader/core/utils/helper.ts）：进度由**客户端**
  // 记录，不依赖服务端查询。服务端仅保存会话本身（含 ChunksReceived），
  // 分片上传是幂等的，重复提交同一 index 不会出错。

  /// 上传会话 ID（可续传的关键；会话过期后置空）
  String? sessionId;

  /// 会话过期时间（服务端返回的 expires，毫秒时间戳）
  int? sessionExpiresAt;

  /// 已成功上传的分片序号（续传时跳过这些分片）
  List<int> uploadedChunks = [];

  /// 创建会话时服务端下发的分片大小（续传必须与建会话时一致）
  int chunkSize = 0;

  /// 当前正在上传的分片内已发送字节数。
  ///
  /// 服务端按「整片」校验 Content-Length（`processChunkUpload`），片内无法
  /// 真正从中间续传，所以该字段**只用于恢复进度显示**：中断后重试时，
  /// 进度从「已完成分片总字节 + 本片已发字节」继续，而不是跳回 0%。
  int currentChunkSent = 0;

  /// 当前会话是否仍然有效（未过期才能续传）
  bool get canResume {
    if (sessionId == null || sessionId!.isEmpty) return false;
    final exp = sessionExpiresAt;
    if (exp == null || exp <= 0) return false;
    // 预留 30 秒余量，避免在过期边缘发起续传
    return exp - DateTime.now().millisecondsSinceEpoch > 30 * 1000;
  }

  /// 已完成分片累计的字节数（不含正在传的片）
  int get completedChunksBytes {
    if (chunkSize <= 0) return 0;
    var bytes = 0;
    for (final i in uploadedChunks) {
      final offset = i * chunkSize;
      final len = (offset + chunkSize > size) ? (size - offset) : chunkSize;
      if (len > 0) bytes += len;
    }
    return bytes;
  }

  /// 续传起点（字节）：已完成分片 + 当前片已发部分。
  /// 用于界面展示「已传多少」，不代表服务端实际已接收这么多。
  int get resumeDisplayedBytes =>
      (completedChunksBytes + currentChunkSent).clamp(0, size);

  /// 界面上「已传」应展示的字节数。
  ///
  /// 有分片记账时以分片累计为准（含片内进度）；无会话时（如刚创建、
  /// 或不分片的大文件传输中）回落到实时上报的 [uploaded]。
  int get transferredBytes {
    final byChunks = resumeDisplayedBytes;
    return byChunks > 0 ? byChunks : uploaded;
  }

  /// 清除续传上下文（会话失效 / 用户取消时调用）
  void clearResumeContext() {
    sessionId = null;
    sessionExpiresAt = null;
    uploadedChunks = [];
    chunkSize = 0;
    currentChunkSent = 0;
  }

  UploadTaskModel({
    required this.name,
    required this.uri,
    required this.sourcePath,
    required this.size,
  });

  /// 序列化为本地持久化数据
  Map<String, dynamic> toJson() => {
        'name': name,
        'uri': uri,
        'sourcePath': sourcePath,
        'size': size,
        'progress': progress,
        'uploaded': uploaded,
        'status': status.name,
        'error': error,
        'sessionId': sessionId,
        'sessionExpiresAt': sessionExpiresAt,
        'uploadedChunks': uploadedChunks,
        'chunkSize': chunkSize,
        'currentChunkSent': currentChunkSent,
      };

  /// 从本地持久化数据恢复
  factory UploadTaskModel.fromJson(Map<String, dynamic> json) =>
      UploadTaskModel(
        name: json['name'] as String? ?? '',
        uri: json['uri'] as String? ?? '',
        sourcePath: json['sourcePath'] as String? ?? '',
        size: json['size'] as int? ?? 0,
      )..progress = (json['progress'] as num?)?.toDouble() ?? 0
        ..uploaded = (json['uploaded'] as num?)?.toInt() ?? 0
        ..status = UploadStatus.values.asNameMap()[json['status'] as String?] ??
            UploadStatus.failed
        ..error = json['error'] as String?
        ..sessionId = json['sessionId'] as String?
        ..sessionExpiresAt = (json['sessionExpiresAt'] as num?)?.toInt()
        ..uploadedChunks =
            (json['uploadedChunks'] as List?)?.whereType<int>().toList() ?? []
        ..chunkSize = (json['chunkSize'] as num?)?.toInt() ?? 0
        ..currentChunkSent = (json['currentChunkSent'] as num?)?.toInt() ?? 0;
}
