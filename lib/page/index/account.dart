import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloudpavilion/api/FileApi.dart';
import 'package:cloudpavilion/api/UserApi.dart';
import 'package:cloudpavilion/config/AppTheme.dart';
import 'package:cloudpavilion/config/AppWidgets.dart';
import 'package:cloudpavilion/config/ThemeController.dart';
import 'package:cloudpavilion/config/SlideUpPageRoute.dart';
import 'package:cloudpavilion/enums/FileType.dart';
import 'package:cloudpavilion/page/index/SecurityPage.dart';
import 'package:cloudpavilion/page/index/shares.dart';
import 'package:cloudpavilion/page/login/users.dart';
import 'package:cloudpavilion/util/AppCache.dart';
import 'package:cloudpavilion/util/AudioPlayerService.dart';
import 'package:cloudpavilion/util/AuthState.dart';
import 'package:cloudpavilion/util/DownloadManager.dart';
import 'package:cloudpavilion/util/TokenAutoRefresh.dart';
import 'package:cloudpavilion/util/TokenManager.dart';
import 'package:cloudpavilion/util/UpdateChecker.dart';
import 'package:cloudpavilion/util/UploadManager.dart';
import 'package:intl/intl.dart';
import '../../util/SpUtils.dart';
import 'package:url_launcher/url_launcher.dart';

/// 原生下载相关通道
const _downloadsChannel = MethodChannel('cloudreve/downloads');

/// 用户信息页
class Account extends StatefulWidget {
  /// 每次进入「用户」页时递增，用于重播容量卡入场动画
  final int replayTick;

  Account({super.key, this.replayTick = 0});

  @override
  State<Account> createState() => _AccountState();
}

class _AccountState extends State<Account> with AutomaticKeepAliveClientMixin {
  late Map<String, dynamic> _userInfo = {
    "data": {
      "avatar": "",
      "nickname": "",
      "group": {"name": ""}
    },
    "userName": ""
  };
  final Uri _url = Uri.parse('https://github.com/Miriy-been/cloud-pavilion');
  late String _freshTime = "";
  late int _used = 0;
  late int _total = 1;

  /// 容量卡入场动画重播计数（下拉刷新 / 重新进入页面时 +1）
  int _replayTick = 0;

  /// 下载路径模式：system=系统下载目录 app=应用专属目录
  String _downloadMode = 'app';

  // 控件被创建的时候，会执行 initState
  @override
  void initState() {
    super.initState();
    getUserInfo();
    _loadDownloadMode();
  }

  /// 一键清除本地缓存（图片缩略图 / 已缓存音乐 / 下载临时文件）
  Future<void> _clearCache() async {
    final size = await AppCache.totalCacheSize();
    if (!mounted) return;
    if (size <= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(appSnack('当前没有可清理的缓存'));
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除缓存'),
        content: Text('将清除 ${formatBytes(size)} 缓存（图片缩略图、已缓存的音乐等），'
            '清除后下次打开会自动重新加载。确定清除吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final freed = await AppCache.clearAllCache();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(appSnack('已清除 ${formatBytes(freed)} 缓存'));
  }

  /// 恢复下载路径模式
  Future<void> _loadDownloadMode() async {
    final mode = await SpUtils.getString('downloadDirMode', 'system');
    if (mounted && mode != _downloadMode) {
      setState(() => _downloadMode = mode);
    }
  }

  @override
  void didUpdateWidget(covariant Account oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 重新进入「用户」页时重播容量卡入场动画
    if (widget.replayTick != oldWidget.replayTick) {
      setState(() => _replayTick++);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // 订阅主题：深浅色切换时重建页面
    Theme.of(context);
    final data = _userInfo['data'] ?? {};
    final nickname = data['nickname']?.toString() ?? '';
    final avatar = data['avatar']?.toString() ?? '';
    final siteName = _userInfo['siteName']?.toString() ?? '';

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: pagePad),
                child: PageHeader(
                  title: '我的',
                  actions: [
                    IconTile(
                      icon: Icons.switch_account_outlined,
                      onTap: () =>
                          Navigator.push(context, SlideUpPageRoute(Users())),
                    ),
                    IconTile(
                      icon: Icons.logout,
                      onTap: _confirmLogout,
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: pagePad),
                child: _buildProfile(nickname, avatar, siteName),
              ),
            ),
            if (_total > 1)
              SliverToBoxAdapter(
                child: Padding(
                  padding:
                      const EdgeInsets.fromLTRB(pagePad, 16, pagePad, 0),
                  child: CapacityCard(
                    key: ValueKey('capacity-$_replayTick'),
                    usedBytes: _used,
                    totalBytes: _total,
                    updatedAt: _freshTime,
                  ),
                ),
              ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    pagePad, 20, pagePad, 0),
                child: _buildSettings(),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }

  /// 赞赏码内容（置于「支持开发者」折叠面板内）
  Widget _buildRewardBody() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 16),
      child: Column(
        children: [
          GestureDetector(
            onTap: _showRewardPreview,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset(
                'images/赞赏码.png',
                width: 180,
                height: 180,
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '如果觉得好用，欢迎扫码支持一下',
            style: TextStyle(fontSize: 12, color: AppColors.ink3),
          ),
        ],
      ),
    );
  }

