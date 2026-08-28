import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:cloudpavilion/exception/NotLoginException.dart';
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
    } else if (error is FormatException) {
      SmartDialog.showToast(error.message);
    } else if (error is NotLoginException) {
      // 登录过期
      TokenManager.clear();
      SmartDialog.showToast("登录已过期,请重新登录");
    } else if (error is DioException) {
      final resp = error.response;
      if (resp != null) {
        // 显示服务器返回的具体错误信息
        final body = resp.data;
        if (body is Map && body['msg'] != null && body['msg'].toString().isNotEmpty) {
          SmartDialog.showToast(body['msg'].toString());
        } else if (body is String && body.isNotEmpty) {
          SmartDialog.showToast(body);
        } else {
          SmartDialog.showToast('请求失败 (${resp.statusCode})');
        }
      } else if (error.type == DioExceptionType.unknown) {
        SmartDialog.showToast('网络连接失败，请检查网络后重试');
      } else if (error.type == DioExceptionType.connectionTimeout) {
        SmartDialog.showToast('${error.type.name} 连接超时');
      } else {
        SmartDialog.showToast(error.type.name);
      }
    } else {
      SmartDialog.showToast("系统错误");
      print(stack);
    }
  }
}
