# Cloudreve V4 迁移 + 功能补全实现计划

**Goal:** 将 FlutterReve（flutter_reve）从 Cloudreve V3 API（Cookie 认证）迁移到 V4 API（JWT 认证），并在现有基础上补全上传、下载、删除、重命名、分享、下载任务列表功能，使其兼容 Cloudreve 4.18.0。

**Architecture:** 适度分层。保留现有页面结构，重构网络层（DioUtil + TokenManager）与数据层（Model + API 方法），认证从 Cookie 改为 Bearer JWT（401 自动刷新重放），文件定位从路径改为 URI（`cloudreve://my/...`）。页面层逐页适配 V4 数据结构并接入新功能。

**Tech Stack:** Flutter / Dart / dio / shared_preferences / flutter_smart_dialog / file_picker（新增）/ path_provider（新增）

**联调环境:** Cloudreve 4.18.0 服务器 `https://ling101-cloudreve.ms.show`（已部署）

---

## V4 API 技术规格（已完成调研，作为实现依据）

| 功能            | 接口                                           | 认证     | 关键字段                                                                                                             |
| --------------- | ---------------------------------------------- | -------- | -------------------------------------------------------------------------------------------------------------------- |
| 站点配置        | `GET /api/v4/site/config/basic`                | Optional | `data.title`                                                                                                         |
| 登录            | `POST /api/v4/session/token`                   | None     | body `{email, password}` → `data.user` + `data.token.{access_token, refresh_token, access_expires, refresh_expires}` |
| 刷新 token      | `POST /api/v4/session/token/refresh`           | None     | body `{refresh_token}` → `data.{access_token, refresh_token, access_expires, refresh_expires}`                       |
| 文件列表        | `GET /api/v4/file?uri=&page=&page_size=`       | Optional | `data.files[]`（`type`：0=文件/1=文件夹，`path` 为完整 URI，`name`/`size`/`updated_at`/`created_at`）                |
| 存储容量        | `GET /api/v4/user/capacity`                    | Required | `data.{total, used}`（单位字节；V3 是 `free`，V4 是 `used`）                                                         |
| 新建文件/文件夹 | `POST /api/v4/file/create`                     | Optional | body `{uri, type: "folder"\|"file", err_on_conflict}`                                                                |
| 重命名          | `POST /api/v4/file/rename`                     | Optional | body `{uri, new_name}`                                                                                               |
| 删除            | `DELETE /api/v4/file`                          | Optional | body `{uris: [...], skip_soft_delete: false}`（false=进回收站）                                                      |
| 下载临时直链    | `POST /api/v4/file/url`                        | Optional | body `{uris: [...], download: true}` → `data.urls[].url`（无需认证头）                                               |
| 创建上传会话    | `PUT /api/v4/file/upload`                      | Optional | body `{uri, size, last_modified, mime_type, policy_id?}` → `data.{session_id, chunk_size, expires}`                  |
| 上传分片        | `POST /api/v4/file/upload/{sessionId}/{index}` | Optional | octet-stream body，`chunk_size=0` 时整文件作为 index 0 一次上传                                                      |
| 创建分享        | `PUT /api/v4/share`                            | Required | body `{uri, is_private, expire, password, permissions}` → `data`（分享链接 URL，如 `/s/xxx` 或 `/s/xxx/pwd`）        |
| 头像            | `GET /api/v4/user/avatar/{userId}`             | None     | 原始图片，可作 `<img>` src                                                                                           |
| 登出            | `POST /api/v4/session`（DELETE）               | Required | 撤销 refresh token（可选实现）                                                                                       |

**认证头:** `X-Cloudreve-Token: Bearer <access_token>`（服务器自定义了认证头名称，**Bearer 前缀必须有**；后端 `jwt.go` 用 `strings.TrimPrefix(headerVal, "Bearer ")` 提取 token）
**2FA/验证码:** 登录若返回 code 203（需 2FA）或验证码错误，弹出提示（本版本仅提示，不做 2FA 流程）。

---

## Task 1: 添加依赖

**Files:**

- Modify: `pubspec.yaml`（dependencies 区）

