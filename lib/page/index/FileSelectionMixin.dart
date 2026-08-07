import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_application_2/api/FileApi.dart';
import 'package:flutter_application_2/api/ShareApi.dart';
import 'package:flutter_application_2/config/AppTheme.dart';
import 'package:flutter_application_2/config/AppWidgets.dart';
import 'package:flutter_application_2/enums/FileType.dart';
import 'package:flutter_application_2/model/FileItemModel.dart';
import 'package:flutter_application_2/page/tools/FolderPicker.dart';
import 'package:flutter_application_2/page/tools/ShareSheet.dart';
import 'package:flutter_application_2/util/DownloadManager.dart';
import 'package:flutter_application_2/util/SpUtils.dart';

/// 文件多选与批量操作（存储页 / 分类页共用）
///
/// 提供：多选状态、底部操作条（下载 / 分享 / 删除 / 更多）、
/// 删除 / 移动 / 复制 / 重命名 / 分享 / 下载等批量操作与配套对话框。
/// 批量操作完成后调用 [afterAction] 刷新列表；文件夹下载通过
/// [onFolderDownload] 由使用方提供（不支持时提示）。
///
/// 注意：mixin 成员均为公开名（跨库复用，无法使用库级私有标识符），
/// 使用方混入后可直接调用 selectionMode / selected 等。
mixin FileSelectionMixin<T extends StatefulWidget> on State<T> {
  /// 是否处于多选模式
  bool selectionMode = false;

  /// 当前选中的文件
  final Set<FileItemModel> selected = {};

  /// 多选状态变化回调（用于隐藏底部主导航栏）
  ValueChanged<bool>? get onSelectionChanged => null;

  /// 文件夹打包下载（可选；未提供时选中文件夹会提示不支持）
  Future<void> Function(FileItemModel dir)? onFolderDownload;

  /// 批量操作完成后的列表刷新（由使用方提供）
  void afterAction();

  void setSelectionMode(bool value) {
    setState(() {
      selectionMode = value;
      if (!value) selected.clear();
    });
    onSelectionChanged?.call(value);
  }

  void exitSelection() => setSelectionMode(false);

  void toggleSelect(FileItemModel obj) {
    setState(() {
      if (!selected.add(obj)) {
        selected.remove(obj);
      }
    });
  }

  /// 全选 / 取消全选
  void selectAll(List<FileItemModel> items) {
    setState(() {
      if (selected.length == items.length) {
        selected.clear();
      } else {
        selected.clear();
        selected.addAll(items);
      }
    });
  }

  /// 多选底部操作条（通栏铺满，四个按钮均分整行）
  Widget buildActionBar() {
    return Container(
      color: AppColors.surface,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
          child: Row(
            children: [
              Expanded(
                child: ActionItem(
                  icon: Icons.download,
                  label: '下载',
                  onTap: selected.isEmpty
                      ? null
                      : () => batchDownload(selected.toList()),
                ),
              ),
              Expanded(
                child: ActionItem(
                  icon: Icons.share,
                  label: '分享',
                  onTap: selected.isEmpty
                      ? null
                      : () => batchShare(selected.toList()),
                ),
              ),
              Expanded(
                child: ActionItem(
                  icon: Icons.delete,
                  label: '删除',
                  danger: true,
                  onTap: selected.isEmpty
                      ? null
                      : () => batchDelete(selected.toList()),
                ),
              ),
              Expanded(
                child: ActionItem(
                  icon: Icons.more_horiz,
                  label: '更多',
                  onTap: selected.isEmpty ? null : showMoreActions,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 低频操作弹窗：重命名 / 移动复制（使用方可覆盖以扩展更多操作）
  void showMoreActions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(pagePad),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 6),
              const SheetHandle(),
              const SizedBox(height: 16),
              ListTile(
                leading:
                    Icon(Icons.drive_file_rename_outline, color: AppColors.primary),
                title: const Text('重命名'),
                onTap: () {
                  Navigator.pop(ctx);
                  batchRename(selected.toList());
                },
              ),
              ListTile(
                leading: Icon(Icons.drive_file_move_outline,
                    color: FileType.IMAGE.fg),
                title: const Text('移动 / 复制'),
                onTap: () {
                  Navigator.pop(ctx);
                  batchMove(selected.toList());
                },
              ),
              ListTile(
                leading:
                    Icon(Icons.info_outline, color: AppColors.info),
                title: const Text('详情'),
                onTap: () {
                  Navigator.pop(ctx);
                  if (selected.length != 1) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context)
                        .showSnackBar(appSnack('详情仅支持选择单个文件'));
                    return;
                  }
                  final obj = selected.first;
                  showFileDetailSheet(context, obj.path, obj.name);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 批量下载（文件直下；文件夹走 onFolderDownload，未提供时提示不支持）
  Future<void> batchDownload(List<FileItemModel> items) async {
    final files = items.where((e) => !e.isDir).toList();
    final dirs = items.where((e) => e.isDir).toList();
    for (final obj in files) {
      final url = await FileApi.getDownloadUrl(obj.path);
      DownloadManager.instance.startDownload(obj.name, url);
    }
    for (final obj in dirs) {
      final downloader = onFolderDownload;
      if (downloader == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(appSnack('暂不支持下载文件夹'));
        return;
      }
      await downloader(obj);
    }
    exitSelection();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(appSnack('已添加 ${files.length} 个下载任务'));
  }

  /// 批量删除（进回收站）
  Future<void> batchDelete(List<FileItemModel> items) async {
    final confirmed = await showConfirmDialog(
        '批量删除', '确定将选中的 ${items.length} 项移入回收站吗？');
    if (confirmed != true) return;
    await FileApi.deleteFiles(items.map((e) => e.path).toList());
    exitSelection();
    afterAction();
  }

  /// 批量分享（配置项与单个分享一致）
  Future<void> batchShare(List<FileItemModel> items) async {
    final share = await showShareDialog(context, '${items.length} 个文件');
    if (share == null) return;
    final siteUrl = await SpUtils.getString('CurrentBaseUrl');
    final links = <String>[];
    var failed = 0;
    for (final obj in items) {
      try {
        final path = await ShareApi.createShare(
          obj.path,
          isPrivate: share.password.isNotEmpty,
          expireSeconds: share.expireSeconds,
          password: share.password.isEmpty ? null : share.password,
          remainDownloads: share.remainDownloads,
        );
        links.add(ShareApi.buildFullUrl(siteUrl, path));
      } catch (e) {
        failed++;
      }
    }
    exitSelection();
    if (links.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: links.first));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(appSnack(failed > 0
          ? '已创建 ${links.length} 个分享，$failed 个失败，第一个链接已复制'
          : '已创建 ${links.length} 个分享，第一个链接已复制'));
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(appSnack('创建分享失败'));
    }
  }

  /// 批量移动 / 复制
  Future<void> batchMove(List<FileItemModel> items) async {
    final dir = await SpUtils.getString('currentMenu');
    final result = await FolderPicker.pick(
      context,
      startUri: dir.isEmpty ? FileApi.myRootUri : dir,
    );
    if (result == null) return;
    final error = validateMove(items, result.uri, copy: result.copy);
    if (error != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(appSnack(error));
      return;
    }
    await FileApi.moveOrCopyFiles(
        items.map((e) => e.path).toList(), result.uri,
        copy: result.copy);
    exitSelection();
    afterAction();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(appSnack('已${result.copy ? '复制' : '移动'} ${items.length} 项'));
  }

  /// 重命名（仅支持单选）
  Future<void> batchRename(List<FileItemModel> items) async {
    if (items.length != 1) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(appSnack('重命名仅支持选择单个文件'));
      return;
    }
    final obj = items.first;
    final name = await showInputDialog('重命名', '新名称', initial: obj.name);
    if (name == null || name.isEmpty || name == obj.name) return;
    await FileApi.renameFile(obj.path, name);
    exitSelection();
    afterAction();
  }

  /// 校验移动 / 复制目标是否合法，返回错误文案（null 表示合法）
  String? validateMove(List<FileItemModel> items, String dst,
      {required bool copy}) {
    for (final item in items) {
      if (dst == item.path || dst.startsWith('${item.path}/')) {
        return '不能将文件移动到自身或其子目录中';
      }
      if (!copy && dst == uriParent(item.path)) {
        return '目标文件夹与源位置相同';
      }
    }
    return null;
  }

  /// 取 URI 的父目录（去末尾最后一段）
  String uriParent(String uri) {
    final idx = uri.lastIndexOf('/');
    return idx <= 0 ? uri : uri.substring(0, idx);
  }

  /// 输入弹窗，返回输入内容（取消返回 null）
  Future<String?> showInputDialog(String title, String hint,
      {String? initial}) async {
    final controller = TextEditingController(text: initial ?? '');
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('确定')),
        ],
      ),
    );
  }

  /// 确认弹窗
  Future<bool?> showConfirmDialog(String title, String content) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('确定')),
        ],
      ),
    );
  }
}

/// 底部操作按钮（下载 / 分享 / 删除 / 更多）
class ActionItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool danger;
  final VoidCallback? onTap;

  const ActionItem({
    super.key,
    required this.icon,
    required this.label,
    this.danger = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = danger
        ? AppColors.danger
        : (onTap == null ? AppColors.ink3 : AppColors.ink2);
    return InkWell(
      onTap: onTap,
      child: SizedBox.expand(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 21, color: color),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 11.5,
                    color: danger ? AppColors.danger : AppColors.ink2)),
          ],
        ),
      ),
    );
  }
}
