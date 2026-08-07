import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:cloudpavilion/exception/NotLoginException.dart';
import 'package:cloudpavilion/util/AuthState.dart';
import './SpUtils.dart';
import './TokenManager.dart';

/// 请求方法
enum DioMethod {
  get,
  post,
  put,
  delete,
  patch,
  head,
}

class DioUtil {
  /// 单例模式
  static DioUtil? _instance;

  /// Dio实例
  static Dio _dio = Dio();

  /// 刷新 token 的并发锁
  static Future<void>? _refreshing;

  factory DioUtil() => _instance ?? DioUtil._internal();

  static DioUtil? get instance => _instance ?? DioUtil._internal();

  /// 连接超时时间
  static const Duration connectTimeout = Duration(milliseconds: 3 * 1000);

  /// 响应超时时间
  static const Duration receiveTimeout = Duration(milliseconds: 60 * 1000);

  /// 标准认证头（Cloudreve 默认读取，Bearer 前缀必须有）
  static const String authHeaderName = 'Authorization';
  /// 兼容自定义认证头：部分自建站点把认证头改成了 X-Cloudreve-Token，
  /// 两个头同时携带，服务端按自己读取的那个认证即可
  static const String altAuthHeaderName = 'X-Cloudreve-Token';

  /// 初始化
  DioUtil._internal() {
    _instance = this;
    BaseOptions options = BaseOptions(
        baseUrl: 'http://127.0.0.1:5212',
        connectTimeout: connectTimeout,
        receiveTimeout: receiveTimeout);
    _dio = Dio(options);
    _dio.interceptors.add(InterceptorsWrapper(
        onRequest: _onRequest, onResponse: _onResponse, onError: _onError));
  }

