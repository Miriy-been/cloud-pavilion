import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:cloudpavilion/exception/BusinessException.dart';
import 'package:cloudpavilion/exception/NotLoginException.dart';
import 'package:cloudpavilion/util/ErrorText.dart';
import 'package:cloudpavilion/util/AuthState.dart';
import 'package:cloudpavilion/util/TokenAutoRefresh.dart';
import 'package:cloudpavilion/util/TokenManager.dart';
import 'package:flutter_smart_dialog/src/smart_dialog.dart';
import '../exception/DebugReportException.dart';
import 'package:dio/dio.dart';
import '../util/SpUtils.dart';

//全局异常的捕捉
class AppExceptionHandle {
  /// [buildApp]：异步构建 App 的启动函数（含各插件/本地状态初始化），最终返回要 runApp 的根 Widget。
  /// 必须在与 [WidgetsFlutterBinding.ensureInitialized] 相同的 zone 内调用 runApp，
  /// 否则会触发 `Zone mismatch` 断言（debug 每次启动打印错误，release 下被兜底成
  /// 「系统错误」toast）。因此这里在 runZonedGuarded 的 zone 内先 ensureInitialized 再 runApp。
  run(FutureOr<Widget> Function() buildApp) {
    ///Flutter 框架异常
    FlutterError.onError = (FlutterErrorDetails details) async {
      ///线上环境
      if (kReleaseMode) {
        Zone.current.handleUncaughtError(details.exception, details.stack!);
      } else {
        //开发期间 print
        FlutterError.dumpErrorToConsole(details);
      }
    };

    runZonedGuarded(() async {
      WidgetsFlutterBinding.ensureInitialized();
      final app = await buildApp();
      runApp(app);
    }, (error, stack) => {catchError(error, stack)});
  }

  ///对搜集的 异常进行处理  上报等等
  catchError(Object error, StackTrace stack) {
    // Vibration.vibrate(duration: 1000);
    if (error is DebugReportException) {
      SmartDialog.showToast(error.message);
    } else if (error is NotLoginException) {
      // 登录过期：清除凭据并同步全局登录态，让根路由守卫切回登录页。
      // 仅 clear() 而不改 AuthState / isLogin 会让 UI 停留在已登录的
      // 内部页面，用户能看到界面但所有请求都在失败。
      TokenManager.clear();
      SpUtils.setBool('isLogin', false);
      AuthState.isLoggedIn.value = false;
      TokenAutoRefresh.instance.stop();
      SmartDialog.showToast("登录已过期,请重新登录");
    } else if (error is DioException) {
      // 统一走 errorText：与各页面局部提示使用同一套文案与中文化规则
      SmartDialog.showToast(errorText(error, '请求失败'));
    } else if (error is BusinessException) {
      SmartDialog.showToast(errorText(error, '请求失败'));
    } else {
      // 未知异常：不向用户抛技术细节，但仍打印栈便于排查
      SmartDialog.showToast(errorText(error, '系统错误'));
      debugPrint(stack.toString());
    }
  }
}
