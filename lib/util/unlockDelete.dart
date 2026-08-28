import 'package:flutter/material.dart';
import 'package:cloudpavilion/api/FileApi.dart';
import 'package:cloudpavilion/config/AppWidgets.dart';
import 'package:cloudpavilion/exception/LockConflictException.dart';

/// 删除并处理「文件被占用」锁冲突（前缀 Storage 页 `batchDelete` 的解锁逻辑）。
///
/// - 正常：删除成功返回 `true`。
/// - 命中 [LockConflictException]：弹「强制解锁」确认；确认后解锁并重试删除，
///   成功返回 `true`；用户选择取消返回 `false`。
/// - 其它异常（网络等）不在本处吞掉，向上抛给调用方自行提示。
Future<bool> deleteWithUnlock(
  BuildContext context,
  List<String> uris, {
  bool skipSoftDelete = false,
}) async {
  try {
    await FileApi.deleteFiles(uris, skipSoftDelete: skipSoftDelete);
    return true;
  } on LockConflictException catch (e) {
    if (!context.mounted) return false;
    final unlock = await showAppConfirm(
      context: context,
      title: '文件被占用',
      content: '部分文件正在被使用，无法删除。如果你是文件所有者，可以强制解锁后重试。',
    );
    if (unlock != true || !context.mounted) return false;
    await FileApi.unlockFiles(e.tokens);
    await FileApi.deleteFiles(uris, skipSoftDelete: skipSoftDelete);
    return true;
  }
}