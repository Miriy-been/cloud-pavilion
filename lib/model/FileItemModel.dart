/// V4 文件对象模型
/// type: 0=文件, 1=文件夹；path 为完整 URI（cloudreve://my/...）
class FileItemModel {
  final int type;
  final String id;
  final String name;
  final int size;
  final String path;
  final String? createdAt;
  final String? updatedAt;
  /// 文件元数据（music:title / music:artist / stream:* 等）
  final Map<String, String>? metadata;

  bool get isDir => type == 1;

  const FileItemModel({
    required this.type,
    required this.id,
    required this.name,
    required this.size,
    required this.path,
    this.createdAt,
    this.updatedAt,
    this.metadata,
  });

  factory FileItemModel.fromJson(Map<String, dynamic> json) {
    final raw = json['metadata'];
    return FileItemModel(
      type: json['type'] ?? 0,
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      size: json['size'] ?? 0,
      path: json['path'] ?? '',
      createdAt: json['created_at'],
      updatedAt: json['updated_at'],
      metadata: raw is Map
          ? raw.map((k, v) => MapEntry(k.toString(), v.toString()))
          : null,
    );
  }
}