  /// 赞赏码大图预览
  void _showRewardPreview() {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  'images/赞赏码.png',
                  width: 280,
                  height: 280,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '感谢支持',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 个人信息区
  Widget _buildProfile(String nickname, String avatar, String siteName) {
    return Row(
      children: [
        _Avatar(nickname: nickname, avatar: avatar, size: 64),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                nickname.isEmpty ? '未设置昵称' : nickname,
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                  color: AppColors.ink,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (siteName.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.cloud_outlined,
                          size: 14, color: AppColors.primary),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          siteName,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: AppColors.primary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// 设置分组：高频项平铺展示，低频项收纳进「更多设置」折叠面板
  Widget _buildSettings() {
    return Column(
      children: [
        // 高频：隐私安全 / 外观偏好 / 我的分享
        GroupCard(
          children: [
            SettingRow(
              icon: Icons.shield_outlined,
              iconColor: AppColors.primary,
              iconBg: AppColors.primarySoft,
              label: '隐私和安全',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SecurityPage()),
              ),
            ),
            SettingRow(
              icon: Icons.tune,
              iconColor: FileType.DOC.fg,
              iconBg: FileType.DOC.bg,
              label: '外观偏好',
              onTap: _showAppearanceSheet,
            ),
            SettingRow(
              icon: Icons.link,
              iconColor: AppColors.primary,
              iconBg: AppColors.primarySoft,
              label: '我的分享',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SharesPage()),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // 低频：更多设置（折叠面板）
        GroupCard(
          children: [
            ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 14),
              childrenPadding: EdgeInsets.zero,
              shape: const Border(),
              collapsedShape: const Border(),
              iconColor: AppColors.ink3,
              collapsedIconColor: AppColors.ink3,
              leading: _tileIcon(Icons.tune, FileType.DOC.fg, FileType.DOC.bg),
              title: Text(
                '更多设置',
                style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w500,
                    color: AppColors.ink),
              ),
              children: [
                SettingRow(
                  icon: Icons.forum_outlined,
                  iconColor: AppColors.warning,
                  iconBg: AppColors.warningBg,
                  label: '项目地址',
                  onTap: () => launchUrl(_url),
                ),
                SettingRow(
                  icon: Icons.download_outlined,
                  iconColor: FileType.IMAGE.fg,
                  iconBg: FileType.IMAGE.bg,
                  label: '下载路径',
                  onTap: _showDownloadPathSheet,
                ),
                SettingRow(
                  icon: Icons.system_update_alt,
                  iconColor: AppColors.primary,
                  iconBg: AppColors.primarySoft,
                  label: '检查更新',
                  onTap: () =>
                      UpdateChecker.check(manual: true, context: context),
                ),
                SettingRow(
                  icon: Icons.cleaning_services_outlined,
                  iconColor: FileType.DOC.fg,
                  iconBg: FileType.DOC.bg,
                  label: '清除缓存',
                  onTap: _clearCache,
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        // 支持开发者（折叠面板，赞赏码）
        GroupCard(
          children: [
            ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 14),
              childrenPadding: EdgeInsets.zero,
              shape: const Border(),
              collapsedShape: const Border(),
              iconColor: AppColors.ink3,
              collapsedIconColor: AppColors.ink3,
              leading: _tileIcon(
                  Icons.favorite, AppColors.danger, AppColors.dangerBg),
              title: Text(
                '支持开发者',
                style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w500,
                    color: AppColors.ink),
              ),
              children: [_buildRewardBody()],
            ),
          ],
        ),
      ],
    );
  }

  /// 折叠面板头部彩色小图标
  Widget _tileIcon(IconData icon, Color color, Color bg) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 18, color: color),
    );
  }

