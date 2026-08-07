import 'package:flutter/material.dart';

import '../config/AppTheme.dart';

/// 文件类型 —— 柔和圆角瓦片色板（前景 + 浅底，含深色模式变体）
///
/// 「色即类型」：图片紫 / 视频红 / 音乐琥珀 / 文档青，贯穿分类页、
/// 文件图标、详情页与传输任务行；品牌蓝仅表达「可执行动作」。
/// [fg] / [bg] 为随主题模式切换的当前取值。
enum FileType {
  DIR(
      'dir', Icons.folder_rounded,
      Color(0xFF2F6BFF), Color(0xFFEDF3FF),
      Color(0xFF6C8CFF), Color(0xFF1D2A4A)),
  IMAGE(
      'image', Icons.image_rounded,
      Color(0xFF7C5CFC), Color(0xFFF3EEFF),
      Color(0xFF9E7CFF), Color(0xFF2A2440)),
  VIDEO(
      'video', Icons.videocam_rounded,
      Color(0xFFE5484D), Color(0xFFFFEEF0),
      Color(0xFFFF6B6F), Color(0xFF3A2226)),
  AUDIO(
      'audio', Icons.music_note_rounded,
      Color(0xFFF5A623), Color(0xFFFFF3E6),
      Color(0xFFFFB84D), Color(0xFF3A2E1E)),
  DOC(
      'doc', Icons.description_rounded,
      Color(0xFF14B8A6), Color(0xFFE6F7F5),
      Color(0xFF2DD4BF), Color(0xFF1E3A35)),
  ARCHIVE(
      'archive', Icons.archive_rounded,
      Color(0xFFD97706), Color(0xFFFFF7E0),
      Color(0xFFF59E0B), Color(0xFF3A2E14)),
  UNKNOWN(
      'unknown', Icons.insert_drive_file_rounded,
      Color(0xFF5B6478), Color(0xFFF1F2F4),
      Color(0xFF8A93A6), Color(0xFF232933)),
  ;

  /// 类型键
  final String value;

  /// 图标
  final IconData icon;

  /// 浅色模式前景色（图标颜色）
  final Color color;

  /// 浅色模式瓦片底色
  final Color tileColor;

  /// 深色模式前景色（图标颜色）
  final Color colorDark;

  /// 深色模式瓦片底色
  final Color tileColorDark;

  const FileType(this.value, this.icon, this.color, this.tileColor,
      this.colorDark, this.tileColorDark);

  /// 当前主题模式下的前景色
  Color get fg => AppColors.dark ? colorDark : color;

  /// 当前主题模式下的瓦片底色
  Color get bg => AppColors.dark ? tileColorDark : tileColor;

  static const _imageSuffixes = {
    'png', 'jpg', 'jpeg', 'gif', 'bmp', 'webp', 'svg', 'heic', 'avif',
  };
  static const _videoSuffixes = {
    'mp4', 'mkv', 'mov', 'avi', 'flv', 'wmv', 'webm', 'm4v', 'rmvb', 'ts',
  };
  static const _audioSuffixes = {
    'mp3', 'wav', 'flac', 'aac', 'ogg', 'm4a', 'wma', 'opus',
  };
  static const _docSuffixes = {
    'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'md', 'csv',
    'json', 'html', 'htm', 'xml', 'js', 'ts', 'css', 'log',
  };
  static const _archiveSuffixes = {
    'zip', 'rar', '7z', 'tar', 'gz', 'bz2', 'xz', 'iso',
  };

  /// 解析类型：type 1=文件夹，其余按后缀归组
  static FileType _resolve(int type, String name) {
    if (type == 1) return DIR;
    final dot = name.lastIndexOf('.');
    if (dot == -1 || dot == name.length - 1) return UNKNOWN;
    final suffix = name.substring(dot + 1).toLowerCase();
    if (_imageSuffixes.contains(suffix)) return IMAGE;
    if (_videoSuffixes.contains(suffix)) return VIDEO;
    if (_audioSuffixes.contains(suffix)) return AUDIO;
    if (_docSuffixes.contains(suffix)) return DOC;
    if (_archiveSuffixes.contains(suffix)) return ARCHIVE;
    return UNKNOWN;
  }

  /// V4 type：0=文件，1=文件夹
  static IconData getIconByTypeAndName(int type, String name) =>
      _resolve(type, name).icon;

  /// 是否为图片文件（网格视图缩略图用）
  static bool isImage(int type, String name) =>
      _resolve(type, name) == IMAGE;

  /// 是否为音频文件（播放器切歌列表用）
  static bool isAudio(int type, String name) =>
      _resolve(type, name) == AUDIO;

  /// 当前主题模式下的前景色（图标颜色）
  static Color getColorByValue(int type, String name) =>
      _resolve(type, name).fg;

  /// 当前主题模式下的瓦片底色
  static Color getBgColorByValue(int type, String name) =>
      _resolve(type, name).bg;
}
