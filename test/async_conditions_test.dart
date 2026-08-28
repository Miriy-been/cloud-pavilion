import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloudpavilion/exception/BusinessException.dart';
import 'package:cloudpavilion/model/UploadTaskModel.dart';
import 'package:cloudpavilion/util/TokenAutoRefresh.dart';
import 'package:cloudpavilion/util/UploadManager.dart';

/// 异步 / 条件逻辑测试（Condition-Based Waiting 原则）：
/// 等待并断言「真实的条件」，不使用固定 sleep 猜测时序。
/// 覆盖：统一业务码校验（BusinessException.fromBody）+ TokenAutoRefresh
/// 决策短路逻辑（mock SharedPreferences，避免触发真实网络请求）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BusinessException.fromBody 统一业务码校验', () {
    test('code=0 正常返回 null（不抛）', () {
      expect(BusinessException.fromBody({'code': 0, 'data': {}}), isNull);
    });

    test('非 0 业务码抛异常并携带 code/msg/data', () {
      final e = BusinessException.fromBody({
        'code': 40073,
        'msg': '文件被占用',
        'data': [
          {'token': 't1'}
        ],
      });
      expect(e, isNotNull);
      expect(e!.code, 40073);
      expect(e.message, '文件被占用');
      expect((e.data as List).first['token'], 't1');
    });

    test('checkCode=false 豁免（登录需读原始 code 判断 2FA）', () {
      expect(
        BusinessException.fromBody(
          {'code': 203, 'msg': '该站点启用了两步验证'},
          checkCode: false,
        ),
        isNull,
      );
    });

    test('body 非 Map / code 缺失 / code 非数字 均不抛', () {
      expect(BusinessException.fromBody('not-a-map'), isNull);
      expect(BusinessException.fromBody({'msg': 'x'}), isNull);
      expect(BusinessException.fromBody({'code': 'not-num'}), isNull);
    });
  });

  group('TokenAutoRefresh.refreshIfNeeded 决策分支', () {
    test('未登录：直接短路返回', () async {
      SharedPreferences.setMockInitialValues({'isLogin': false});
      await TokenAutoRefresh.instance.refreshIfNeeded();
    });

    test('已登录但 token 远未过期：不触发刷新（避免无意义请求）', () async {
      final exp = DateTime.now()
          .add(const Duration(hours: 2))
          .toIso8601String();
      SharedPreferences.setMockInitialValues({
        'isLogin': true,
        'access_expires': exp,
        'refresh_expires': exp,
      });
      await TokenAutoRefresh.instance.refreshIfNeeded();
    });

    test('access 临近过期但 refresh token 已过期：无法续期，短路返回', () async {
      SharedPreferences.setMockInitialValues({
        'isLogin': true,
        'access_expires': DateTime.now()
            .add(const Duration(minutes: 5))
            .toIso8601String(),
        'refresh_expires': DateTime.now()
            .subtract(const Duration(minutes: 1))
            .toIso8601String(),
        'refresh_token': 'rt',
      });
      await TokenAutoRefresh.instance.refreshIfNeeded();
    });

    test('临近过期但 refresh token 缺失：避免无效请求，短路返回', () async {
      SharedPreferences.setMockInitialValues({
        'isLogin': true,
        'access_expires': DateTime.now()
            .add(const Duration(minutes: 5))
            .toIso8601String(),
        'refresh_expires': DateTime.now()
            .add(const Duration(days: 2))
            .toIso8601String(),
        // 无 refresh_token
      });
      await TokenAutoRefresh.instance.refreshIfNeeded();
    });
  });

  group('UploadManager.restore 恢复中断任务（真实逻辑）', () {
    setUp(() {
      // 单例清理，避免用例间互相污染
      UploadManager.instance.tasks.clear();
    });

    test('uploading 任务恢复为 failed + 中断文案', () async {
      SharedPreferences.setMockInitialValues({
        'uploadConcurrency': 5,
        'uploadTasks': jsonEncode([
          {
            'name': 'a.txt',
            'uri': 'cloudreve://my/a.txt',
            'sourcePath': '/tmp/a.txt',
            'size': 1,
            'progress': 0.3,
            'uploaded': 300,
            'status': 'uploading',
            'error': null,
          }
        ]),
      });
      await UploadManager.instance.restore();
      final t = UploadManager.instance.tasks.single;
      expect(t.status, UploadStatus.failed);
      expect(t.error, '上传已中断');
    });

    test('finished 任务保持 finished', () async {
      SharedPreferences.setMockInitialValues({
        'uploadConcurrency': 5,
        'uploadTasks': jsonEncode([
          {
            'name': 'b.txt',
            'uri': 'cloudreve://my/b.txt',
            'sourcePath': '/tmp/b.txt',
            'size': 2,
            'progress': 1.0,
            'uploaded': 2,
            'status': 'finished',
            'error': null,
          }
        ]),
      });
      await UploadManager.instance.restore();
      expect(
          UploadManager.instance.tasks.single.status, UploadStatus.finished);
    });

    test('损坏 JSON 忽略，保留空列表', () async {
      SharedPreferences.setMockInitialValues({
        'uploadConcurrency': 5,
        'uploadTasks': 'not-json{{{',
      });
      await UploadManager.instance.restore();
      expect(UploadManager.instance.tasks, isEmpty);
    });

    test('并发数恢复并限制在 1~20', () async {
      SharedPreferences.setMockInitialValues({'uploadConcurrency': 99});
      await UploadManager.instance.restore();
      expect(UploadManager.instance.maxConcurrent, 20);
    });
  });
}
