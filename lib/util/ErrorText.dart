import 'package:dio/dio.dart';

/// 将异常转为简短的中文错误文本，用于上传 / 下载失败时的即时提示
String errorText(Object e, String fallback) {
  if (e is DioException) {
    final resp = e.response;
    if (resp != null) {
      final body = resp.data;
      if (body is Map &&
          body['msg'] != null &&
          body['msg'].toString().isNotEmpty) {
        return body['msg'].toString();
      }
      return '请求失败 (${resp.statusCode})';
    }
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return '网络超时';
      case DioExceptionType.badCertificate:
        return '证书校验失败';
      case DioExceptionType.badResponse:
        return '服务器响应异常';
      case DioExceptionType.connectionError:
        return '网络连接失败';
      case DioExceptionType.cancel:
        return '已取消';
      case DioExceptionType.unknown:
        return '网络错误';
    }
  }
  if (e is FormatException) {
    final m = e.message.toString();
    return m.isEmpty ? fallback : m;
  }
  final s = e.toString().replaceFirst('Exception: ', '');
  return s.isEmpty ? fallback : s;
}
