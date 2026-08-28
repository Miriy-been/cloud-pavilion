import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloudpavilion/config/AppTheme.dart';
import 'package:cloudpavilion/config/ThemeController.dart';
import 'package:cloudpavilion/page/index/bottomBar.dart';
import 'package:cloudpavilion/util/DownloadManager.dart';
import 'package:cloudpavilion/util/DioUtil.dart';
import 'package:cloudpavilion/util/ReveAudioHandler.dart';
import 'package:cloudpavilion/util/SpUtils.dart';
import 'package:cloudpavilion/util/TokenAutoRefresh.dart';
import 'package:cloudpavilion/util/UploadManager.dart';
import 'package:cloudpavilion/util/WorkflowTaskManager.dart';
import 'package:flutter_smart_dialog/src/init_dialog.dart';
import 'package:cloudpavilion/page/tools/customToast.dart';
import 'package:cloudpavilion/util/AppCache.dart';
import 'package:cloudpavilion/util/AuthState.dart';
import 'package:cloudpavilion/page/login/login.dart';
import 'package:cloudpavilion/page/login/users.dart';
import 'package:cloudpavilion/handler/AppExceptionHandle.dart';
import 'package:audio_service/audio_service.dart';

void main() {
  // 首次 ensureInitialized 须与应用根 Widget 的 runApp 处于同一 zone，
  // 由 AppExceptionHandle 在 runZonedGuarded 内统一处理（见其 run()）
  AppExceptionHandle().run(bootstrap);
}

/// 异步启动流程：初始化各插件/本地状态后返回要 runApp 的根 Widget。
Future<Widget> bootstrap() async {
  // 音频后台播放：注册系统媒体通知栏（Android 前台服务 / iOS 后台音频），
  // 通知栏按钮由 ReveAudioHandler 自定义（仅上一曲/播放暂停/下一曲）
  ReveAudioHandler.instance = (await AudioService.init(
    builder: () => ReveAudioHandler(),
    config: AudioServiceConfig(
      androidNotificationChannelId: 'com.cloudpavilion.app.audio',
      androidNotificationChannelName: '音乐播放',
      androidNotificationOngoing: true,
    ),
  )) as ReveAudioHandler;
  var isLogin = await SpUtils.getBool("isLogin");
  // 同步初始登录态到全局守卫（未登录进登录页，已登录进主界面）
  AuthState.isLoggedIn.value = isLogin;
  // 恢复已确认的 ModelScope 网关站点：首个请求即跳过 Authorization，避免冷启动 403
  await DioUtil.bootModelScopeSites();
  // 缓存超阈值自动淘汰最旧文件（后台执行，不阻塞启动）
  AppCache.evictIfOverflow();
  // 恢复本地持久化的上传 / 下载任务记录
  DownloadManager.instance.restore();
  UploadManager.instance.restore();
  // 恢复服务器端后台任务跟踪（压缩 / 解压，App 重启后继续提示结果）
  WorkflowTaskManager.instance.restore();
  // 已登录时启动 token 定时自动刷新，保证会话长效在线
  if (isLogin) TokenAutoRefresh.instance.start();
  return MyApp(
    isLogin: isLogin,
  );
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
    // 首帧后设置 Android 多任务卡片显示应用正式名称「云阁」（非阻塞，
    // 不放在 main() 中 await，避免平台通道未就绪导致启动卡在首帧；
    // 个别机型/系统不实现该方法会返回平台错误，属非关键装饰性调用，静默忽略，
    // 否则未捕获异常会被 AppExceptionHandle 兜底成「系统错误」toast）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SystemChrome.setApplicationSwitcherDescription(
              const ApplicationSwitcherDescription(label: '云阁'))
          .catchError((Object _) {
        // 平台错误忽略，不影响使用
      });
    });
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
      title: '云阁',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: _mode,
      initialRoute: widget.isLogin ? "/" : "/home",
      routes: {
        // 根路由走登录态守卫：未登录时强制显示登录页
        "/": (context) => const AuthGate(),
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

/// 根路由登录态守卫：登录时显示主界面（底部导航），未登录时显示登录页。
///
/// 监听 [AuthState.isLoggedIn]：token 刷新失败 / 登出 / 改密等任何导致
/// 登录态丢失的路径，都会立即把主界面替换为登录页，
/// 避免未登录仍停留在存储/分类等内部页面。
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AuthState.isLoggedIn,
      builder: (context, _) {
        return AuthState.isLoggedIn.value ? Bottom() : Login();
      },
    );
  }
}