**Step 1:** 在 dependencies 中添加：

```yaml
# 文件选择（上传）
file_picker: ^8.0.0
# 本地目录（下载保存）
path_provider: ^2.1.0
```

**Step 2:** 验证：运行 `flutter pub get` 无报错；`flutter analyze` 通过。

**Step 3:** 提交（message: `feat: add file_picker and path_provider deps`）。

---

## Task 2: 网络层重构（DioUtil + TokenManager）

**Files:**

- Create: `lib/util/TokenManager.dart`
- Modify: `lib/util/DioUtil.dart`

**Step 1:** 创建 `TokenManager.dart`，负责当前账号 token 对（access/refresh/过期时间）的读取与存储：

- `static Future<void> saveTokens(String accessToken, String refreshToken, DateTime accessExpires, DateTime refreshExpires)`
- `static Future<String> getAccessToken()` / `getRefreshToken()`
- `static Future<void> clear()`
- 存取走 `SpUtils`，key 固定（单账号上下文，多账号切换时整体覆盖）

**Step 2:** 重构 `DioUtil.dart`：

- 移除 Cookie 相关逻辑（`_onRequest` 中 Cookie 头、`_onResponse` 中 set-cookie 保存）
- `_onRequest`：**同步顺序修复** —— 先 `await` 读取 baseUrl 和 access token，再 `handler.next(options)`：

```dart
void _onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
  final baseUrl = await SpUtils.getString('CurrentBaseUrl');
  if (baseUrl.isNotEmpty) options.baseUrl = baseUrl;
  final token = await TokenManager.getAccessToken();
  // 服务器自定义认证头：X-Cloudreve-Token，值必须带 "Bearer " 前缀
  if (token.isNotEmpty) options.headers['X-Cloudreve-Token'] = 'Bearer $token';
  handler.next(options);
}
```

- `_onResponse`：移除 Cookie 保存逻辑；`response.data['code'] == 401` 时抛 `NotLoginException`
- `_onError`：新增 401 自动刷新重放逻辑：
  1. 收到 401 → 用 refresh_token 调 `POST /api/v4/session/token/refresh`
  2. 刷新成功 → 保存新 token 对 → 重放原请求（克隆 `error.requestOptions`，设置新 Authorization 头）
  3. 刷新失败 → 清除登录态，抛 `NotLoginException` 并引导回登录页
  - 注意用 `_isRefreshing` 标志防并发重复刷新（简单实现：仅首次 401 触发，其余等待或用 Future 缓存）

**Step 3:** 验证：`flutter analyze` 通过。编译通过（无真实服务器时先不联调）。

**Step 4:** 提交（message: `refactor: rework DioUtil for JWT auth with auto-refresh`）。

---

## Task 3: 数据模型层

**Files:**

- Create: `lib/model/FileItemModel.dart`
- Create: `lib/model/UserModel.dart`

**Step 1:** `FileItemModel`：字段 `type(int)`、`name`、`size`、`path(uri)`、`id`、`updatedAt`、`createdAt`；`isDir => type == 1`；`fromJson`。

**Step 2:** `UserModel`：字段 `id`、`email`、`nickname`、`avatar`、`group(name/id)`；`fromJson`。登录响应 `data.user` 映射到该模型。

**Step 3:** 验证：`flutter analyze` 通过。

**Step 4:** 提交（message: `feat: add FileItemModel and UserModel`）。

---

## Task 4: API 层

**Files:**

- Modify: `lib/api/AuthApi.dart`
- Modify: `lib/api/InfoApi.dart`
- Create: `lib/api/FileApi.dart`
- Create: `lib/api/ShareApi.dart`
- Create: `lib/api/UserApi.dart`

**Step 1:** `AuthApi`：

- `getConfig()` → `GET /api/v4/site/config/basic`，返回 `result['data']`
- `login(email, password)` → `POST /api/v4/session/token` body `{email, password}`，返回完整响应（调用方处理 `data.user` / `data.token` / code 203）
- `refreshToken(refreshToken)` → `POST /api/v4/session/token/refresh` body `{refresh_token}`，返回 `data`

