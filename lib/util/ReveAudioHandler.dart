import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

/// 媒体会话处理器：把 just_audio 播放状态桥接到系统媒体通知栏 / 锁屏控制。
///
/// - 控制按钮固定为：上一曲 / 播放暂停 / 下一曲（列表循环，最后一首自动回到第一首，不减少按钮）
/// - 声明 [MediaAction.seek] 并把时长写入 MediaItem，使系统媒体面板 / 通知栏出现可拖动进度条
/// - 播放页与通知栏统一展示 MediaItem 元数据（歌名 / 歌手 / 专辑 / 封面 / 时长）
class ReveAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  ReveAudioHandler() {
    _player.playbackEventStream.listen(_broadcastState);
    _player.playingStream.listen((p) {
      _playing = p;
      _broadcastState();
    });
  }

  /// 全局实例（main 中 AudioService.init 创建后赋值）
  static ReveAudioHandler? instance;

  final AudioPlayer _player = AudioPlayer();
  bool _playing = false;

  AudioPlayer get player => _player;

  @override
  Future<void> play() async {
    _playing = true;
    _broadcastState();
    await _player.play();
  }

  @override
  Future<void> pause() async {
    _playing = false;
    _broadcastState();
    await _player.pause();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  /// 下一曲：列表循环（最后一首回到第一首）
  @override
  Future<void> skipToNext() => _skipRelative(1);

  /// 上一曲：列表循环（第一首回到最后一首）
  @override
  Future<void> skipToPrevious() => _skipRelative(-1);

  Future<void> _skipRelative(int delta) async {
    final len = _player.sequence?.length ?? 0;
    final idx = _player.currentIndex;
    if (len == 0 || idx == null) return;
    await _player.seek(Duration.zero, index: (idx + delta + len) % len);
  }

  @override
  Future<void> skipToQueueItem(int index) =>
      _player.seek(Duration.zero, index: index);

  /// 更新播放队列（加载新播放源后调用）
  void setQueue(List<MediaItem> items, int index) {
    queue.add(items);
    if (index >= 0 && index < items.length) {
      mediaItem.add(items[index]);
    }
    _broadcastState();
  }

  /// 停止/登出时清空通知栏队列与当前曲目，
  /// 避免系统媒体面板残留旧歌曲且仍可播放
  void clear() {
    _playing = false;
    queue.add([]);
    mediaItem.add(null);
    _broadcastState();
  }

  /// 更新指定曲目的封面（缩略图异步加载完成后调用）
  void updateArtwork(int index, Uri? artUri) {
    final items = List.of(queue.value);
    if (index < 0 || index >= items.length) return;
    final updated = items[index].copyWith(artUri: artUri);
    items[index] = updated;
    queue.add(items);
    if (index == playbackState.value.queueIndex) {
      mediaItem.add(updated);
    }
    _broadcastState();
  }

  /// 更新指定曲目的歌名 / 歌手 / 专辑（元数据补拉完成后调用）
  void updateTrackInfo(int index,
      {String? title, String? artist, String? album}) {
    final items = List.of(queue.value);
    if (index < 0 || index >= items.length) return;
    final cur = items[index];
    if (title == cur.title && artist == cur.artist && album == cur.album) {
      return;
    }
    final updated = cur.copyWith(
      title: title ?? cur.title,
      artist: artist,
      album: album,
    );
    items[index] = updated;
    queue.add(items);
    if (index == playbackState.value.queueIndex) {
      mediaItem.add(updated);
    }
    _broadcastState();
  }

  /// 广播最新播放状态到系统媒体会话（决定通知栏按钮与当前曲目信息）
  void _broadcastState([PlaybackEvent? event]) {
    final e = event ?? _player.playbackEvent;
    final idx = e.currentIndex;
    // 实时同步当前曲目到通知栏：切歌 / 封面 / 时长就绪后立即刷新
    if (idx != null && idx >= 0 && idx < queue.value.length) {
      var item = queue.value[idx];
      // 时长就绪后写入 MediaItem，系统媒体面板 / 通知栏才会渲染可拖动进度条
      if (e.duration != null && item.duration != e.duration) {
        item = item.copyWith(duration: e.duration);
        final items = List.of(queue.value);
        items[idx] = item;
        queue.add(items);
      }
      if (mediaItem.valueOrNull != item) {
        mediaItem.add(item);
      }
    }
    // 固定三个控制键：上一曲 / 播放暂停 / 下一曲（不随位置减少）
    final controls = <MediaControl>[
      MediaControl.skipToPrevious,
      _playing ? MediaControl.pause : MediaControl.play,
      MediaControl.skipToNext,
    ];
    playbackState.add(playbackState.value.copyWith(
      controls: controls,
      androidCompactActionIndices: const [0, 1, 2],
      processingState: _mapProcessingState(e.processingState),
      playing: _playing,
      updatePosition: e.updatePosition,
      bufferedPosition: e.bufferedPosition,
      speed: _playing ? 1.0 : 0.0,
      queueIndex: idx,
      systemActions: {MediaAction.seek},
    ));
  }

  AudioProcessingState _mapProcessingState(ProcessingState s) {
    switch (s) {
      case ProcessingState.idle:
        return AudioProcessingState.idle;
      case ProcessingState.loading:
        return AudioProcessingState.loading;
      case ProcessingState.buffering:
        return AudioProcessingState.buffering;
      case ProcessingState.ready:
        return AudioProcessingState.ready;
      case ProcessingState.completed:
        return AudioProcessingState.completed;
    }
  }
}
