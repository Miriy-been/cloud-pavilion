import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_2/api/AuthApi.dart';
import 'package:flutter_application_2/api/FileApi.dart';
import 'package:flutter_application_2/config/AppTheme.dart';
import 'package:flutter_application_2/config/AppWidgets.dart';
import 'package:flutter_application_2/exception/DebugReportException.dart';
import 'package:flutter_application_2/page/login/users.dart';
import 'package:flutter_application_2/util/FingerprintService.dart';
import 'package:flutter_application_2/util/SpUtils.dart';
import 'package:flutter_application_2/util/TokenAutoRefresh.dart';
import 'package:flutter_application_2/util/TokenManager.dart';
import 'dart:convert';

import '../../config/SlideUpPageRoute.dart';

/// 登录页（站点绑定 + 账号密码登录合并单页）
class Login extends StatefulWidget {
  Login({super.key});

  @override
  State<Login> createState() => _LoginState();
}

class _LoginState extends State<Login> {
  var _siteName = '登录';

  TextEditingController _siteAddrController = TextEditingController();
  TextEditingController _emailController = TextEditingController();
  TextEditingController _passwordController = TextEditingController();

  // 控件被创建的时候，会执行 initState
  @override
  void initState() {
    super.initState();
    getTitle();
  }

  @override
  Widget build(BuildContext context) {
    // 订阅主题：深浅色切换时重建登录页配色
    Theme.of(context);
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: pagePad),
              child: Column(
                children: <Widget>[
                  SizedBox(
                      height: MediaQuery.of(context).padding.top + 6),
                  if (Navigator.canPop(context))
                    Align(
                      alignment: Alignment.centerLeft,
                      child: IconTile(
                        icon: Icons.arrow_back_ios_new,
                        filled: false,
                        compact: true,
                        onTap: () => Navigator.pop(context),
                      ),
                    ),
                  const SizedBox(height: 20),
                  _LogoMark(size: 58),
                  const SizedBox(height: 16),
                  Text(
                    _siteName,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 26),
                  // 站点地址
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '站点地址',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _LoginField(
                    icon: Icons.public,
                    hintText: 'https://your-site.com',
                    controller: _siteAddrController,
                    keyboardType: TextInputType.url,
                  ),
                  const SizedBox(height: 16),
                  // 邮箱
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '邮箱',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _LoginField(
                    icon: Icons.email_outlined,
                    hintText: '用户邮箱',
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 16),
                  // 密码
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '密码',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _LoginField(
                    icon: Icons.lock_outline,
                    hintText: '登录密码',
                    controller: _passwordController,
                    obscure: true,
                    keyboardType: TextInputType.visiblePassword,
                  ),
                  const SizedBox(height: 18),
                  PillButton(
                    label: '登录',
                    onPressed: () => login(context),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      GhostButton(
                        label: '指纹登录',
                        icon: Icons.fingerprint,
                        onPressed: () => _fingerprintLogin(context),
                      ),
                      const SizedBox(width: 8),
                      GhostButton(
                        label: '多账号管理',
                        icon: Icons.switch_account_rounded,
                        onPressed: () {
                          Navigator.push(
                              context, SlideUpPageRoute(Users()));
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void getTitle() async {
    var result = await SpUtils.getString('CurrentTitle');
    if (mounted && result.isNotEmpty) {
      setState(() {
        _siteName = result;
      });
    }
  }

  /// 登录（先配置站点，再账号密码登录）
  void login(BuildContext context) async {
    try {
      // 1. 校验站点地址并保存站点配置
      final siteUrl = await _prepareSite();

      // 2. 校验邮箱和密码
      if (_emailController.text.isEmpty) {
        throw FormatException('邮箱不能为空');
      }
      if (_passwordController.text.isEmpty) {
        throw FormatException('密码不能为空');
      }
      // 3. 登录（V4 JWT）
      var result = await AuthApi.login(
          _emailController.text, _passwordController.text);
      if (result['code'] == 203) {
        throw DebugReportException('该站点启用了两步验证，暂不支持');
      }
      if (result['code'] != 0) {
        throw DebugReportException(
            result['msg']?.toString() ?? '邮箱或密码错误');
      }

      // 登录成功：若该账号未开启指纹登录且设备支持，询问开启
      await _offerEnableFingerprint(
          context, siteUrl, _emailController.text, _passwordController.text);

      await _finalizeLogin(context, result, siteUrl, _emailController.text);
    } catch (e) {
      // 登录失败：显式提示（不依赖全局异常处理器）
      if (mounted) _showError(context, e);
    }
  }

  /// 指纹登录（本地指纹解锁已保存的账号凭据，多账号需先选择账号）
  void _fingerprintLogin(BuildContext context) async {
    try {
      final accounts = await FingerprintService.listAccounts();
      if (accounts.isEmpty) {
        throw DebugReportException('此账号尚未开启指纹登录\n请先使用密码登录，成功后按提示开启');
      }

      // 选账号：多个时弹出选择，单个直接使用
      Map<String, dynamic> account;
      if (accounts.length == 1) {
        account = accounts.first;
      } else {
        final selected = await showModalBottomSheet<Map<String, dynamic>>(
          context: context,
          builder: (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text('选择要登录的账号',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink)),
                ),
                ...accounts.map((a) => ListTile(
                      leading: Icon(Icons.account_circle_outlined,
                          color: AppColors.primary),
                      title: Text(
                          '${a['siteName'] ?? ''} · ${a['userName'] ?? ''}',
                          style: const TextStyle(fontSize: 14)),
                      onTap: () => Navigator.pop(ctx, a),
                    )),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
        if (selected == null) return;
        account = selected;
      }

      final siteUrl = (account['siteUrl'] ?? '').toString();
      final userName = (account['userName'] ?? '').toString();
      if (siteUrl.isEmpty || userName.isEmpty) {
        throw DebugReportException('指纹账号信息不完整，请重新开启');
      }

      // 系统指纹验证
      final ok = await FingerprintService.verify(
          '验证指纹登录 ${account['siteName'] ?? userName}');
      if (!ok) return; // 用户取消 / 验证失败

      // 读取本地凭据并登录
      final password =
          await FingerprintService.passwordFor(siteUrl, userName);
      if (password == null || password.isEmpty) {
        throw DebugReportException('本地凭据缺失，请重新用密码登录');
      }
      SpUtils.setString('CurrentBaseUrl', siteUrl);
      final config = await AuthApi.getConfig();
      final siteTitle =
          config['data']['title']?.toString() ?? account['siteName'] ?? '';
      SpUtils.setString('CurrentTitle', siteTitle);
      if (mounted) setState(() => _siteName = siteTitle);

      final result = await AuthApi.login(userName, password);
      if (result['code'] == 203) {
        throw DebugReportException('该站点启用了两步验证，暂不支持');
      }
      if (result['code'] != 0) {
        // 密码可能已被修改：清理本地凭据，避免反复失败
        await FingerprintService.disable(siteUrl, userName);
        throw DebugReportException('登录失败：本地密码可能已过期\n已关闭该账号指纹登录');
      }
      await _finalizeLogin(context, result, siteUrl, userName);
    } catch (e) {
      // 指纹验证取消（返回 false）已静默；其余错误显式提示
      if (mounted) _showError(context, e);
    }
  }

  /// 密码登录成功后询问是否开启指纹登录
  Future<void> _offerEnableFingerprint(BuildContext context, String siteUrl,
      String userName, String password) async {
    if (!mounted) return;
    try {
      if (await FingerprintService.hasAccount(siteUrl, userName)) return;
      if (!await FingerprintService.isAvailable()) return; // 设备不支持
      final enable = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('开启指纹登录'),
          content: const Text('下次可用指纹快速登录此账号，是否开启？'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('暂不')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('开启')),
          ],
        ),
      );
      if (enable == true && mounted) {
        try {
          await FingerprintService.enable(
              siteUrl, userName, _siteName, password);
        } catch (_) {
          ScaffoldMessenger.of(context)
              .showSnackBar(appSnack('开启指纹登录失败，请重试'));
        }
      }
    } catch (_) {}
  }

  /// 登录失败统一提示：解析常见异常为中文文案并用 SnackBar 显示
  void _showError(BuildContext context, Object e) {
    String msg;
    if (e is DebugReportException) {
      msg = e.message;
    } else if (e is FormatException) {
      final m = e.message.toString();
      msg = m.isEmpty ? '输入有误' : m;
    } else if (e is DioException) {
      final resp = e.response;
      if (resp != null) {
        final body = resp.data;
        if (body is Map &&
            body['msg'] != null &&
            body['msg'].toString().isNotEmpty) {
          msg = body['msg'].toString();
        } else {
          msg = '请求失败 (${resp.statusCode})';
        }
      } else {
        switch (e.type) {
          case DioExceptionType.connectionTimeout:
            msg = '连接超时，请检查网络';
          case DioExceptionType.receiveTimeout:
            msg = '响应超时，请稍后重试';
          case DioExceptionType.unknown:
            msg = '网络连接失败，请检查站点地址与网络';
          default:
            msg = '网络请求失败，请重试';
        }
      }
    } else {
      msg = '操作失败：$e';
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(appSnack(msg));
  }

  /// 校验并保存站点地址，返回去掉末尾斜杠的站点 URL
  Future<String> _prepareSite() async {
    if (!Uri.parse(_siteAddrController.text).isAbsolute) {
      throw DebugReportException('站点配置错误');
    }
    String siteUrl = _siteAddrController.text;
    if (siteUrl.endsWith('/')) {
      siteUrl = siteUrl.substring(0, siteUrl.length - 1);
    }
    SpUtils.setString('CurrentBaseUrl', siteUrl);
    final config = await AuthApi.getConfig();
    final siteTitle = config['data']['title']?.toString() ?? '';
    SpUtils.setString('CurrentTitle', siteTitle);
    if (mounted) setState(() => _siteName = siteTitle);
    return siteUrl;
  }

  /// 登录成功后的统一收尾：保存 token 对、本地账号并跳转根目录
  Future<void> _finalizeLogin(BuildContext context,
      Map<String, dynamic> result, String siteUrl, String userName) async {
    // 登录新账号：清空文件列表 / 元数据缓存，避免串用上一个账号的数据
    FileApi.clearAllCache();
    // 保存 token 对
    final token = result['data']['token'];
    await TokenManager.saveTokens(
      accessToken: token['access_token'],
      refreshToken: token['refresh_token'],
      accessExpires: DateTime.parse(token['access_expires']),
      refreshExpires: DateTime.parse(token['refresh_expires']),
    );

    // 加载本地账号
    Map<String, dynamic> userInfo = {
      'data': result['data']['user'],
      'token': token,
      'userName': userName,
      'siteName': _siteName,
      'siteUrl': siteUrl
    };
    convertAvatar(siteUrl, userInfo['data']);

    final accountList = <String>[];
    accountList.add(json.encode(userInfo));

    List<String> localList = await SpUtils.getStringList('accounts');

    if (localList.isNotEmpty) {
      for (var value in localList) {
        Map<String, dynamic> jsonData = json.decode(value);
        if (jsonData['siteUrl'] != siteUrl ||
            jsonData['userName'] != userInfo['userName']) {
          convertAvatar(siteUrl, jsonData['data']);
          accountList.add(value);
        }
      }
    }
    SpUtils.setString('currentUserName', userName);
    SpUtils.setStringList('accounts', accountList);
    SpUtils.setString('userInfo', json.encode(userInfo));
    SpUtils.setBool("isLogin", true);
    SpUtils.setString('currentMenu', 'cloudreve://my');
    SpUtils.setString('folderStack', '');
    // 登录成功后启动 token 定时自动刷新
    TokenAutoRefresh.instance.start();

    // 跳转根目录
    Navigator.pushReplacementNamed(context, "/");
  }

  convertAvatar(String siteUrl, Map<String, dynamic> jsonData) {
    String avatar = siteUrl + '/api/v4/user/avatar/' + jsonData['id'];
    jsonData['avatar'] = avatar;
  }
}

/// 登录输入框（白底圆角 + 前缀图标）
class _LoginField extends StatelessWidget {
  final IconData icon;
  final String hintText;
  final TextEditingController controller;
  final bool obscure;
  final TextInputType keyboardType;

  const _LoginField({
    required this.icon,
    required this.hintText,
    required this.controller,
    this.obscure = false,
    this.keyboardType = TextInputType.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.line, width: 1.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboardType,
        style: TextStyle(fontSize: 15, color: AppColors.ink),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: TextStyle(color: AppColors.ink3),
          border: InputBorder.none,
          prefixIcon: Icon(icon, color: AppColors.ink3, size: 22),
          contentPadding:
              const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        ),
      ),
    );
  }
}

/// 品牌 Logo 标记（渐变圆角方块 + 云图标）
class _LogoMark extends StatelessWidget {
  final double size;

  const _LogoMark({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: AppColors.brandGradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(size * 0.32),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: .3),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Icon(
        Icons.cloud,
        size: size * 0.52,
        color: Colors.white,
      ),
    );
  }
}