**Step 2:** `InfoApi`：删除（目录列表、存储改用 FileApi/UserApi），或保留 `getStorage` 转发到 `UserApi.getCapacity`。

**Step 3:** `FileApi`（URI 前缀常量 `cloudreve://my`）：

- `listFiles(String uri, {int page = 1, int pageSize = 100})` → `GET /file?uri=&page=&page_size=`，返回 `data`
- `createFolder(String parentUri, String name)` → `POST /file/create` body `{uri: '$parentUri/$name', type: 'folder', err_on_conflict: false}`
- `renameFile(String uri, String newName)` → `POST /file/rename`
- `deleteFiles(List<String> uris)` → `DELETE /file` body `{uris, skip_soft_delete: false}`
- `getDownloadUrl(String uri)` → `POST /file/url` body `{uris: [uri], download: true}`，返回 `data.urls.first.url`
- `createUploadSession(String uri, int size, {String? mimeType, int? lastModified})` → `PUT /file/upload`
- `uploadChunk(String sessionId, int index, List<int> bytes)` → `POST /file/upload/$sessionId/$index`

**Step 4:** `ShareApi`：

- `createShare(String uri, {bool isPrivate = false, int? expireSeconds, String? password})` → `PUT /share` body `{uri, is_private, expire, password, permissions: {anonymous: "AQ=="}}`（`permissions` 社区版传空对象或 `{anonymous: "AQ=="}`，联调确认）
- `listMyShares()` → `GET /share/my`（路径联调确认，见备注）

**Step 5:** `UserApi`：

- `getCapacity()` → `GET /user/capacity`，返回 `data.{total, used}`
- 头像：直接拼 URL `{siteUrl}/api/v4/user/avatar/{userId}`（无需 API 方法，页面 `Image.network` 使用）

**Step 6:** 验证：`flutter analyze` 通过。

**Step 7:** 提交（message: `feat: add V4 API layer (Auth/File/Share/User)`）。

---

## Task 5: 站点绑定页适配

**Files:**

- Modify: `lib/main.dart`

**Step 1:** `selectConfig()` 中 `result['data']['title']` 逻辑不变（V4 `site/config/basic` 仍返回 `data.title`），仅确认 `AuthApi.getConfig()` 已指向 V4 路径即可。

**Step 2:** 硬编码服务器地址改为 `_siteAddrController.text = "https://ling101-cloudreve.ms.show"`（联调服务器）。

**Step 3:** 验证：真机/模拟器 `flutter run` → 绑定站点页输入地址 → 显示站点标题 → 进入登录页。

---

## Task 6: 登录页适配（JWT + 多账号结构）

**Files:**

- Modify: `lib/page/login/login.dart`
- Modify: `lib/util/SpUtils.dart`（如需新增 key）

**Step 1:** `login()` 改造：

- 调 `AuthApi.login(email, password)`
- 处理 code 203（2FA 需要）→ 弹提示"该站点启用了两步验证，暂不支持"
- 成功：`TokenManager.saveTokens(access_token, refresh_token, access_expires, refresh_expires)`
- 用户信息：`data.user` → `UserModel`，头像 URL 改为 `{siteUrl}/api/v4/user/avatar/{user.id}`
- 多账号存储结构调整：`accounts` 列表每项存 `{siteUrl, siteName, userName, userInfo, token: {access_token, refresh_token, ...}}`（token 存当前账号对象内，切换账号时写入 TokenManager）

**Step 2:** `convertAvatar` 中 V3 头像路径 `/api/v3/user/avatar/{id}/s` 改为 V4 `/api/v4/user/avatar/{id}`。

**Step 3:** 登录后跳转：`currentMenu` 从 `'/'` 改为根目录 URI `'cloudreve://my'`。

**Step 4:** 验证：`flutter analyze`；真机登录测试（用你的测试账号）→ 成功进入主页。

**Step 5:** 提交（message: `feat: migrate login to V4 JWT auth`）。

---

## Task 7: 文件列表页适配（URI 化 + 目录浏览）

**Files:**

- Modify: `lib/api/InfoApi.dart`（目录列表改用 FileApi）
- Modify: `lib/page/index/index.dart`
- Modify: `lib/enums/FileType.dart`

