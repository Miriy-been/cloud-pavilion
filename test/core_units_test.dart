import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:cloudpavilion/api/FileApi.dart';
import 'package:cloudpavilion/model/DownloadTaskModel.dart';
import 'package:cloudpavilion/model/FileListPage.dart';
import 'package:cloudpavilion/model/UploadTaskModel.dart';
import 'package:cloudpavilion/util/AppCache.dart';
import 'package:cloudpavilion/util/ErrorText.dart';

/// 核心纯逻辑单元测试：任务模型序列化容错 + 失败提示中文化。
/// 覆盖上传/下载任务持久化恢复（restore）与删除/上传/下载失败提示链路，
/// 防止「静默成功」「恢复后状态异常」等回归。
void main() {
  group('ErrorText 失败提示中文化', () {
    test('服务端 msg「Object existed」映射为「目标位置已存在同名文件」', () {
      final opts = RequestOptions(path: '/api/v4/file/upload');
      final e = DioException(
        requestOptions: opts,
        response: Response(
          requestOptions: opts,
          statusCode: 200,
          data: {'code': 40005, 'msg': 'Object existed'},
        ),
      );
      expect(errorText(e, '网络错误'), '目标位置已存在同名文件');
    });

    test('连接超时映射为「网络超时」', () {
      final e = DioException(
        type: DioExceptionType.connectionTimeout,
        requestOptions: RequestOptions(path: '/api'),
      );
      expect(errorText(e, '网络错误'), '网络超时');
    });

    test('普通 Exception 去除 Exception: 前缀', () {
      expect(errorText(Exception('上传已中断'), '未知错误'), '上传已中断');
    });

    test('空 msg 回退到兜底文案', () {
      // Exception('') 的 toString 去前缀后为空，应回退 fallback
      expect(errorText(Exception(''), '未知错误'), '未知错误');
    });
  });

  group('UploadTaskModel 序列化', () {
    test('toJson → fromJson 往返保持字段一致', () {
      final t = UploadTaskModel(
        name: 'a.txt',
        uri: 'cloudreve://my/a.txt',
        sourcePath: '/tmp/a.txt',
        size: 1024,
      )
        ..progress = 0.5
        ..uploaded = 512
        ..speed = 100
        ..status = UploadStatus.failed
        ..error = '上传已中断';
      final restored = UploadTaskModel.fromJson(t.toJson());
      expect(restored.name, 'a.txt');
      expect(restored.uri, 'cloudreve://my/a.txt');
      expect(restored.sourcePath, '/tmp/a.txt');
      expect(restored.size, 1024);
      expect(restored.progress, 0.5);
      expect(restored.uploaded, 512);
      expect(restored.status, UploadStatus.failed);
      expect(restored.error, '上传已中断');
    });

    test('缺字段 / 非法状态容错不崩溃', () {
      final t = UploadTaskModel.fromJson(<String, dynamic>{});
      expect(t.name, '');
      expect(t.uri, '');
      expect(t.size, 0);
      expect(t.progress, 0);
      // 未知 / 缺失状态兜底为 failed（restore 时未完成任务按失败处理）
      expect(t.status, UploadStatus.failed);
    });
  });

  group('DownloadTaskModel 序列化', () {
    test('toJson → fromJson 往返保持字段一致', () {
      final t = DownloadTaskModel(
        name: 'b.zip',
        savePath: '/x/b.zip',
        sourceUrl: 'http://u/b.zip',
        systemDownloads: true,
      )
        ..totalSize = 2048
        ..progress = 1
        ..downloaded = 2048
        ..status = DownloadStatus.finished;
      final restored = DownloadTaskModel.fromJson(t.toJson());
      expect(restored.name, 'b.zip');
      expect(restored.savePath, '/x/b.zip');
      expect(restored.sourceUrl, 'http://u/b.zip');
      expect(restored.systemDownloads, true);
      expect(restored.totalSize, 2048);
      expect(restored.progress, 1);
      expect(restored.downloaded, 2048);
      expect(restored.status, DownloadStatus.finished);
    });

    test('缺字段容错不崩溃', () {
      final t = DownloadTaskModel.fromJson(<String, dynamic>{});
      expect(t.name, '');
      expect(t.sourceUrl, '');
      expect(t.totalSize, 0);
      expect(t.progress, 0);
      expect(t.status, DownloadStatus.failed);
    });
  });

  group('FileListPage 分页解析', () {
    test('游标分页：取 next_token 且 hasMore 为 true', () {
      final page = FileListPage.fromData({
        'files': [
          {'type': 0, 'name': 'a.txt', 'path': 'cloudreve://my/a.txt'},
        ],
        'pagination': {'page': 0, 'page_size': 100, 'next_token': 'tok'},
      });
      expect(page.items.length, 1);
      expect(page.nextToken, 'tok');
      expect(page.hasMore, isTrue);
    });

    test('末页：next_token 为空且无总数时 hasMore 为 false', () {
      final page = FileListPage.fromData({
        'files': [
          {'type': 0, 'name': 'a.txt', 'path': 'cloudreve://my/a.txt'},
        ],
        'pagination': {'page': 0, 'page_size': 100},
      });
      expect(page.nextToken, '');
      expect(page.hasMore, isFalse);
    });

    test('偏移分页回退：已加载数小于 total_items 时仍有下一页', () {
      final page = FileListPage.fromData({
        'files': [
          {'type': 0, 'name': 'a.txt', 'path': 'cloudreve://my/a.txt'},
        ],
        'pagination': {'total_items': 10},
      }, loadedBefore: 3);
      expect(page.loaded, 4);
      expect(page.hasMore, isTrue);
    });

    test('偏移分页回退：已加载数达到 total_items 时判定末页', () {
      final page = FileListPage.fromData({
        'files': [
          {'type': 0, 'name': 'a.txt', 'path': 'cloudreve://my/a.txt'},
        ],
        'pagination': {'total_items': 4},
      }, loadedBefore: 3);
      expect(page.hasMore, isFalse);
    });

    test('缺 pagination / files 非列表时不崩溃', () {
      expect(FileListPage.fromData(<String, dynamic>{}).items, isEmpty);
      final page = FileListPage.fromData({'files': 'oops'});
      expect(page.items, isEmpty);
      expect(page.hasMore, isFalse);
    });
  });

  group('FileApi 直链缓存过期校验', () {
    setUp(FileApi.clearUrlCacheForTest);

    test('未过期的缓存直接命中', () {
      final future = DateTime.now()
          .add(const Duration(hours: 1))
          .millisecondsSinceEpoch;
      FileApi.writeUrlCacheForTest('k1', 'http://a/1', future);
      expect(FileApi.readUrlCacheForTest('k1'), 'http://a/1');
    });

    test('已过期的缓存返回 null（不能把失效直链交给播放器/下载器）', () {
      final past =
          DateTime.now().subtract(const Duration(minutes: 1)).millisecondsSinceEpoch;
      FileApi.writeUrlCacheForTest('k2', 'http://a/2', past);
      expect(FileApi.readUrlCacheForTest('k2'), isNull);
    });

    test('读到过期项后立即清除，避免反复命中', () {
      final past =
          DateTime.now().subtract(const Duration(minutes: 1)).millisecondsSinceEpoch;
      FileApi.writeUrlCacheForTest('k3', 'http://a/3', past);
      FileApi.readUrlCacheForTest('k3');
      // 清除后即使把系统时间相关的判断绕开，也不应再返回旧值
      expect(FileApi.readUrlCacheForTest('k3'), isNull);
    });

    test('未写入的 key 返回 null', () {
      expect(FileApi.readUrlCacheForTest('absent'), isNull);
    });
  });

  group('AppCache 活跃文件隔离', () {
    test('登记后同一路径被识别为活跃（含分隔符归一）', () {
      AppCache.markActive(r'C:\tmp\a.bin');
      expect(AppCache.isActiveForTest(r'C:\tmp\a.bin'), isTrue);
      // Windows 反斜杠与正斜杠应视为同一文件
      expect(AppCache.isActiveForTest('C:/tmp/a.bin'), isTrue);
      AppCache.unmarkActive(r'C:\tmp\a.bin');
    });

    test('注销后不再视为活跃（下载结束可被正常清理）', () {
      AppCache.markActive('/tmp/b.bin');
      AppCache.unmarkActive('/tmp/b.bin');
      expect(AppCache.isActiveForTest('/tmp/b.bin'), isFalse);
    });

    test('不同路径互不影响', () {
      AppCache.markActive('/tmp/c.bin');
      expect(AppCache.isActiveForTest('/tmp/d.bin'), isFalse);
      AppCache.unmarkActive('/tmp/c.bin');
    });
  });
}
