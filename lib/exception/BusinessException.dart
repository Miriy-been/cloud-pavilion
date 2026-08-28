/// 响应业务码非 0 的统一异常（`DioUtil.request` 校验业务码时抛出）。
/// 携带服务端 code / msg / data，便于调用方按业务码分支处理（如锁冲突 40073）。
class BusinessException implements Exception {
  final int code;
  final String? message;
  final dynamic data;
  BusinessException(this.code, this.message, this.data);

  @override
  String toString() => message ?? '请求失败 (code: $code)';

  /// 解析响应 body：非 0 业务码（[checkCode] 开启时）返回对应异常，否则返回 null。
  /// 纯函数，便于单元测试统一业务码校验逻辑。
  static BusinessException? fromBody(dynamic body, {bool checkCode = true}) {
    if (!checkCode ||
        body is! Map ||
        body['code'] is! num ||
        (body['code'] as num) == 0) {
      return null;
    }
    return BusinessException(
      (body['code'] as num).toInt(),
      body['msg']?.toString(),
      body['data'],
    );
  }
}