**Step 1:** `FileType.dart` 适配 V4：`getIconByTypeAndName` 参数类型改为 `int type`，判断 `type == 1`（文件夹）否则按后缀判断图标。删除 `DIR.value` 字符串依赖（或保留兼容）。

**Step 2:** `index.dart`：

- `currentList` 存 `FileItemModel` 列表（从 `data.files` 映射）
- 根目录：`SpUtils.getString('currentMenu')` 存 URI（默认 `cloudreve://my`）
- `getRootFileList()`：`FileApi.listFiles(currentUri)` → `setState(currentList = ...)`
- `inDir()`：文件夹 → `currentMenu = obj.path`（V4 响应自带 `path` 字段，无需手动拼接）→ 重新加载
- 文件项显示：`obj.name`、`obj.size`（格式化）、`obj.updatedAt`（当前"修改于"字段未填充，V4 有 `updated_at` 可显示）
- 下拉刷新：重新加载当前 URI

**Step 3:** 长按菜单：下载/删除改为真实调用（删除见 Task 8，下载见 Task 9），分享入口保留。

**Step 4:** 验证：`flutter analyze`；真机测试目录浏览、进入/返回文件夹、下拉刷新。

**Step 5:** 提交（message: `feat: migrate file list to V4 URI`）。

---

## Task 8: 文件操作补全（删除 + 重命名 + 新建文件夹）

**Files:**

- Modify: `lib/page/index/index.dart`

**Step 1:** 长按菜单真实化：

- 删除：确认弹窗（复用 giffy_dialog 或 smart_dialog）→ `FileApi.deleteFiles([uri])` → 刷新列表
- 重命名：弹窗输入新名称 → `FileApi.renameFile(uri, newName)` → 刷新列表

**Step 2:** 右上角菜单：

- 新建文件夹：弹窗输入名称 → `FileApi.createFolder(currentUri, name)` → 刷新列表
- 新建文件（空文本文件）：`FileApi.createFolder` 同接口，`type: 'file'`，可选实现

**Step 3:** 验证：真机测试新建文件夹 → 删除 → 重命名全流程；检查回收站（web 端确认删除后文件进入回收站）。

**Step 4:** 提交（message: `feat: implement delete/rename/create-folder`）。

---

## Task 9: 上传功能（分片 + 进度）

**Files:**

- Create: `lib/util/UploadManager.dart`（可选，简单实现可内联在页面）
- Modify: `lib/page/index/index.dart`
- Modify: `lib/page/index/download.dart`（上传任务也展示在任务队列）

**Step 1:** 上传按钮（右上角菜单 + FAB 区域）：

- `FilePicker.platform.pickFiles(allowMultiple: true, withData: false)` 选文件
- 对每个文件：
  1. `FileApi.createUploadSession(uri: '$currentUri/${文件名}', size: fileSize, mimeType, lastModified)`
  2. 取 `chunk_size`：`0` 表示不分片 → 整个文件作为 index 0 一次 POST；否则按 chunk_size 分片顺序上传
  3. 上传进度汇总 → 进度条展示（`flutter_smart_dialog` 或页面内进度组件）
  4. 完成后刷新列表

**Step 2:** 上传任务并入下载页任务队列（与下载共用本地任务模型）。

**Step 3:** 验证：真机上传小文件（<1MB）和大文件（>25MB 触发分片）各一次，确认文件出现在列表中。

**Step 4:** 提交（message: `feat: implement chunked upload with progress`）。

---

## Task 10: 下载功能 + 下载页任务列表

**Files:**

- Create: `lib/model/DownloadTaskModel.dart`
- Modify: `lib/page/index/index.dart`（下载入口）
- Modify: `lib/page/index/download.dart`（任务列表 UI + 逻辑）

**Step 1:** `DownloadTaskModel`：`name`、`uri`、`progress`(0-1)、`status`(downloading/finished/failed)、`savePath`、`size`。

**Step 2:** 下载页改造：

