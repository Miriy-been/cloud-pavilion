import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:cloudpavilion/api/FileApi.dart';
import 'package:cloudpavilion/api/SecurityApi.dart';
import 'package:cloudpavilion/config/AppTheme.dart';
import 'package:cloudpavilion/config/AppWidgets.dart';
import 'package:cloudpavilion/util/AudioPlayerService.dart';
import 'package:cloudpavilion/util/AuthState.dart';
import 'package:cloudpavilion/util/FingerprintService.dart';
import 'package:cloudpavilion/util/SpUtils.dart';
import 'package:cloudpavilion/util/TokenAutoRefresh.dart';
import 'package:cloudpavilion/util/TokenManager.dart';

/// 隐私和安全页
/// - 密码管理：重设密码
/// - 指纹登录：查看已开启指纹登录的账号 / 关闭
class SecurityPage extends StatefulWidget {
  const SecurityPage({super.key});

  @override
  State<SecurityPage> createState() => _SecurityPageState();
}

class _SecurityPageState extends State<SecurityPage> {
  // 密码管理
  final _currentPwd = TextEditingController();
  final _newPwd = TextEditingController();
  final _confirmPwd = TextEditingController();
  bool _changingPwd = false;

  // 指纹登录账号
  List<Map<String, dynamic>> _fpAccounts = [];
  bool _loadingFp = true;
  String? _disablingKey;

  @override
  void initState() {
    super.initState();
    _loadFpAccounts();
  }

  @override
  void dispose() {
    _currentPwd.dispose();
    _newPwd.dispose();
    _confirmPwd.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(appSnack(msg));
  }

  /// 加载已开启指纹登录的账号
  Future<void> _loadFpAccounts() async {
    final accounts = await FingerprintService.listAccounts();
    if (!mounted) return;
    setState(() {
      _fpAccounts = accounts;
      _loadingFp = false;
    });
  }

  /// 重设密码
  Future<void> _changePassword() async {
    if (_newPwd.text.length < 6) {
      _toast('新密码至少 6 位');
      return;
    }
    if (_newPwd.text != _confirmPwd.text) {
      _toast('两次输入的新密码不一致');
      return;
    }
    setState(() => _changingPwd = true);
    try {
      await SecurityApi.changePassword(_currentPwd.text, _newPwd.text);
      // 修改成功：旧 token 已失效，清除本机凭据与缓存，跳回登录页重新登录
      AudioPlayerService.instance.stop();
      TokenAutoRefresh.instance.stop();
      TokenManager.clear();
      SpUtils.setBool('isLogin', false);
      AuthState.isLoggedIn.value = false;
      FileApi.clearAllCache();
      final siteUrl = await SpUtils.getString('CurrentBaseUrl');
      final userName = await SpUtils.getString('currentUserName');
      // 本机指纹保存的密码已是旧密码，一并移除
      await FingerprintService.disable(siteUrl, userName);
      // 移除多账号快照中的该账号：token 已随改密失效，
      // 不应再出现在账户管理页且可被旧 token 登录
      final accounts = await SpUtils.getStringList('accounts');
      if (accounts.isNotEmpty) {
        final kept = accounts.where((raw) {
          try {
            final jsonData = json.decode(raw) as Map<String, dynamic>;
            return !(jsonData['siteUrl'] == siteUrl &&
                jsonData['userName'] == userName);
          } catch (_) {
            return true;
          }
        }).toList();
        await SpUtils.setStringList('accounts', kept);
      }
      if (!mounted) return;
      _currentPwd.clear();
      _newPwd.clear();
      _confirmPwd.clear();
      _toast('密码修改成功，请重新登录');
      Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
    } catch (e) {
      final msg = e.toString().replaceAll('Exception: ', '');
      _toast('密码修改失败：$msg');
    } finally {
      if (mounted) setState(() => _changingPwd = false);
    }
  }

