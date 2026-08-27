import 'package:flutter/material.dart';
import 'package:cloudpavilion/config/AppTheme.dart';
import 'package:cloudpavilion/config/AppWidgets.dart';

/// 分享参数（有效期 / 访问密码 / 下载后自动过期）
class ShareParams {
  final int? expireSeconds;
  final String password;
  final int? remainDownloads;
  const ShareParams(
      {this.expireSeconds, this.password = '', this.remainDownloads});
}

/// 创建分享参数弹窗（存储页批量分享、预览页快捷分享共用）
Future<ShareParams?> showShareDialog(BuildContext context, String fileName) {
  return showDialog<ShareParams>(
    context: context,
    builder: (ctx) {
      int? expireSeconds;
      bool autoExpire = false;
      final passwordController = TextEditingController();
      final remainController = TextEditingController();
      return StatefulBuilder(
        builder: (ctx, setState) => AppDialogCard(
          header: Text(
            '创建分享',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 分享对象（统一小字说明，突出文件名）
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: AppColors.bg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.insert_drive_file_outlined,
                          size: 16, color: AppColors.ink3),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12.5, color: AppColors.ink2),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<int?>(
                  initialValue: null,
                  decoration: appFieldDecoration('有效期', hint: '永久有效'),
                  items: const [
                    DropdownMenuItem<int?>(value: null, child: Text('永久')),
                    DropdownMenuItem<int?>(value: 86400, child: Text('1 天')),
                    DropdownMenuItem<int?>(
                        value: 604800, child: Text('7 天')),
                    DropdownMenuItem<int?>(
                        value: 2592000, child: Text('30 天')),
                  ],
                  onChanged: (v) => setState(() => expireSeconds = v),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passwordController,
                  decoration: appFieldDecoration('访问密码', hint: '留空为公开分享'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text('下载后自动过期',
                          style: TextStyle(
                              fontSize: 14, color: AppColors.ink)),
                    ),
                    Switch(
                      value: autoExpire,
                      activeTrackColor: AppColors.primary,
                      onChanged: (v) => setState(() => autoExpire = v),
                    ),
                  ],
                ),
                if (autoExpire) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: remainController,
                    keyboardType: TextInputType.number,
                    decoration: appFieldDecoration('下载次数', hint: '达到次数后失效'),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            AppDialogButton(
              label: '取消',
              onPressed: () => Navigator.pop(ctx),
            ),
            AppDialogButton(
              label: '创建',
              primary: true,
              onPressed: () => Navigator.pop(
                ctx,
                ShareParams(
                  expireSeconds: expireSeconds,
                  password: passwordController.text.trim(),
                  remainDownloads: autoExpire
                      ? int.tryParse(remainController.text.trim())
                      : null,
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}
