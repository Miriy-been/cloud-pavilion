import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_application_2/api/FileApi.dart';
import 'package:flutter_application_2/enums/FileType.dart';
import 'package:flutter_application_2/model/FileItemModel.dart';
import 'package:flutter_application_2/util/AppCache.dart';
import 'package:flutter_application_2/util/ReveAudioHandler.dart';
import 'package:just_audio/just_audio.dart';

/// 全局音频播放服务（单例）
///
/// 基于 just_audio + audio_service 实现：支持后台播放（锁屏/退出应用持续播放），
/// 系统媒体通知栏控制由 [ReveAudioHandler] 提供（上一曲/播放暂停/下一曲 + 可拖动进度条）。
///
/// 播放策略（与主流音乐 App 对齐，控制本地缓存与流量）：
/// - 纯流式播放（ProgressiveAudioSource）：不把整曲落盘，本地占用几乎不增长；
/// - 移动数据下跳过下一曲封面预下载，仅在 WiFi 下预热封面；
/// - 缩略图/封面等缓存超阈值时由 [AppCache] 自动淘汰最旧文件；
/// - 切歌不显示全屏加载动画，仅由 [buffering] 小菊花提示，界面保持稳定。
class AudioPlayerService extends ChangeNotifier {
  AudioPlayerService._() {
    _player = ReveAudioHandler.instance!.player;
    // 同步播放器状态到公开字段，通知 UI 刷新
    _player.currentIndexStream.listen(_onIndexChanged);
    _player.positionStream.listen((p) {
      if (p != position) {
        position = p;
        notifyListeners();
      }
    });
    _player.durationStream.listen((d) {
      final v = d ?? Duration.zero;
      if (v != duration) {
        duration = v;
        notifyListeners();
      }
    });
    _player.playerStateStream.listen((s) {
      if (s.playing != playing) {
        playing = s.playing;
        notifyListeners();
      }
      // 加载/缓冲中：播放页显示小菊花（不遮挡播放器界面）
      final buf = s.processingState == ProcessingState.loading ||
          s.processingState == ProcessingState.buffering;
      if (buf != buffering) {
        buffering = buf;
        notifyListeners();
      }
      if (s.processingState == ProcessingState.completed && playing) {
        playing = false;
        notifyListeners();
      }
    });
    // 监听网络类型：移动数据下跳过封面等非必要预加载，节省流量。
    // 单例生命周期与应用一致，订阅不取消（不保存引用）
    Connectivity().onConnectivityChanged.listen((results) {
      final wifi = results.any((r) => r == ConnectivityResult.wifi);
      if (wifi != _isWifi) {
        _isWifi = wifi;
        notifyListeners();
      }
    });
  }

  static final AudioPlayerService instance = AudioPlayerService._();

  late final AudioPlayer _player;
  List<FileItemModel> playlist = [];
  int currentIndex = -1;
  /// 首次加载 / 重建播放源（无内容时显示全屏加载）
  bool loading = false;
  /// 切歌 / 缓冲中（播放器界面保持，播放键位置显示小菊花）
  bool buffering = false;
  bool playing = false;
  double volume = 1.0;
  /// 循环模式：0=列表循环 1=单曲循环 2=关闭（默认列表循环，最后一首自动回到第一首）
  int loop = 0;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  String? error;

  /// 当前曲目媒体信息（播放页 / 通知栏展示）
  String? currentTitle;
  String? currentArtist;
  String? currentAlbum;
  String? currentCover;

  /// 全站音频库缓存（缩短重复进入播放页的等待）
  List<FileItemModel>? _libraryCache;
  DateTime? _libraryCacheAt;
  static const _cacheTtl = Duration(seconds: 60);
  int? _metaLoadingFor;

  /// 当前网络是否 WiFi（移动数据下跳过非必要预加载，节省流量）
  bool _isWifi = true;

  /// 缓存自动淘汰节流：避免高频触发遍历文件系统
  DateTime _lastEvictAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// 是否已有播放内容（顶部小图标据此显示）
  bool get isActive => playlist.isNotEmpty && currentIndex >= 0;

  String get currentName =>
      currentIndex >= 0 && currentIndex < playlist.length
          ? playlist[currentIndex].name
          : '';

