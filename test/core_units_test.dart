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

  group('UploadTaskModel 断点续传上下文', () {
    test('会话未过期时可续传', () {
      final t = UploadTaskModel(
        name: 'a.bin',
        uri: 'cloudreve://my/a.bin',
        sourcePath: '/tmp/a.bin',
        size: 100,
      )
        ..sessionId = 'sess-1'
        ..sessionExpiresAt =
            DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch
        ..chunkSize = 10
        ..uploadedChunks = [0, 1];
      expect(t.canResume, isTrue);
    });

    test('会话已过期时不可续传', () {
      final t = UploadTaskModel(
        name: 'a.bin',
        uri: 'cloudreve://my/a.bin',
        sourcePath: '/tmp/a.bin',
        size: 100,
      )
        ..sessionId = 'sess-1'
        ..sessionExpiresAt =
            DateTime.now().subtract(const Duration(hours: 1)).millisecondsSinceEpoch;
      expect(t.canResume, isFalse);
    });

    test('无 sessionId 时不可续传', () {
      final t = UploadTaskModel(
        name: 'a.bin',
        uri: 'cloudreve://my/a.bin',
        sourcePath: '/tmp/a.bin',
        size: 100,
      )..sessionExpiresAt = DateTime.now()
              .add(const Duration(hours: 1))
              .millisecondsSinceEpoch;
      expect(t.canResume, isFalse);
    });

    test('过期边缘（剩余不足 30 秒）视为不可续传', () {
      final t = UploadTaskModel(
        name: 'a.bin',
        uri: 'cloudreve://my/a.bin',
        sourcePath: '/tmp/a.bin',
        size: 100,
      )
        ..sessionId = 'sess-1'
        ..sessionExpiresAt =
            DateTime.now().add(const Duration(seconds: 10)).millisecondsSinceEpoch;
      expect(t.canResume, isFalse);
    });

    test('续传上下文可序列化往返（重启后仍能续传）', () {
      final t = UploadTaskModel(
        name: 'a.bin',
        uri: 'cloudreve://my/a.bin',
        sourcePath: '/tmp/a.bin',
        size: 100,
      )
        ..sessionId = 'sess-9'
        ..sessionExpiresAt =
            DateTime.now().add(const Duration(hours: 2)).millisecondsSinceEpoch
        ..chunkSize = 25
        ..uploadedChunks = [0, 2];
      final restored = UploadTaskModel.fromJson(t.toJson());
      expect(restored.sessionId, 'sess-9');
      expect(restored.chunkSize, 25);
      expect(restored.uploadedChunks, [0, 2]);
      expect(restored.canResume, isTrue);
    });

    test('clearResumeContext 清空全部续传字段', () {
      final t = UploadTaskModel(
        name: 'a.bin',
        uri: 'cloudreve://my/a.bin',
        sourcePath: '/tmp/a.bin',
        size: 100,
      )
        ..sessionId = 'sess-1'
        ..sessionExpiresAt = 1
        ..chunkSize = 10
        ..uploadedChunks = [0];
      t.clearResumeContext();
      expect(t.sessionId, isNull);
      expect(t.sessionExpiresAt, isNull);
      expect(t.uploadedChunks, isEmpty);
      expect(t.chunkSize, 0);
      expect(t.canResume, isFalse);
    });

    test('旧版本任务（无续传字段）可正常加载', () {
      final old = UploadTaskModel.fromJson({
        'name': 'old.bin',
        'uri': 'cloudreve://my/old.bin',
        'sourcePath': '/tmp/old.bin',
        'size': 10,
        'status': 'failed',
        'error': '上传已中断',
      });
      expect(old.sessionId, isNull);
      expect(old.uploadedChunks, isEmpty);
      expect(old.canResume, isFalse);
    });
  });

  group('DownloadTaskModel 断点续传判定', () {
    test('有直链 + 保存路径 + 已下载字节时可续传', () {
      final t = DownloadTaskModel(
        name: 'a.bin',
        savePath: '/tmp/a.bin',
        sourceUrl: 'https://x/a.bin',
      )..downloaded = 1024;
      expect(t.canResume, isTrue);
    });

    test('未下载任何字节时不可续传', () {
      final t = DownloadTaskModel(
        name: 'a.bin',
        savePath: '/tmp/a.bin',
        sourceUrl: 'https://x/a.bin',
      );
      expect(t.canResume, isFalse);
    });

    test('缺直链或保存路径时不可续传', () {
      final noUrl = DownloadTaskModel(
        name: 'a.bin',
        savePath: '/tmp/a.bin',
      )..downloaded = 10;
      expect(noUrl.canResume, isFalse);

      final noPath = DownloadTaskModel(
        name: 'a.bin',
        savePath: '',
        sourceUrl: 'https://x/a.bin',
      )..downloaded = 10;
      expect(noPath.canResume, isFalse);
    });

    test('downloaded 参与序列化往返（重启后可续传）', () {
      final t = DownloadTaskModel(
        name: 'a.bin',
        savePath: '/tmp/a.bin',
        sourceUrl: 'https://x/a.bin',
      )
        ..downloaded = 2048
        ..totalSize = 4096
        ..progress = 0.5;
      final r = DownloadTaskModel.fromJson(t.toJson());
      expect(r.downloaded, 2048);
      expect(r.canResume, isTrue);
    });

    test('sourceUri 参与序列化往返（重启后仍能显示缩略图）', () {
      final t = DownloadTaskModel(
        name: 'a.jpg',
        savePath: '/tmp/a.jpg',
        sourceUrl: 'https://x/a.jpg',
        sourceUri: 'cloudreve://my/a.jpg',
      );
      final r = DownloadTaskModel.fromJson(t.toJson());
      expect(r.sourceUri, 'cloudreve://my/a.jpg');
    });

    test('旧任务缺 sourceUri 时回落为空串（列表显示类型图标）', () {
      final r = DownloadTaskModel.fromJson({
        'name': 'old.bin',
        'savePath': '/tmp/old.bin',
      });
      expect(r.sourceUri, '');
    });
  });

  group('任务状态：暂停语义', () {
    test('上传暂停态可序列化并往返', () {
      final t = UploadTaskModel(
        name: 'a.bin',
        uri: 'cloudreve://my/a.bin',
        sourcePath: '/tmp/a.bin',
        size: 100,
      )..status = UploadStatus.paused;
      final r = UploadTaskModel.fromJson(t.toJson());
      expect(r.status, UploadStatus.paused);
    });

    test('下载暂停态可序列化并往返', () {
      final t = DownloadTaskModel(
        name: 'a.bin',
        savePath: '/tmp/a.bin',
      )..status = DownloadStatus.paused;
      final r = DownloadTaskModel.fromJson(t.toJson());
      expect(r.status, DownloadStatus.paused);
    });

    test('旧版 "cancelled" 数据回落为 failed（不做兼容映射）', () {
      final old = UploadTaskModel.fromJson({
        'name': 'old.bin',
        'status': 'cancelled',
      });
      expect(old.status, UploadStatus.failed);
    });

    test('暂停态不属于完成态，仍可继续', () {
      final t = UploadTaskModel(
        name: 'a.bin',
        uri: 'cloudreve://my/a.bin',
        sourcePath: '/tmp/a.bin',
        size: 100,
      )
        ..status = UploadStatus.paused
        ..sessionId = 's'
        ..sessionExpiresAt = DateTime.now()
            .add(const Duration(hours: 1))
            .millisecondsSinceEpoch
        ..chunkSize = 10
        ..uploadedChunks = [0]
        ..currentChunkSent = 5;
      expect(t.status, isNot(UploadStatus.finished));
      expect(t.canResume, isTrue);
      expect(t.resumeDisplayedBytes, 15);
    });

    test('暂停时展示的已传字节取分片累计', () {
      final t = UploadTaskModel(
        name: 'a.bin',
        uri: 'cloudreve://my/a.bin',
        sourcePath: '/tmp/a.bin',
        size: 100,
      )
        ..status = UploadStatus.paused
        ..chunkSize = 20
        ..uploadedChunks = [0, 1]
        ..currentChunkSent = 5;
      // 20 + 20 + 5
      expect(t.transferredBytes, 45);
    });

    test('无分片记账时回落到实时上报字节', () {
      final t = UploadTaskModel(
        name: 'a.bin',
        uri: 'cloudreve://my/a.bin',
        sourcePath: '/tmp/a.bin',
        size: 100,
      )..uploaded = 33;
      // chunkSize 为 0（不分片）时按 uploaded 展示
      expect(t.transferredBytes, 33);
    });
  });

  group('UploadTaskModel 片内进度', () {
    UploadTaskModel make() => UploadTaskModel(
          name: 'a.bin',
          uri: 'cloudreve://my/a.bin',
          sourcePath: '/tmp/a.bin',
          size: 100,
        )
          ..sessionId = 's'
          ..sessionExpiresAt = DateTime.now()
              .add(const Duration(hours: 1))
              .millisecondsSinceEpoch
          ..chunkSize = 30;

    test('已完成分片字节按片大小累计（含末片截断）', () {
      final t = make()..uploadedChunks = [0, 1];
      expect(t.completedChunksBytes, 60);
    });

    test('末片不足一个 chunk 时只计入实际长度', () {
      // size=100, chunk=30 → 分片 0..3，末片为 10 字节
      final t = make()..uploadedChunks = [0, 1, 2, 3];
      expect(t.completedChunksBytes, 100);
    });

    test('续传展示字节 = 已完成分片 + 本片已发', () {
      final t = make()
        ..uploadedChunks = [0]
        ..currentChunkSent = 15;
      expect(t.resumeDisplayedBytes, 45);
    });

    test('一片都没完成但本片有进度时，展示字节仍大于 0', () {
      // 这正是大分片（25MB）断网的场景：不能因为片未完成就判定无进展
      final t = make()
        ..uploadedChunks = []
        ..currentChunkSent = 17;
      expect(t.resumeDisplayedBytes, 17);
      expect(t.canResume, isTrue);
    });

    test('展示字节不会超过文件大小', () {
      final t = make()
        ..uploadedChunks = [0, 1, 2]
        ..currentChunkSent = 999;
      expect(t.resumeDisplayedBytes, 100);
    });

    test('currentChunkSent 参与序列化往返', () {
      final t = make()..currentChunkSent = 12;
      expect(UploadTaskModel.fromJson(t.toJson()).currentChunkSent, 12);
    });

    test('clearResumeContext 同时清零片内进度', () {
      final t = make()..currentChunkSent = 12;
      t.clearResumeContext();
      expect(t.currentChunkSent, 0);
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
