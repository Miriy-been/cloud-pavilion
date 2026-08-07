import 'package:flutter/material.dart';
import 'package:flutter_application_2/config/AppTheme.dart';

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
        builder: (ctx, setState) => AlertDialog(
          title: const Text('创建分享'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 16),
                DropdownButtonFormField<int?>(
                  initialValue: null,
                  decoration: const InputDecoration(labelText: '有效期'),
                  items: const [
                    DropdownMenuItem<int?>(value: null, child: Text('永久')),
                    DropdownMenuItem<int?>(value: 86400, child: Text('1 天')),
                    DropdownMenuItem<int?>(value: 604800, child: Text('7 天')),
                    DropdownMenuItem<int?>(value: 2592000, child: Text('30 天')),
                  ],
                  onChanged: (v) => setState(() => expireSeconds = v),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passwordController,
                  decoration: const InputDecoration(
                    labelText: '访问密码（可选，留空为公开分享）',
                    hintText: '仅限字母和数字',
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Expanded(child: Text('下载后自动过期')),
                    Switch(
                      value: autoExpire,
                      activeTrackColor: AppColors.primary,
                      onChanged: (v) => setState(() => autoExpire = v),
                    ),
                  ],
                ),
                if (autoExpire)
                  TextField(
                    controller: remainController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '下载次数（达到次数后链接失效）',
                      hintText: '例如 10',
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消')),
            TextButton(
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
              child: const Text('创建'),
            ),
          ],
        ),
      );
    },
  );
}
