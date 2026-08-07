import 'package:flutter_application_2/util/DioUtil.dart';
import 'package:dio/dio.dart';

/// 用户相关 V4 API
class UserApi {
  /// 存储容量（返回 data: {total, used}，单位字节）
  static Future<Map<String, dynamic>> getCapacity() async {
    var result = await DioUtil()
        .request('/api/v4/user/capacity', method: DioMethod.get);
    return result['data'];
  }
}
