import 'package:flutter_application_2/util/DioUtil.dart';

/// 账号安全相关 API（重设密码），对齐 Cloudreve V4 后端
class SecurityApi {
  /// 重设密码（需输入当前密码）
  static Future<void> changePassword(
      String currentPassword, String newPassword) async {
    await DioUtil().request('/api/v4/user/setting',
        method: DioMethod.patch,
        data: {
          'current_password': currentPassword,
          'new_password': newPassword,
        });
  }
}
