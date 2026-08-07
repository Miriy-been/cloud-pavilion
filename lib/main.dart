import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_application_2/config/AppTheme.dart';
import 'package:flutter_application_2/config/ThemeController.dart';
import 'package:flutter_application_2/page/index/bottomBar.dart';
import 'package:flutter_application_2/util/DownloadManager.dart';
import 'package:flutter_application_2/util/ReveAudioHandler.dart';
import 'package:flutter_application_2/util/SpUtils.dart';
import 'package:flutter_application_2/util/TokenAutoRefresh.dart';
import 'package:flutter_application_2/util/UploadManager.dart';
import 'package:flutter_application_2/util/WorkflowTaskManager.dart';
import 'package:flutter_smart_dialog/src/init_dialog.dart';
import 'package:flutter_application_2/page/tools/customToast.dart';
import 'package:flutter_application_2/util/AppCache.dart';
import 'package:flutter_application_2/page/login/login.dart';
import 'package:flutter_application_2/page/login/users.dart';
import 'package:flutter_application_2/handler/AppExceptionHandle.dart';
import 'package:audio_service/audio_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 音频后台播放：注册系统媒体通知栏（Android 前台服务 / iOS 后台音频），
  // 通知栏按钮由 ReveAudioHandler 自定义（仅上一曲/播放暂停/下一曲）
  ReveAudioHandler.instance = (await AudioService.init(
    builder: () => ReveAudioHandler(),
    config: AudioServiceConfig(
      androidNotificationChannelId: 'com.example.flutter_application_2.audio',
      androidNotificationChannelName: '音乐播放',
      androidNotificationOngoing: true,
    ),
  )) as ReveAudioHandler;
  var isLogin = await SpUtils.getBool("isLogin");
  // 缓存超阈值自动淘汰最旧文件（后台执行，不阻塞启动）
  AppCache.evictIfOverflow();
  // 恢复本地持久化的上传 / 下载任务记录
  DownloadManager.instance.restore();
  UploadManager.instance.restore();
  // 恢复服务器端后台任务跟踪（压缩 / 解压，App 重启后继续提示结果）
  WorkflowTaskManager.instance.restore();
  // 已登录时启动 token 定时自动刷新，保证会话长效在线
  if (isLogin) TokenAutoRefresh.instance.start();
  AppExceptionHandle().run(MyApp(
    isLogin: isLogin,
  ));
}

class MyApp extends StatefulWidget {
  final bool isLogin;

  const MyApp({super.key, required this.isLogin});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  late ThemeMode _mode = ThemeMode.light;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 恢复本地主题模式
    ThemeController.load().then((_) {
      _mode = ThemeController.mode.value;
      if (mounted) setState(() {});
    });
    ThemeController.mode.addListener(_onThemeChanged);
  }

  void _onThemeChanged() {
    if (mounted) setState(() => _mode = ThemeController.mode.value);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 回到前台时立即检查 token 状态，弥补后台暂停定时器导致的过期
    if (state == AppLifecycleState.resumed) {
      TokenAutoRefresh.instance.refreshIfNeeded();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ThemeController.mode.removeListener(_onThemeChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final smartBuilder = FlutterSmartDialog.init(
      toastBuilder: (String msg) => CustomToast(msg),
    );
    return MaterialApp(
      title: 'FlutterReve',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: _mode,
      initialRoute: widget.isLogin ? "/" : "/home",
      routes: {
        "/": (context) => Bottom(),
        "/login": (context) => Login(),
        "/home": (context) => Login(),
        "/users": (context) => Users(),
      },
      navigatorObservers: [FlutterSmartDialog.observer],
      // 同步深浅色标志到静态调色板
      builder: (context, child) {
        AppColors.dark = Theme.of(context).brightness == Brightness.dark;
        // 状态栏透明化，随深浅主题切换图标亮度（移除系统默认黑色遮罩）
        final overlay = SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness:
              AppColors.dark ? Brightness.light : Brightness.dark,
          statusBarBrightness:
              AppColors.dark ? Brightness.dark : Brightness.light,
        );
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: overlay,
          child: smartBuilder(context, child),
        );
      },
    );
  }
}
