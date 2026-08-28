/// 删除 / 操作命中文件锁冲突（Cloudreve Code=40073，文件被占用）时抛出，
/// 携带服务端返回的解锁 token，供「强制解锁」流程使用。
class LockConflictException implements Exception {
  final List<String> tokens;
  LockConflictException(this.tokens);
}