  /// 请求拦截器
  void _onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    // 切换到当前站点
    final baseUrl = await SpUtils.getString('CurrentBaseUrl');
    if (baseUrl.isNotEmpty) {
      options.baseUrl = baseUrl;
    }
    // 主动刷新（对齐网页版）：请求发出前检查 access token 是否已过期/即将过期，
    // 过期则先刷新再发送，避免把过期 token 发给服务器被降级成匿名。
    // 登录/刷新接口自身不走此逻辑，防止递归。
    if (!options.path.contains('/session/token')) {
      try {
        if (await TokenManager.isAccessTokenExpired() &&
            await SpUtils.getBool('isLogin')) {
          await refreshTokenNow();
        }
      } catch (_) {
        // 刷新失败不阻塞请求，交由 401 错误处理兜底（失败最终会走登出流程）
      }
    }
    // 添加认证头（登录/刷新接口无需携带，对齐网页版 noCredential）
    final isTokenEndpoint = options.path.contains('/session/token');
    final token = await TokenManager.getAccessToken();
    if (token.isNotEmpty && !isTokenEndpoint) {
      options.headers[authHeaderName] = 'Bearer $token';
      options.headers[altAuthHeaderName] = 'Bearer $token';
    }
    handler.next(options);
  }

  /// 响应拦截器
  void _onResponse(
      Response response, ResponseInterceptorHandler handler) async {
    // 业务码 401 视为未登录：转入错误流统一处理（与 HTTP 401 一致的刷新逻辑），
    // 避免在拦截器内直接 throw 被 Dio 包装成 unknown 类型而丢失响应信息
    if (response.data is Map && response.data['code'] == 401) {
      handler.reject(
        DioException(
          requestOptions: response.requestOptions,
          response: response,
          type: DioExceptionType.badResponse,
          message: '未登录',
        ),
      );
      return;
    }
    handler.next(response);
  }

  /// 错误处理：HTTP 401 或业务码 401 时自动刷新 token 并重放请求
  void _onError(DioException error, ErrorInterceptorHandler handler) {
    // 联调日志：打印失败请求的完整信息
    debugPrint('Dio错误: ${error.requestOptions.method} '
        '${error.requestOptions.uri} '
        '-> ${error.response?.statusCode} ${error.response?.data}');
    final resp = error.response;
    final isAuthExpired = resp?.statusCode == 401 ||
        (resp?.data is Map && resp?.data['code'] == 401);
    final isTokenEndpoint =
        error.requestOptions.path.contains('/session/token');
    if (isAuthExpired && !isTokenEndpoint) {
      _retryWithRefresh(error, handler);
    } else {
      handler.next(error);
    }
  }

  /// 刷新 token 后重放原请求
  Future<void> _retryWithRefresh(
      DioException error, ErrorInterceptorHandler handler) async {
    // 记录发起刷新时的账号上下文；刷新期间若账号已切换（切号/改密/登出），
    // 则丢弃刷新结果与重放，避免旧账号 token 污染新账号上下文
    final reqUrl = await SpUtils.getString('CurrentBaseUrl');
    final reqUser = await SpUtils.getString('currentUserName');
    try {
      _refreshing ??= _doRefresh();
      await _refreshing;
    } catch (e) {
      // 刷新失败：仅当账号未变化时才清理登录态，避免误登出新账号
      final curUrl = await SpUtils.getString('CurrentBaseUrl');
      final curUser = await SpUtils.getString('currentUserName');
      if (curUrl == reqUrl && curUser == reqUser) {
        await TokenManager.clear();
        await SpUtils.setBool('isLogin', false);
        // 通知全局守卫切回登录页，避免未登录仍停留在内部页面
        AuthState.isLoggedIn.value = false;
      }
      handler.next(error);
      return;
    } finally {
      _refreshing = null;
    }
    // 账号已切换：原请求不属于当前上下文，丢弃重放
    final curUrl = await SpUtils.getString('CurrentBaseUrl');
    final curUser = await SpUtils.getString('currentUserName');
    if (curUrl != reqUrl || curUser != reqUser) {
      handler.next(error);
      return;
    }
    // 用新 token 重放原请求
    final token = await TokenManager.getAccessToken();
    error.requestOptions.headers[authHeaderName] = 'Bearer $token';
    error.requestOptions.headers[altAuthHeaderName] = 'Bearer $token';
    try {
      final response = await _dio.fetch(error.requestOptions);
      handler.resolve(response);
    } on DioException catch (e) {
      handler.next(e);
    }
  }

  /// 立即刷新 token（供定时任务调用，与 401 重试共用并发锁）
  Future<void> refreshTokenNow() {
    _refreshing ??= _doRefresh();
    return _refreshing!.whenComplete(() => _refreshing = null);
  }

  /// 调用刷新接口获取新的 token 对
  Future<void> _doRefresh() async {
    final refreshToken = await TokenManager.getRefreshToken();
    if (refreshToken.isEmpty) {
      throw NotLoginException("refresh token 不存在");
    }
    final baseUrl = await SpUtils.getString('CurrentBaseUrl');
    final userName = await SpUtils.getString('currentUserName');
    final response = await _dio.post(
      '$baseUrl/api/v4/session/token/refresh',
      data: {'refresh_token': refreshToken},
    );
    final body = response.data;
    if (body is! Map || body['code'] != 0) {
      throw NotLoginException("刷新 token 失败");
    }
    final data = body['data'] as Map<String, dynamic>;
    // 刷新期间账号可能已切换/登出（切号、改密、退出登录）：
    // 丢弃旧账号的刷新结果，避免覆盖新账号 token 上下文
    final curUrl = await SpUtils.getString('CurrentBaseUrl');
    final curUser = await SpUtils.getString('currentUserName');
    if (curUrl != baseUrl ||
        curUser != userName ||
        !(await SpUtils.getBool('isLogin'))) {
      return;
    }
    await TokenManager.saveTokens(
      accessToken: data['access_token'] as String,
      refreshToken: data['refresh_token'] as String,
      accessExpires: DateTime.parse(data['access_expires'] as String),
      refreshExpires: DateTime.parse(data['refresh_expires'] as String),
    );
    // 同步更新本地账号快照（accounts）中的 token，
    // 否则切换账号时仍会用旧快照 token，导致登录态失效
    await _syncAccountSnapshot(data);
  }

  /// 将刷新得到的新 token 写回 accounts 快照（当前账号）
  Future<void> _syncAccountSnapshot(Map<String, dynamic> data) async {
    final siteUrl = await SpUtils.getString('CurrentBaseUrl');
    final userName = await SpUtils.getString('currentUserName');
    if (siteUrl.isEmpty || userName.isEmpty) return;
    final list = await SpUtils.getStringList('accounts');
    if (list.isEmpty) return;
    final token = {
      'access_token': data['access_token'],
      'refresh_token': data['refresh_token'],
      'access_expires': data['access_expires'],
      'refresh_expires': data['refresh_expires'],
    };
    final updated = <String>[];
    for (final raw in list) {
      try {
        final jsonData = jsonDecode(raw) as Map<String, dynamic>;
        if (jsonData['siteUrl'] == siteUrl &&
            jsonData['userName'] == userName) {
          jsonData['token'] = token;
          updated.add(jsonEncode(jsonData));
          continue;
        }
      } catch (_) {}
      updated.add(raw);
    }
    await SpUtils.setStringList('accounts', updated);
  }

  /// 请求类
  Future<T> request<T>(
    String path, {
    DioMethod method = DioMethod.get,
    Map<String, dynamic>? params,
    data,
    CancelToken? cancelToken,
    Options? options,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    const _methodValues = {
      DioMethod.get: 'get',
      DioMethod.post: 'post',
      DioMethod.put: 'put',
      DioMethod.delete: 'delete',
      DioMethod.patch: 'patch',
      DioMethod.head: 'head'
    };
    options ??= Options();
    // 必须始终设置 method：调用方传入自定义 Options 时可能未携带 method
    options.method = _methodValues[method];
    try {
      Response response;
      response = await _dio.request(path,
          data: data,
          queryParameters: params,
          cancelToken: cancelToken,
          options: options,
          onSendProgress: onSendProgress,
          onReceiveProgress: onReceiveProgress);
      return response.data;
    } on DioException catch (e) {
      rethrow;
    }
  }

  /// 开启日志打印
  /// 需要打印日志的接口在接口请求前 DioUtil.instance?.openLog();
  void openLog() {
    _dio.interceptors
        .add(LogInterceptor(responseHeader: false, responseBody: true));
  }
}
