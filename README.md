<div align="center">

# CloudReve

基于 CloudReve V4 API 的 Android 云存储客户端，Flutter 构建。

</div>

## 功能特性

- **文件管理**：目录浏览（列表/网格）、排序、面包屑导航、文件详情
- **批量操作**：多选下载、分享、删除、重命名、移动/复制
- **分类视图**：图片 / 视频 / 音乐 / 文档 四类快捷筛选
- **在线预览**：图片、视频、音频、文档在线预览
- **音乐播放**：后台播放、系统媒体通知栏控制、循环模式、封面缓存
- **传输管理**：上传 / 下载后台任务，支持断点恢复与失败重试
- **回收站**：软删除、恢复、彻底删除、一键清空
- **我的分享**：创建 / 编辑 / 删除分享链接，复制分享地址
- **登录安全**：密码登录、指纹登录、多账号管理、自动续期 token
- **隐私安全**：修改密码、指纹登录账号管理
- **体验细节**：深色 / 浅色主题、缓存自动清理、版本更新检查

## 技术栈

- Flutter / Dart
- CloudReve V4 API（后端）
- just_audio + audio_service（后台音乐播放）
- flutter_cache_manager（缩略图 / 封面磁盘缓存）
- flutter_secure_storage（凭据加密存储）

## 构建

```bash
flutter pub get
flutter build apk --release
```

APK 输出于 `build/app/outputs/flutter-apk/`。

## 发布

新版本通过 GitHub Releases 分发：修改 `pubspec.yaml` 中的 `version`，构建 APK 后上传到 Release（tag 形如 `v1.1.0`，更新说明写在 release body），客户端会自动弹出更新提示。

## 开源协议

[MIT](LICENSE)
