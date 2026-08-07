/// 下载任务状态
enum DownloadStatus { downloading, finished, failed, cancelled }

/// 本地下载任务
class DownloadTaskModel {
  final String name;

  /// 文件保存路径（系统下载目录任务完成转入后会被更新）
  String savePath;

  /// 下载源地址（签名临时直链），用于失败后重试
  final String sourceUrl;

  /// 是否保存至系统下载目录（决定重试方式与保存位置展示）
  final bool systemDownloads;
  int totalSize;
  double progress; // 0 ~ 1
  DownloadStatus status;
  String? error;

  DownloadTaskModel({
    required this.name,
    required this.savePath,
    this.sourceUrl = '',
    this.systemDownloads = false,
    this.totalSize = 0,
    this.progress = 0,
    this.status = DownloadStatus.downloading,
    this.error,
  });

  /// 序列化为本地持久化数据
  Map<String, dynamic> toJson() => {
        'name': name,
        'savePath': savePath,
        'sourceUrl': sourceUrl,
        'systemDownloads': systemDownloads,
        'totalSize': totalSize,
        'progress': progress,
        'status': status.name,
        'error': error,
      };

  /// 从本地持久化数据恢复
  factory DownloadTaskModel.fromJson(Map<String, dynamic> json) =>
      DownloadTaskModel(
        name: json['name'] as String? ?? '',
        savePath: json['savePath'] as String? ?? '',
        sourceUrl: json['sourceUrl'] as String? ?? '',
        systemDownloads: json['systemDownloads'] as bool? ?? false,
        totalSize: json['totalSize'] as int? ?? 0,
        progress: (json['progress'] as num?)?.toDouble() ?? 0,
        status: DownloadStatus.values.asNameMap()[json['status'] as String?] ??
            DownloadStatus.failed,
        error: json['error'] as String?,
      );
}
