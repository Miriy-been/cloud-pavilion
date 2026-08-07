/// 后台上传任务状态
enum UploadStatus { uploading, finished, failed, cancelled }

/// 后台上传任务模型
class UploadTaskModel {
  final String name;
  final String uri; // 目标云端 URI
  final String sourcePath; // 本地源文件路径
  final int size;
  double progress = 0;
  UploadStatus status = UploadStatus.uploading;
  String? error;

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
        'status': status.name,
        'error': error,
      };

  /// 从本地持久化数据恢复
  factory UploadTaskModel.fromJson(Map<String, dynamic> json) =>
      UploadTaskModel(
        name: json['name'] as String? ?? '',
        uri: json['uri'] as String? ?? '',
        sourcePath: json['sourcePath'] as String? ?? '',
        size: json['size'] as int? ?? 0,
      )..progress = (json['progress'] as num?)?.toDouble() ?? 0
        ..status = UploadStatus.values.asNameMap()[json['status'] as String?] ??
            UploadStatus.failed
        ..error = json['error'] as String?;
}