  String get currentUri =>
      currentIndex >= 0 && currentIndex < playlist.length
          ? playlist[currentIndex].path
          : '';

  /// 用新播放列表开始播放
  Future<void> start(List<FileItemModel> list, int index) async {
    playlist = List.of(list);
    currentIndex = index.clamp(0, list.length - 1);
    await _buildAndPlay();
  }

  /// 从任意入口播放：播放列表统一为「全站音频库」（分类页音乐板块）。
  /// 定位到点击的歌曲开始播放；拉取失败时退化为单曲播放。
  Future<void> playFromLibrary(FileItemModel target) async {
    try {
      var audioList = _libraryCache;
      if (audioList == null ||
          _libraryCacheAt == null ||
          DateTime.now().difference(_libraryCacheAt!) > _cacheTtl) {
        final data = await FileApi.listFiles(
            '${FileApi.myRootUri}?category=audio',
            pageSize: 200);
        final files = data['files'];
        audioList = <FileItemModel>[];
        if (files is List) {
          for (final e in files) {
            final item = FileItemModel.fromJson(e as Map<String, dynamic>);
            if (FileType.isAudio(item.type, item.name)) audioList.add(item);
          }
        }
        _libraryCache = audioList;
        _libraryCacheAt = DateTime.now();
      }
      final idx = audioList.indexWhere((e) => e.path == target.path);
      if (audioList.isNotEmpty && idx >= 0) {
        // 目标歌曲已在当前播放列表（同一全站库）：直接 seek 秒切，不重建播放源
        if (playlist.isNotEmpty && _sameLibrary(playlist, audioList)) {
          await _seekTo(idx);
        } else {
          await start(audioList, idx);
        }
      } else if (audioList.isNotEmpty) {
        await start(audioList, 0);
      } else {
        await start([target], 0);
      }
    } catch (e) {
      await start([target], 0);
    }
  }

