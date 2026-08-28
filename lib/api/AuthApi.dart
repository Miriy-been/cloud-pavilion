import 'package:cloudpavilion/util/DioUtil.dart';

class AuthApi {
  // 获取站点配置（V4）
  static getConfig() async {
    var result = await DioUtil()
        .request('/api/v4/site/config/basic', method: DioMethod.get);
    return result;
  }

  // 登录（V4 JWT，返回 data.user + data.token）
  // checkCode:false——登录失败需读原始 code/msg（2FA=203、密码错误等）展示给用户
  static login(String email, String password) async {
    var result = await DioUtil().request('/api/v4/session/token',
        method: DioMethod.post,
        data: {'email': email, 'password': password},
        checkCode: false);
    return result;
  }

  // 刷新 token
  static refreshToken(String refreshToken) async {
    var result = await DioUtil().request('/api/v4/session/token/refresh',
        method: DioMethod.post, data: {'refresh_token': refreshToken});
    return result;
  }
}
