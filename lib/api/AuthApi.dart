import 'package:flutter_application_2/util/DioUtil.dart';
import 'package:dio/dio.dart';

class AuthApi {
  // 获取站点配置（V4）
  static getConfig() async {
    var result = await DioUtil()
        .request('/api/v4/site/config/basic', method: DioMethod.get);
    return result;
  }

  // 登录（V4 JWT，返回 data.user + data.token）
  static login(String email, String password) async {
    var result = await DioUtil().request('/api/v4/session/token',
        method: DioMethod.post, data: {'email': email, 'password': password});
    return result;
  }

  // 刷新 token
  static refreshToken(String refreshToken) async {
    var result = await DioUtil().request('/api/v4/session/token/refresh',
        method: DioMethod.post, data: {'refresh_token': refreshToken});
    return result;
  }
}