  /// 外观偏好：主题模式切换
  void _showAppearanceSheet() {
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
              Text(
                '外观偏好',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '选择界面的显示模式',
                style: TextStyle(fontSize: 12.5, color: AppColors.ink3),
              ),
              const SizedBox(height: 14),
              _ThemeOption(
                icon: Icons.light_mode_outlined,
                label: '浅色',
                selected: ThemeController.mode.value == ThemeMode.light,
                onTap: () {
                  ThemeController.set(ThemeMode.light);
                  Navigator.pop(ctx);
                },
              ),
              _ThemeOption(
                icon: Icons.dark_mode_outlined,
                label: '深色',
                selected: ThemeController.mode.value == ThemeMode.dark,
                onTap: () {
                  ThemeController.set(ThemeMode.dark);
                  Navigator.pop(ctx);
                },
              ),
              _ThemeOption(
                icon: Icons.brightness_auto_outlined,
                label: '跟随系统',
                selected: ThemeController.mode.value == ThemeMode.system,
                onTap: () {
                  ThemeController.set(ThemeMode.system);
                  Navigator.pop(ctx);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 下载路径选择弹窗
  void _showDownloadPathSheet() {
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
              Text(
                '下载路径',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '选择文件下载后的保存位置',
                style: TextStyle(fontSize: 12.5, color: AppColors.ink3),
              ),
              const SizedBox(height: 14),
              _DownloadOption(
                icon: Icons.folder_open,
                title: '系统下载目录',
                desc: '文件直接保存至系统默认 Download 文件夹',
                selected: _downloadMode == 'system',
                onTap: () {
                  setState(() => _downloadMode = 'system');
                  SpUtils.setString('downloadDirMode', 'system');
                  Navigator.pop(ctx);
                },
              ),
              _DownloadOption(
                icon: Icons.folder_special,
                title: '应用专属目录',
                desc: '自动在手机根目录创建 cloudreve 文件夹存放下载文件',
                selected: _downloadMode == 'app',
                onTap: () async {
                  if (!await _ensureAppDirAccess()) return;
                  if (!mounted) return;
                  setState(() => _downloadMode = 'app');
                  SpUtils.setString('downloadDirMode', 'app');
                  if (ctx.mounted) Navigator.pop(ctx);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 应用专属目录：校验 /storage/emulated/0/cloudreve 可访问，未授权时引导
  Future<bool> _ensureAppDirAccess() async {
    final res = await _downloadsChannel
        .invokeMethod<Map<dynamic, dynamic>>('ensureAppDownloadDir');
    if (res != null && res['ok'] == true) return true;
    if (res == null || res['needPermission'] != true) return true;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('需要权限'),
        content: const Text(
            '保存到 /storage/emulated/0/cloudreve 需要开启「所有文件访问」权限，是否前往设置开启？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('去授权'),
          ),
        ],
      ),
    );
    if (go == true) {
      _downloadsChannel.invokeMethod('openAllFilesAccess');
      return true;
    }
    return false;
  }

  /// 退出登录确认
  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认'),
        content: const Text('你确认要退出登录吗？\n所有正在运行中的任务，比如上传 / 下载均会停止'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('退出登录'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    // 停止后台播放的音乐
    AudioPlayerService.instance.stop();
    // 停止 token 定时自动刷新
    TokenAutoRefresh.instance.stop();
    // 停止所有进行中的上传/下载任务（与提示语「任务会停止」一致）
    for (final t in List.of(DownloadManager.instance.tasks)) {
      DownloadManager.instance.cancel(t);
    }
    for (final t in List.of(UploadManager.instance.tasks)) {
      UploadManager.instance.cancel(t);
    }
    // 清空文件列表/直链/元数据缓存，避免登出后残留旧账号数据
    FileApi.clearAllCache();
    // 切换登录状态
    TokenManager.clear();
    SpUtils.setBool("isLogin", false);
    AuthState.isLoggedIn.value = false;
    // 跳转路由
    Navigator.pushNamedAndRemoveUntil(
        context, "/home", (route) => false);
  }

  /// 保持页面状态
  @override
  bool get wantKeepAlive => true;

  Future<void> getUserInfo() async {
    var result = await SpUtils.getString('userInfo');
    Map<String, dynamic> jsondata = jsonDecode(result);
    setState(() {
      _userInfo = jsondata;
    });
    await getStorage();
  }

  /// 空间使用情况
  Future<void> getStorage() async {
    try {
      final data = await UserApi.getCapacity();
      final timeFormat = DateFormat('yyyy/MM/dd');
      setState(() {
        _total = data['total'];
        _used = data['used'];
        _freshTime = timeFormat.format(DateTime.now());
      });
      SpUtils.setString('freshTime', _freshTime);
    } catch (e) {
      // 拿缓存时间
      var time = await SpUtils.getString('freshTime');
      setState(() {
        _freshTime = time;
      });
    }
  }

  Future<void> _refresh() async {
    await Future.delayed(const Duration(seconds: 1));
    await getUserInfo();
    // 下拉刷新完成后重播容量卡入场动画
    if (mounted) setState(() => _replayTick++);
  }
}

/// 头像（网络图失败时回退为首字渐变）
class _Avatar extends StatelessWidget {
  final String nickname;
  final String avatar;
  final double size;

  const _Avatar({
    required this.nickname,
    required this.avatar,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: AppColors.brandGradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Text(
          nickname.isEmpty ? '云' : nickname.characters.first,
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.36,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
    if (avatar.isEmpty) return fallback;
    return ClipOval(
      child: Image.network(
        avatar,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }
}

/// 主题选项行
class _ThemeOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeOption({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.primarySoft
                    : AppColors.bg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                size: 21,
                color: selected ? AppColors.primary : AppColors.ink2,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: selected ? AppColors.primary : AppColors.ink,
                ),
              ),
            ),
            if (selected)
              Icon(Icons.check_circle,
                  size: 20, color: AppColors.primary),
          ],
        ),
      ),
    );
  }
}

/// 下载路径选项行（标题 + 说明 + 选中态）
class _DownloadOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String desc;
  final bool selected;
  final VoidCallback onTap;

  const _DownloadOption({
    required this.icon,
    required this.title,
    required this.desc,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: selected ? AppColors.primarySoft : AppColors.bg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                size: 22,
                color: selected ? AppColors.primary : AppColors.ink2,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: selected ? AppColors.primary : AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    desc,
                    style: TextStyle(fontSize: 11.5, color: AppColors.ink3),
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle, size: 20, color: AppColors.primary),
          ],
        ),
      ),
    );
  }
}
