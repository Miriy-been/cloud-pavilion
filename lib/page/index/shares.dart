import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_application_2/api/ShareApi.dart';
import 'package:flutter_application_2/config/AppTheme.dart';
import 'package:flutter_application_2/config/AppWidgets.dart';
import 'package:flutter_application_2/util/SpUtils.dart';

/// 我的分享列表页
class SharesPage extends StatefulWidget {
  const SharesPage({super.key});

  @override
  State<SharesPage> createState() => _SharesPageState();
}

class _SharesPageState extends State<SharesPage> {
  List<dynamic> _shares = [];
  bool _loading = true;

  /// 排序方式：time（创建时间）/ views（访问量）/ expired（是否过期）
  String _sortBy = 'time';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool showLoading = true}) async {
    if (showLoading) setState(() => _loading = true);
    try {
      // 是否过期后端不支持排序，用默认顺序拉取后在本地重排
      String? orderBy;
      String? orderDirection;
      if (_sortBy == 'time') {
        orderBy = 'id';
        orderDirection = 'desc';
      } else if (_sortBy == 'views') {
        orderBy = 'views';
        orderDirection = 'desc';
      }
      var shares = await ShareApi.listMyShares(
          orderBy: orderBy, orderDirection: orderDirection);
      if (_sortBy == 'expired') {
        shares = List<dynamic>.from(shares)
          ..sort((a, b) {
            final ae = (a as Map)['expired'] == true;
            final be = (b as Map)['expired'] == true;
            if (ae == be) return 0;
            return ae ? 1 : -1;
          });
      }
      if (!mounted) return;
      setState(() {
        _shares = shares;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  /// 切换排序方式
  void _changeSort(String sortBy) {
    if (sortBy == _sortBy) return;
    setState(() => _sortBy = sortBy);
    _load(showLoading: false);
  }

  Future<void> _copyLink(Map<String, dynamic> share) async {
    final siteUrl = await SpUtils.getString('CurrentBaseUrl');
    final fullUrl = ShareApi.buildFullUrl(siteUrl, share['url']);
    await Clipboard.setData(ClipboardData(text: fullUrl));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(appSnack('链接已复制：$fullUrl'));
    }
  }

  Future<void> _deleteShare(Map<String, dynamic> share) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除分享'),
        content: Text('确定删除「${share['name']}」的分享链接吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ShareApi.deleteShare(share['id']);
    _load(showLoading: false);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(appSnack('已删除分享链接'));
  }

  String _expireText(Map<String, dynamic> share) {
    if (share['expired'] == true) return '已过期';
    final expires = share['expires'];
    if (expires == null || expires.toString().isEmpty) return '永久有效';
    final dt = DateTime.tryParse(expires.toString());
    if (dt == null) return '永久有效';
    final local = dt.toLocal();
    return '至 ${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }

  /// 下载次数文案：优先展示剩余次数，否则展示已下载次数
  String _downloadText(Map<String, dynamic> share) {
    final remain = share['remain_downloads'];
    if (remain is int && remain > 0) return '剩余 $remain 次';
    final downloaded = share['downloaded'];
    if (downloaded is int && downloaded > 0) return '已下载 $downloaded 次';
    return '';
  }

  /// 编辑分享弹窗（有效期 + 下载后自动过期）
  /// 注：V4 后端编辑接口不支持修改访问密码，仅只读展示
  Future<(int?, int?)?> _showEditDialog(
      Map<String, dynamic> share, int? remainNow, String? currentPassword) {
    return showDialog<(int?, int?)>(
      context: context,
      builder: (ctx) {
        int? expireSeconds;
        bool autoExpire = remainNow != null && remainNow > 0;
        final remainController =
            TextEditingController(text: autoExpire ? '$remainNow' : '');
        final isPrivate = currentPassword != null && currentPassword.isNotEmpty;
        return StatefulBuilder(
          builder: (ctx, setState) => AlertDialog(
            title: const Text('编辑分享'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  share['name']?.toString() ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600),
                ),
                if (isPrivate) ...[
                  const SizedBox(height: 8),
                  Text(
                    '访问密码：$currentPassword · 不可修改',
                    style: TextStyle(fontSize: 12, color: AppColors.ink3),
                  ),
                ],
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
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Expanded(
                      child: Text('下载后自动过期'),
                    ),
                    Switch(
                      value: autoExpire,
                      activeTrackColor: AppColors.primary,
                      onChanged: (v) => setState(() => autoExpire = v),
                    ),
                  ],
                ),
                if (autoExpire)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 4),
                    child: TextField(
                      controller: remainController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '下载次数（达到次数后失效）',
                        hintText: '例如 10',
                      ),
                    ),
                  ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('取消')),
              TextButton(
                onPressed: () => Navigator.pop(
                    ctx,
                    (
                      expireSeconds,
                      autoExpire
                          ? int.tryParse(remainController.text.trim())
                          : null,
                    )),
                child: const Text('保存'),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 编辑分享：先取 source_uri，再提交修改
  Future<void> _editShare(Map<String, dynamic> share) async {
    // 私有分享需携带密码，后端解析分享 URI 定位源文件时校验密码
    Map<String, dynamic> info;
    try {
      info = await ShareApi.getShareInfo(share['id'],
          password: share['password']?.toString());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(appSnack('获取分享信息失败：$e'));
      return;
    }
    final sourceUri = info['source_uri']?.toString();
    if (sourceUri == null || sourceUri.isEmpty) {
      if (!mounted) return;
      final expired = info['expired'] == true || share['expired'] == true;
      ScaffoldMessenger.of(context).showSnackBar(appSnack(expired
          ? '该分享已过期或源文件不可用，请删除后重新创建'
          : '无法获取分享源文件，编辑失败'));
      return;
    }

    // 与网页版一致：source_uri 是源文件所在位置（单文件分享时为父目录/根），
    // 编辑接口需要定位到具体文件，单文件分享需拼接文件名（百分号编码）
    final name = info['name']?.toString() ?? share['name']?.toString() ?? '';
    final sourceType = info['source_type'] ?? share['source_type'];
    var editUri = sourceUri;
    if (sourceType == 0 && name.isNotEmpty) {
      editUri = sourceUri.endsWith('/')
          ? '$sourceUri${Uri.encodeComponent(name)}'
          : '$sourceUri/${Uri.encodeComponent(name)}';
    }

    final remainNow = info['remain_downloads'];
    final currentPassword =
        info['password']?.toString() ?? share['password']?.toString() ?? '';
    final result = await _showEditDialog(
        share, remainNow is int ? remainNow : null, currentPassword);
    if (result == null || !mounted) return;
    try {
      await ShareApi.updateShare(
        share['id'],
        uri: editUri,
        expireSeconds: result.$1,
        remainDownloads: result.$2,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(appSnack('分享设置已更新'));
      _load(showLoading: false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(appSnack('编辑失败：$e'));
    }
  }

  @override
  Widget build(BuildContext context) {
    // 订阅主题：深浅色切换时重建页面
    Theme.of(context);
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: pagePad),
            child: PageHeader(
              title: '我的分享',
              secondary: true,
              leading: IconTile(
                icon: Icons.arrow_back_ios_new,
                filled: false,
                compact: true,
                onTap: () => Navigator.pop(context),
              ),
            ),
          ),
          // 第二行：列表头 + 排序（顶栏保持标题，信息下沉）
          Padding(
            padding: EdgeInsets.fromLTRB(pagePad, 0, pagePad, 6),
            child: SectionHeader(
              title: '全部分享',
              count: '${_shares.length}',
              trailing: SortChip(
                options: const [
                  SortOption('time', '按时间'),
                  SortOption('views', '按访问量'),
                  SortOption('expired', '按是否过期'),
                ],
                value: _sortBy,
                enableDirection: false,
                onChanged: _changeSort,
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _shares.isEmpty
                    ? const EmptyState(
                        icon: Icons.link,
                        title: '暂无分享',
                        subtitle: '在「存储」页长按文件即可创建分享链接',
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: EdgeInsets.fromLTRB(pagePad, 6, pagePad,
                              MediaQuery.of(context).padding.bottom + 16),
                          itemCount: _shares.length,
                          itemBuilder: (context, index) {
                            final share =
                                _shares[index] as Map<String, dynamic>;
                            final isPrivate = share['is_private'] == true;
                            final dlText = _downloadText(share);
                            final meta = [
                              '访问 ${share['visited'] ?? 0} 次',
                              if (dlText.isNotEmpty) dlText,
                              _expireText(share),
                            ].join(' · ');
                            return FileRow(
                              type: 0,
                              name: share['name'] ?? '',
                              meta: meta,
                              leading: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: isPrivate
                                      ? AppColors.warningBg
                                      : AppColors.primarySoft,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  isPrivate
                                      ? Icons.lock_outline
                                      : Icons.link,
                                  size: 22,
                                  color: isPrivate
                                      ? AppColors.warning
                                      : AppColors.primary,
                                ),
                              ),
                              trailing: PopupMenuButton<String>(
                                icon: Icon(Icons.more_horiz,
                                    size: 22, color: AppColors.ink3),
                                color: AppColors.surface,
                                surfaceTintColor: Colors.transparent,
                                itemBuilder: (ctx) => const [
                                  PopupMenuItem(
                                      value: 'copy',
                                      child: Text('复制链接')),
                                  PopupMenuItem(
                                      value: 'edit',
                                      child: Text('编辑分享')),
                                  PopupMenuItem(
                                      value: 'delete',
                                      child: Text('删除分享')),
                                ],
                                onSelected: (value) {
                                  if (value == 'copy') {
                                    _copyLink(share);
                                  } else if (value == 'edit') {
                                    _editShare(share);
                                  } else if (value == 'delete') {
                                    _deleteShare(share);
                                  }
                                },
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
