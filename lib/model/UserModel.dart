/// 用户模型（登录响应 data.user）
class UserModel {
  final String id;
  final String email;
  final String nickname;
  final String groupId;
  final String groupName;

  const UserModel({
    required this.id,
    required this.email,
    required this.nickname,
    required this.groupId,
    required this.groupName,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    final group = json['group'] is Map ? json['group'] as Map : null;
    return UserModel(
      id: json['id'] ?? '',
      email: json['email'] ?? '',
      nickname: json['nickname'] ?? '',
      groupId: group?['id']?.toString() ?? '',
      groupName: group?['name']?.toString() ?? '',
    );
  }

  /// 头像图片 URL（V4：GET /api/v4/user/avatar/{id} 返回原始图片）
  String avatarUrl(String siteUrl) => '$siteUrl/api/v4/user/avatar/$id';
}
