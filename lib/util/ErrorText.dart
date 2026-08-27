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
        return _localizeServerMsg(body['msg'].toString());
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
    return m.isEmpty ? fallback : _localizeServerMsg(m);
  }
  // 去除 DebugReportException / NotLoginException / 其它异常的前缀，展示为中文
  final msg = _localizeServerMsg(e
      .toString()
      .replaceFirst('MyException: ', '')
      .replaceFirst('Exception: ', '')
      .replaceFirst('DioException: ', ''));
  return msg.isEmpty ? fallback : msg;
}

/// 将服务端返回的英文 / 原始错误映射为明确的中文提示。
/// 已支持中文的提示（如「同名对象已存在」）原样保留，避免画蛇添足。
String _localizeServerMsg(String m) {
  if (m.contains('同名')) return m; // 已是清晰中文
  final lower = m.toLowerCase();
  // 覆盖 Cloudreve 的常见英文措辞（如 "Object existed" / "already exist" /
  // "file with the same name ..."），统一转成简洁中文
  if (lower.contains('same name') ||
      lower.contains('object existed') ||
      lower.contains('object exists') ||
      lower.contains('file existed') ||
      lower.contains('file exists') ||
      lower.contains('name existed') ||
      lower.contains('already exist') ||
      lower.contains('duplicate')) {
    return '目标位置已存在同名文件';
  }
  return m;
}