  /// 判断两个列表是否完全一致（同路径同顺序）
  bool _sameLibrary(List<FileItemModel> a, List<FileItemModel> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].path != b[i].path) return false;
    }
    return true;
  }

  /// 切换上一首 / 下一首（列表循环）
  Future<void> switchTrack(int delta) async {
    if (playlist.isEmpty) return;
    final next = (currentIndex + delta + playlist.length) % playlist.length;
    await _seekTo(next);
  }

  /// 跳转到指定曲目
  Future<void> jumpTo(int index) async {
    if (index < 0 || index >= playlist.length) return;
    await _seekTo(index);
  }

  /// 跳转到指定曲目：不显示全屏加载动画（保留播放器界面），
  /// 缓冲期间由 [buffering] 小菊花提示。
  /// 重复点击当前曲目直接忽略，避免重启播放造成的界面闪烁。
  Future<void> _seekTo(int index) async {
    // 同曲目重复点击：不重启、不刷新，保持播放状态，杜绝闪烁
    if (index == currentIndex) return;
    currentIndex = index;
    error = null;
    _resetTrackVisuals();
    notifyListeners();
    try {
      await _player.seek(Duration.zero, index: index);
      if (!_player.playing) await _player.play();
    } catch (e) {
      error = '播放失败，请检查网络后重试';
      notifyListeners();
    }
  }

  /// 切歌时立即清空旧曲目的展示文本（标题/歌手/专辑），
  /// 避免播放页短暂显示上一首歌的信息造成闪烁。
  /// 注意：进度与时长交给播放器流事件自行维护，绝不手动清零——
  /// 时长流仅在数值变化时触发，手动清零后若时长不变将永远停在 0。
  void _resetTrackVisuals() {
    currentTitle = null;
    currentArtist = null;
    currentAlbum = null;
  }

  void togglePlay() {
    _player.playing ? _player.pause() : _player.play();
  }

  void seekTo(Duration d) {
    _player.seek(d);
  }

  void setVolume(double v) {
    volume = v;
    _player.setVolume(v);
    notifyListeners();
  }

  /// 循环模式切换：列表循环 → 单曲循环 → 关闭
  void toggleLoop() {
    loop = (loop + 1) % 3;
    _player.setLoopMode(_loopModeFor(loop));
    notifyListeners();
  }

  LoopMode _loopModeFor(int m) {
    switch (m) {
      case 1:
        return LoopMode.one;
      case 2:
        return LoopMode.off;
      default:
        return LoopMode.all;
    }
  }

  /// 从播放列表移除若干曲目（多选删除后调用）
  void removeFromPlaylist(Iterable<FileItemModel> items) {
    final paths = items.map((e) => e.path).toSet();
    // 记录删除前的播放状态，用于删除后无缝衔接
    final prevUri = currentUri;
    final prevPos = _player.position;
    final wasPlaying = _player.playing;
    final wasCurrent = currentIndex >= 0 &&
        currentIndex < playlist.length &&
        paths.contains(playlist[currentIndex].path);
    playlist.removeWhere((e) => paths.contains(e.path));
    if (playlist.isEmpty) {
      stop();
      return;
    }
    if (wasCurrent) {
      currentIndex = currentIndex.clamp(0, playlist.length - 1);
    } else {
      final cur = currentUri;
      final idx = playlist.indexWhere((e) => e.path == cur);
      currentIndex = idx < 0 ? 0 : idx;
    }
    // 静默重建播放源：不显示全屏 loading，仅缓冲小菊花，避免删除后界面抖动。
    // 删除非当前曲目时恢复到原进度继续播放；删除当前曲目时跳到下一首从头播。
    final resumeAt =
        (!wasCurrent && prevUri == currentUri) ? prevPos : null;
    _buildAndPlay(silent: true, resumeAt: resumeAt, autoPlay: wasPlaying);
  }

  /// 停止播放并清空列表
  void stop() {
    _player.stop();
    playlist = [];
    currentIndex = -1;
    playing = false;
    loading = false;
    buffering = false;
    position = Duration.zero;
    duration = Duration.zero;
    error = null;
    currentTitle = null;
    currentArtist = null;
    currentAlbum = null;
    currentCover = null;
    _evictCacheIfNeeded();
    notifyListeners();
  }

  /// 重建播放源并播放（列表变化 / 首次加载）
  /// [silent] 为 true 时不置全屏 loading（列表删除等场景静默重建，保留播放器界面）；
  /// [resumeAt] 非空时在开播前恢复到该进度（删除非当前曲目后衔接原进度，避免整曲重播）；
  /// [autoPlay] 为 false 时重建后不自动播放（恢复删除前的播放/暂停状态）。
  Future<void> _buildAndPlay(
      {bool silent = false, Duration? resumeAt, bool autoPlay = true}) async {
    if (playlist.isEmpty) return;
    if (!silent) loading = true;
    error = null;
    // 进度与时长由播放器流事件维护，不在此清零（时长流仅在数值变化时触发）
    notifyListeners();
    try {
      // 并行获取全部曲目的临时下载 URL（带持久化缓存，通常零额外请求），减少加载等待
      final urls = await Future.wait(playlist.map(
          (f) => FileApi.getDownloadUrl(f.path, download: false)));
      final sources = <AudioSource>[];
      final mediaItems = <MediaItem>[];
      for (var i = 0; i < playlist.length; i++) {
        final f = playlist[i];
        final md = f.metadata;
        final item = MediaItem(
          id: f.path,
          title: md?['music:title'] ?? f.name,
          artist: md?['music:artist'],
          album: md?['music:album'],
        );
        // 纯流式播放：不整曲落盘，避免本地缓存快速增长（与主流音乐 App 一致）；
        // 代价是切回/重播需重新缓冲，换取几乎为零的本地占用
        sources.add(ProgressiveAudioSource(Uri.parse(urls[i]), tag: item));
        mediaItems.add(item);
      }
      await _player.setAudioSource(
        ConcatenatingAudioSource(children: sources),
        initialIndex: currentIndex,
      );
      await _player.setVolume(volume);
      await _player.setLoopMode(_loopModeFor(loop));
      // 先同步通知栏队列与曲目信息，再开始播放：
      // 通知栏首次创建时即携带歌曲信息（若后补元数据，部分系统不会主动刷新）
      ReveAudioHandler.instance?.setQueue(mediaItems, currentIndex);
      _refreshMediaInfo(currentIndex);
      // 删除非当前曲目后：恢复到删除前的播放进度，无缝衔接不重播
      if (resumeAt != null && resumeAt > Duration.zero) {
        await _player.seek(resumeAt);
      }
      if (autoPlay) await _player.play();
      _prefetchNextCover();
      _evictCacheIfNeeded();
    } catch (e) {
      error = '音频加载失败，请检查网络后重试';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// 曲目切换：更新媒体信息（元数据缺失时自动补拉）与封面缩略图，并预热下一曲封面
  Future<void> _onIndexChanged(int? i) async {
    if (i == null || i < 0 || i >= playlist.length) return;
    if (i != currentIndex) {
      currentIndex = i;
      // 通知栏/系统切歌路径（未经过 _seekTo）：同样立即清空旧曲目展示信息
      _resetTrackVisuals();
      notifyListeners();
    }
    _refreshMediaInfo(i);
    _prefetchNextCover();
  }

  Future<void> _refreshMediaInfo(int index) async {
    if (index != currentIndex || _metaLoadingFor == index) return;
    _metaLoadingFor = index;
    try {
      final f = playlist[index];
      var md = f.metadata;
      // 列表接口通常不带 music:* 元数据，播放时对当前曲目补拉
      if (md == null || !md.containsKey('music:title')) {
        try {
          final info = await FileApi.getFileInfo(f.path);
          final raw = info['metadata'];
          if (raw is Map) {
            md = raw
                .map((k, v) => MapEntry(k.toString(), v.toString()));
            playlist[index] = FileItemModel(
                type: f.type,
                id: f.id,
                name: f.name,
                size: f.size,
                path: f.path,
                createdAt: f.createdAt,
                updatedAt: f.updatedAt,
                metadata: md);
          }
        } catch (_) {}
      }
      currentTitle = md?['music:title'] ?? f.name;
      currentArtist = md?['music:artist'];
      currentAlbum = md?['music:album'];
      // 同步到通知栏 MediaItem（歌名/歌手/专辑）
      ReveAudioHandler.instance?.updateTrackInfo(
        index,
        title: currentTitle,
        artist: currentArtist,
        album: currentAlbum,
      );
      notifyListeners();
      await _loadCover(index);
    } finally {
      if (_metaLoadingFor == index) _metaLoadingFor = null;
    }
  }

  /// 异步加载当前曲目封面（缩略图），同步到通知栏与播放页
  Future<void> _loadCover(int index) async {
    if (index != currentIndex) return;
    try {
      final url = await FileApi.getThumbnailUrl(playlist[index].path);
      if (index != currentIndex) return;
      if (url != currentCover) {
        currentCover = url;
        if (url != null) {
          ReveAudioHandler.instance?.updateArtwork(index, Uri.parse(url));
        }
        notifyListeners();
      }
    } catch (_) {}
  }

  // ---------- 下一曲封面预热（WiFi 下） ----------

  /// 预热下一曲封面：
  /// 1. 先把封面地址写入通知栏队列——切歌时首条媒体信息即携带封面，
  ///    避免 audio_service 先发"无封面"元数据导致通知栏封面闪灰；
  /// 2. WiFi 下把封面字节预下载到封面缓存，取图直接命中本地。
  void _prefetchNextCover() {
    if (playlist.isEmpty || currentIndex < 0) return;
    final next = (currentIndex + 1) % playlist.length;
    if (next == currentIndex) return; // 仅一首，无需预热
    _prefetchCover(next, playlist[next]);
  }

  Future<void> _prefetchCover(int index, FileItemModel f) async {
    try {
      final thumb = await FileApi.getThumbnailUrl(f.path);
      if (thumb == null) return;
      // 未播放的曲目：仅更新队列中的封面地址，不广播当前状态
      ReveAudioHandler.instance?.updateArtwork(index, Uri.parse(thumb));
      // 移动数据下跳过封面字节预下载，仅 WiFi 预热（封面很小，省一点是一点）
      if (!_isWifi) return;
      await AudioService.cacheManager.getSingleFile(thumb);
    } catch (_) {}
  }

  /// 缓存超阈值时淘汰最旧文件（节流 30s，避免播放/切歌高频触发遍历文件系统）
  void _evictCacheIfNeeded() {
    if (DateTime.now().difference(_lastEvictAt).inSeconds < 30) return;
    _lastEvictAt = DateTime.now();
    AppCache.evictIfOverflow();
  }
}
