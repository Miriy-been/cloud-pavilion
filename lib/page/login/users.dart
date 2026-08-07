import 'package:flutter/material.dart';
import 'package:flutter_application_2/api/FileApi.dart';
import 'package:flutter_application_2/config/AppTheme.dart';
import 'package:flutter_application_2/config/AppWidgets.dart';
import 'package:flutter_application_2/util/SpUtils.dart';
import 'package:flutter_application_2/util/TokenAutoRefresh.dart';
import 'package:flutter_application_2/util/TokenManager.dart';
import 'package:flutter_smart_dialog/src/smart_dialog.dart';
import 'dart:convert';

/// 账户管理
class Users extends StatefulWidget {
  Users({super.key});

  @override
  State<Users> createState() => _UsersState();
}

class _UsersState extends State<Users> {
  late List userList = [];

  // 控件被创建的时候，会执行 initState
  @override
  void initState() {
    super.initState();
    getUserList();
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
              title: '账户管理',
              secondary: true,
              leading: IconTile(
                icon: Icons.close,
                filled: false,
                compact: true,
                onTap: () => Navigator.pop(context),
              ),
              actions: [
                IconTile(icon: Icons.qr_code_scanner, onTap: () {}),
                IconTile(
                  icon: Icons.add,
                  onTap: () => Navigator.pushNamed(context, "/home"),
                ),
              ],
            ),
          ),
          Expanded(
            child: userList.isEmpty
                ? const EmptyState(
                    icon: Icons.switch_account_outlined,
                    title: '还没有绑定任何账号',
                    subtitle: '点击右上角 + 绑定新站点',
                  )
                : ListView.builder(
                    padding: EdgeInsets.fromLTRB(pagePad, 6, pagePad,
                        MediaQuery.of(context).padding.bottom + 16),
                    itemCount: userList.length,
                    itemBuilder: (context, index) {
                      final obj = userList[index];
                      return _buildSiteSection(obj);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// 站点分组
  Widget _buildSiteSection(Map<String, dynamic> obj) {
    final siteUrl = obj['siteUrl']?.toString() ?? '';
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  // 站点地址：多站点场景下区分账号归属
                  child: Text(
                    siteUrl,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          ...(obj['list'] as List)
              .map((data) => _buildAccountRow(data))
              .toList(),
        ],
      ),
    );
  }

  /// 账号行
  Widget _buildAccountRow(Map<String, dynamic> data) {
    final userData = data['data'] ?? {};
    final nickname = userData['nickname']?.toString() ?? '';
    final avatar = userData['avatar']?.toString() ?? '';
    final isCurrent = data['isCurrent'] == true;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => login(data),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(
              color: isCurrent ? AppColors.primary : AppColors.line,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: const [
              BoxShadow(
                color: AppColors.shadow,
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              _AccountAvatar(
                nickname: nickname,
                avatar: avatar,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nickname,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      data['userName']?.toString() ?? '',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.ink3),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              _Radio(on: isCurrent),
            ],
          ),
        ),
      ),
    );
  }

  void getUserList() async {
    List<Map<String, dynamic>> result = [];
    String currentUserName = await SpUtils.getString('currentUserName');
    String currentBaseUrl = await SpUtils.getString('CurrentBaseUrl');
    List<String> localList = await SpUtils.getStringList('accounts');
    // 根据站点组合（同一站点下的账号合并为一组，避免分组重复）
    localList.forEach((data) {
      Map<String, dynamic> jsonData = json.decode(data);
      jsonData['isCurrent'] = false;
      // 当前账号
      if (jsonData['siteUrl'] == currentBaseUrl &&
          jsonData['userName'] == currentUserName) {
        jsonData['isCurrent'] = true;
      }
      var hasSite =
          result.any((value) => value['siteUrl'] == jsonData['siteUrl']);
      if (hasSite) {
        // 站点已存在：并入该组
        final group = result.firstWhere(
            (value) => value['siteUrl'] == jsonData['siteUrl']);
        (group['list'] as List).add(jsonData);
      } else {
        // 新站点：新建分组
        result.add({
          "siteUrl": jsonData['siteUrl'],
          "siteName": jsonData['siteName'],
          "list": [jsonData],
        });
      }
    });
    setState(() {
      userList = result;
    });
  }

  /// 切换账号：将该账号的 token 写入当前上下文并回到主页
  void login(Map<String, dynamic> data) async {
    final token = data['token'];
    if (token == null) {
      SmartDialog.showToast('该账号缺少登录信息，请重新登录');
      return;
    }
    await TokenManager.saveTokens(
      accessToken: token['access_token'],
      refreshToken: token['refresh_token'],
      accessExpires: DateTime.parse(token['access_expires']),
      refreshExpires: DateTime.parse(token['refresh_expires']),
    );
    // 切换账号：清空文件列表 / 元数据缓存，避免串用上一个账号的数据
    FileApi.clearAllCache();
    await SpUtils.setString('CurrentBaseUrl', data['siteUrl']);
    await SpUtils.setString('currentUserName', data['userName']);
    await SpUtils.setString('userInfo', json.encode(data));
    await SpUtils.setBool('isLogin', true);
    await SpUtils.setString('currentMenu', FileApi.myRootUri);
    await SpUtils.setString('folderStack', '');
    // 切换账号后启动 token 定时自动刷新
    TokenAutoRefresh.instance.start();
    Navigator.pushNamedAndRemoveUntil(context, "/", (route) => false);
  }
}

/// 账号头像（网络图失败回退首字）
class _AccountAvatar extends StatelessWidget {
  final String nickname;
  final String avatar;

  const _AccountAvatar({required this.nickname, required this.avatar});

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: 40,
      height: 40,
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
          style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600),
        ),
      ),
    );
    if (avatar.isEmpty) return fallback;
    return ClipOval(
      child: Image.network(
        avatar,
        width: 40,
        height: 40,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }
}

/// 圆形单选项
class _Radio extends StatelessWidget {
  final bool on;

  const _Radio({required this.on});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: on ? AppColors.primary : AppColors.surface,
        border: Border.all(
          color: on ? AppColors.primary : AppColors.line,
          width: 1.8,
        ),
      ),
      child: on ? const Icon(Icons.check, size: 14, color: Colors.white) : null,
    );
  }
}