  /// 关闭指定账号的指纹登录
  Future<void> _disableFingerprint(Map<String, dynamic> account) async {
    final siteUrl = (account['siteUrl'] ?? '').toString();
    final userName = (account['userName'] ?? '').toString();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('关闭指纹登录'),
        content: Text('关闭后「$userName」将无法用指纹快捷登录，确定关闭吗？'),
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
    final key = '$siteUrl|$userName';
    setState(() => _disablingKey = key);
    await FingerprintService.disable(siteUrl, userName);
    if (mounted) {
      setState(() {
        _fpAccounts.removeWhere((a) =>
            a['siteUrl'] == siteUrl && a['userName'] == userName);
        _disablingKey = null;
      });
    }
    _toast('已关闭');
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
              title: '隐私和安全',
              secondary: true,
              leading: IconTile(
                icon: Icons.arrow_back_ios_new,
                filled: false,
                compact: true,
                onTap: () => Navigator.pop(context),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(pagePad, 4, pagePad, 32),
              children: [
                _buildPasswordSection(),
                const SizedBox(height: 24),
                _buildFingerprintSection(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 密码管理
  Widget _buildPasswordSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('密码管理',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.ink2)),
        const SizedBox(height: 8),
        GroupCard(
          children: [
            _PasswordField(
              controller: _currentPwd,
              hint: '当前密码',
              icon: Icons.lock_outline,
            ),
            _PasswordField(
              controller: _newPwd,
              hint: '新密码（至少 6 位）',
              icon: Icons.password_rounded,
            ),
            _PasswordField(
              controller: _confirmPwd,
              hint: '确认新密码',
              icon: Icons.verified_user_outlined,
            ),
            // 按钮区与输入区用分隔线隔开，留白更舒适
            Container(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.line)),
              ),
              padding: const EdgeInsets.all(14),
              child: SizedBox(
                width: double.infinity,
                child: PillButton(
                  label: _changingPwd ? '保存中…' : '保存新密码',
                  onPressed: _changingPwd ? null : _changePassword,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 指纹登录账号管理
  Widget _buildFingerprintSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('指纹登录',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink2)),
            const Spacer(),
            Text('${_fpAccounts.length} 个账号已开启',
                style: TextStyle(fontSize: 12, color: AppColors.ink3)),
          ],
        ),
        const SizedBox(height: 8),
        GroupCard(
          children: [
            if (_loadingFp)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Center(
                    child: CircularProgressIndicator(strokeWidth: 3)),
              )
            else if (_fpAccounts.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 26),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.fingerprint, size: 38, color: AppColors.ink3),
                      const SizedBox(height: 8),
                      Text('尚未开启指纹登录',
                          style: TextStyle(
                              fontSize: 13, color: AppColors.ink3)),
                      const SizedBox(height: 4),
                      Text('用密码登录成功后按提示开启',
                          style: TextStyle(
                              fontSize: 12, color: AppColors.ink3)),
                    ],
                  ),
                ),
              )
            else
              ..._fpAccounts.map((a) {
                final siteUrl = (a['siteUrl'] ?? '').toString();
                final userName = (a['userName'] ?? '').toString();
                final disabling = _disablingKey == '$siteUrl|$userName';
                return Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: AppColors.line)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: AppColors.primarySoft,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.fingerprint,
                            size: 18, color: AppColors.primary),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(userName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.ink)),
                            const SizedBox(height: 3),
                            // 站点地址：多站点场景下区分账号归属
                            Text(siteUrl,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 11.5, color: AppColors.ink3)),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: disabling
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2),
                              )
                            : Icon(Icons.delete_outline,
                                size: 20, color: AppColors.danger),
                        onPressed:
                            disabling ? null : () => _disableFingerprint(a),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
        const SizedBox(height: 8),
        Text('指纹登录仅在本机验证指纹后自动填入保存的密码，凭据加密存储于本机',
            style: TextStyle(fontSize: 11.5, color: AppColors.ink3)),
      ],
    );
  }
}

/// 密码输入行
class _PasswordField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;

  const _PasswordField({
    required this.controller,
    required this.hint,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.ink3),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              obscureText: true,
              style: TextStyle(fontSize: 14, color: AppColors.ink),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(fontSize: 14, color: AppColors.ink3),
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