- 本地任务管理器（内存 List + `SpUtils` 持久化，或用简单单例 `DownloadManager`）
- Tab1「进行中」：`dio.download(url, savePath, onReceiveProgress)`，进度条实时更新
- Tab2「已完成」：显示完成列表，点击可打开文件目录（本版本仅显示路径，不做文件打开）
- 存储位置：`path_provider` → 平台文档目录（Android 无需额外权限）下 `CloudReve/` 子目录

**Step 3:** `index.dart` 长按「下载」：`FileApi.getDownloadUrl(uri)` → 加入任务队列 → 启动下载。

**Step 4:** 验证：真机下载一个文件 → 任务列表进度推进 → 完成后显示在已完成 Tab；检查文件确实落在本地目录。

**Step 5:** 提交（message: `feat: implement download with task queue`）。

---

## Task 11: 分享功能

**Files:**

- Create: `lib/page/index/share.dart`（或弹窗组件）
- Modify: `lib/page/index/index.dart`（长按菜单「分享」入口）

**Step 1:** 分享弹窗/页面：

- 选中文件/文件夹 → 弹窗输入：有效期（不填=永久）、密码（可选，私有分享）
- 调 `ShareApi.createShare(uri, isPrivate, expireSeconds, password)`
- 成功 → 显示分享链接（`{siteUrl}` + 返回的 `data` 路径），提供复制按钮（`Clipboard.setData`）

**Step 2:** 备注：`permissions` 字段在社区版可能被忽略，联调时以实际服务器返回为准；若必填，传 `{anonymous: "AQ==", everyone: "AQ=="}`。

**Step 3:** 验证：真机创建分享 → 复制链接 → 用浏览器打开该链接可访问。

**Step 4:** 提交（message: `feat: implement share link creation`）。

---

## Task 12: 账户页 + 多账号切换适配

**Files:**

- Modify: `lib/page/index/account.dart`
- Modify: `lib/page/login/users.dart`

**Step 1:** `account.dart`：

- `getStorage()`：`UserApi.getCapacity()` → `data.total` / `data.used`；`_free = total - used`（保留现有显示逻辑，percent 用 used/total）
- 头像：`Image.network` 使用 V4 头像 URL（登录时已存）
- `_userInfo['data']['group']['id']`/`name` 字段与 V4 `data.user` 结构核对（V4 登录返回 `user.group.{id, name}`，结构兼容现有取值）

**Step 2:** `users.dart`：

- 账号切换：点击账号 → 将该账号的 token 写入 TokenManager + 切换 `CurrentBaseUrl` + `currentMenu` 重置为 `cloudreve://my` → 回主页刷新
- 删除不再使用的账号（可选）

**Step 3:** 退出登录：清理 TokenManager + `isLogin=false`（保留现有逻辑，补调 `TokenManager.clear()`）。

**Step 4:** 验证：真机测试多账号切换后文件列表、容量均对应该账号；退出登录后可重新登录。

**Step 5:** 提交（message: `feat: adapt account page and multi-account switching`）。

---

## Task 13: 整体联调与回归

**Step 1:** 全流程真机验证清单：

- [ ] 站点绑定 → 显示站点标题
- [ ] 登录（正确/错误密码）
- [ ] 目录浏览、进入/返回、下拉刷新
- [ ] 新建文件夹 → 删除（进回收站）→ 重命名
- [ ] 上传小文件 + 大文件分片，进度条正常
- [ ] 下载文件，任务列表进度、完成状态正常
- [ ] 创建分享链接，浏览器可打开
- [ ] 账户页容量、头像、用户组正确
- [ ] 多账号切换后各数据正确
- [ ] 退出登录 → 重新登录

**Step 2:** `flutter analyze` 无 error。

**Step 3:** 提交最终整理。

---

## 待联调确认项

1. **分享 `permissions` 字段**：社区版 4.18.0 是否必需、格式如何（示例 `{anonymous: "AQ=="}`）
2. **`GET /share/my` 路径**：列表分享接口真实路径（从 llms.txt 看是 `List my share links`，路径实现时确认）
3. **登录 2FA code 203**：测试账号若启用 2FA，确认提示文案
4. **上传分片**：本地存储策略下 `chunk_size` 实际值，验证分片逻辑
