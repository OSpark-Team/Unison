# entry 模块文档

[根目录](../../CLAUDE.md) > **entry**

> 文档生成时间：2026-02-04T07:45:43Z

## 变更记录 (Changelog)

| 日期 | 版本 | 变更内容 |
|------|------|----------|
| 2026-02-04 | 1.2.0 | 深度扫描更新，补充各子模块详细接口和依赖分析 |

---

## 模块职责

entry 是应用的主模块，包含应用的核心功能：
- 用户界面（首页、歌单详情、设置等）
- OMSP 协议适配器
- 数据源管理（本地持久化 + 分布式同步）
- 应用接续（跨设备）
- 视图模型（MVVM 架构）
- 工具类集合
- UI 组件库

---

## 入口与启动

### 应用入口
- **文件**：`src/main/ets/entryability/EntryAbility.ets`
- **启动流程**：
  1. 初始化数据源数据库 (`SourceDataSource.initialize`)
  2. 初始化应用接续 (`ContinueSwitch.initialize`)
  3. 初始化首选项存储 (`PreferencesUtil.init`)
  4. 初始化窗口工具 (`WindowUtil.loadContent`)
  5. 加载所有数据源 (`SourceListViewModel.loadSources`)
  6. 处理应用接续数据

### 备份能力
- **文件**：`src/main/ets/entrybackupability/EntryBackupAbility.ets`
- **功能**：支持应用数据备份与恢复

---

## 对外接口

### 路由页面
| 路由名称 | 文件路径 | 功能描述 |
|----------|----------|----------|
| ContentCardDetail | pages/dialog/ContentCardDetail.ets | 内容卡片详情弹窗（支持 HotSongAll、RecommendPlaylistAll、RecommendArtistAll、RankAll） |
| PlaylistDetail | pages/PlaylistDetail.ets | 歌单详情页（支持 normal/album/artist 类型） |

### 主页面
- **文件**：`src/main/ets/pages/Index.ets`
- **结构**：
  - Tab 导航（首页、库、AI、我的）
  - 数据源选择器（支持多数据源切换）
  - 应用接续页面跳转

---

## 关键依赖与配置

### 依赖模块
- `@ohos/axios` - HTTP 请求
- `@kit.ArkUI` - ArkUI 框架
- `@kit.AbilityKit` - Ability 能力
- `@kit.UIDesignKit` - UI 设计套件
- `@kit.AVSessionKit` - 音视频会话
- `@kit.BasicServicesKit` - 基础服务（事件、设备信息）
- `@kit.ArkData` - 关系型数据库
- `@kit.DistributedServiceKit` - 分布式服务
- `@kit.ImageKit` - 图片处理

### 配置文件
- `module.json5` - 模块配置
  - 设备类型：phone, tablet, 2in1, car, wearable
  - 权限：INTERNET, DISTRIBUTED_DATASYNC
- `oh-package.json5` - 依赖包配置

---

## 子模块详解

### 1. adapter/ - OMSP 协议适配器

**职责**：封装 OMSP 协议的所有 API 调用，提供统一的接口供业务层使用。

**文件**：`src/main/ets/adapter/omsp.ets`

**对外接口**：

```typescript
// 认证相关
OMSPAdapter.GetQRKey(instance: AxiosInstance): Promise<string>
OMSPAdapter.CreateQR(instance: AxiosInstance, unikey: string): Promise<QRCode>
OMSPAdapter.CheckQR(instance: AxiosInstance, unikey: string): Promise<QRCheck>
OMSPAdapter.GetLoginStatus(instance: AxiosInstance): Promise<User>

// 播放列表相关
OMSPAdapter.GetUserPlaylists(instance, uid, limit, offset): Promise<Playlist[]>
OMSPAdapter.GetRecommendPlaylists(instance, limit): Promise<Playlist[]>
OMSPAdapter.GetTopPlaylists(instance, limit): Promise<Playlist[]>
OMSPAdapter.GetPlaylistDetail(instance, id, limit): Promise<Playlist>

// 歌曲相关
OMSPAdapter.GetRecommendSongs(instance, limit): Promise<Song[]>
OMSPAdapter.GetSongDetail(instance, id, uid, br): Promise<Song>
OMSPAdapter.LikeSong(instance, id, like): Promise<void>

// 艺术家相关
OMSPAdapter.GetRecommendArtists(instance, limit): Promise<Artist[]>
OMSPAdapter.GetArtistDetail(instance, id, limit): Promise<Playlist>
OMSPAdapter.LikeAlbum(instance, id, like): Promise<void>

// 专辑相关
OMSPAdapter.GetAlbumDetail(instance, id, limit): Promise<Playlist>
OMSPAdapter.GetSubscribedAlbums(instance, limit, offset): Promise<Album[]>

// 搜索相关
OMSPAdapter.Search(instance, keywords, limit): Promise<SearchResponse>
```

**响应接口**：

| 接口名 | 字段 | 说明 |
|---------|------|------|
| BaseResponse<T> | code, message, data, timestamp | 统一响应格式 |
| QRCode | qrurl, qrimg | 二维码信息 |
| QRCheck | status, cookie | 二维码检查状态（-1 过期，0 等待扫码，1 等待确认，2 成功） |
| SearchResponse | songs, playlists, artists, albums | 综合搜索结果 |

---

### 2. components/ - UI 组件库

| 组件 | 文件 | 功能描述 | 主要参数 |
|------|------|----------|----------|
| CustomTitleBar | CustomTitleBar.ets | 自定义标题栏，支持搜索框、返回按钮、状态栏避让 | title, showBackButton, showSearchBox, onSearchChange |
| MediaCard | MediaCard.ets | 媒体卡片，支持背景图片/视频、标题描述、操作插槽 | backgroundImg, backgroundVideo, title, description, aspectRatioValue |
| ModuleCard | ModuleCard.ets | 模块卡片，用于 ForU 模块展示 | moduleName, moduleColor |
| ContentCard | ContentCard.ets | 内容卡片，支持标题描述和自定义内容插槽 | title, heightValue |
| PlaylistListItem | PlaylistListItem.ets | 歌单列表项，显示封面、名称、歌曲数量 | coverImage, playlistName, trackCount |
| PlaylistSongGrid | PlaylistSongGrid.ets | 歌单歌曲网格，响应式 Grid 布局 | songs, onSongClick, onSongLongPress |
| SongListItem | SongListItem.ets | 歌曲列表项，显示封面、歌名、艺术家、时长 | coverImage, songName, artistName, duration |
| ArtistListItem | ArtistListItem.ets | 艺术家列表项，显示头像、名称、操作按钮 | coverImage, artistName, coverSize |
| SettingItem | SettingItem.ets | 设置项，支持开关/导航/文本三种类型 | type, icon, title, description, value |
| SettingGroup | SettingGroup.ets | 设置分组，包含标题和多个设置项 | title, content |
| PaddedContainer | PaddedContainer.ets | 安全区避让容器，支持四方向安全区避让 | - |
| PlaylistInfoCard | PlaylistInfoCard.ets | 歌单信息卡片，支持动态主题色提取 | playlist, onPlayAll, onShuffle, cardHeight |

---

### 3. utils/ - 工具类集合

| 工具类 | 文件 | 主要方法 | 说明 |
|--------|------|----------|------|
| Logger | Logger.ets | debug(), info(), warn(), error() | 基于 hilog 的日志工具 |
| PreferencesUtil | PreferencesUtil.ets | get/put/delete/clear, getAll/hasKey | 首选项存储，支持同步和异步 |
| Tools | Tools.ets | cover(), shuffle(), sample() | 封面 URL 处理、数组随机、随机取样 |
| WindowUtil | WindowUtil.ets | loadContent() | 窗口初始化、断点监听、安全区处理 |
| SourceRequest | SouceRequest.ets | Create/Get/Reload/All/Has/Keys | Axios 实例管理、请求拦截器 |
| ImageColorExtractor | ImageColorExtractor.ets | extractMainColor, extractMultipleDominantColors, mixColors, adjustColorBrightness | 图片颜色提取、颜色混合、渐变生成 |
| Continue | Continue.ets | enableContinue/disableContinue/setContinueData/getContinueData | 应用接续开关和数据管理 |

---

### 4. viewmodel/ - 视图图模型层

| ViewModel | 文件 | 主要状态和方法 |
|-----------|------|---------------|
| CurrentSourceViewModel | CurrentSourceViewModel.ets | source, userPlaylists, newSongs, recommendPlaylists, recommendArtists, rankPlaylists, loadAll() |
| SourceListViewModel | SourceListViewModel.ets | sources, isLoading, errorMessage, qrCodeVisible, qrCodeUrl, qrCodeStatus, loadSources(), addSource(), updateSource(), deleteSource(), generateQRCode(), clearQRCodeTimer() |
| PlaylistViewModel | PlaylistViewModel.ets | currentIndex, playlist, mode, setMode(), insertSongs(), currentSong/nextSong/prevSong |
| SettingViewModel | SettingViewModel.ets | theme, lang, playBitrate, downloadBitrate, dataSaverMode, maxCacheSize, mainSource, uniformBlur, uniformOpacity, uniformScale, firstOpenVersion |

---

### 5. model/ - 数据模型

| 模型 | 文件 | 主要字段 |
|------|------|----------|
| Source | Source.ets | id, name, type, url, description, token, updated_at, user |
| ContinueData | ContinueData.ets | page, id, sourceId, playlist |
| WindowProperties | WindowProperties.ets | currentBreakpoint, winWidth, winHeight, topRect, bottomRect, decorHeight, leftCutoutRectHeight/Width, rightCutoutRectHeight/Width |
| adapter/* | adapter/ 目录 | Song, Playlist, Artist, Album, User, Lyric, Privilege, Types, StatusResponse, QrCreateResponse, QrCheckResponse, SongMeta |

---

### 6. view/ - 视图组件

| 视图 | 文件 | 功能描述 | 主要依赖 |
|------|------|----------|----------|
| HomeView | HomeView.ets | 首页视图，显示 ForU、推荐歌单、推荐艺术家、排行榜等 | CurrentSourceViewModel, SourceListViewModel, SettingViewModel |
| LibraryView | LibraryView.ets | 库视图，显示用户歌单网格，支持搜索过滤 | CurrentSourceViewModel, SourceListViewModel |
| MyView | MyView.ets | 我的视图，包含数据源管理和设置 | SourceManagementView, SettingsView |
| SettingsView | SettingsView.ets | 设置视图，显示通用设置、播放设置、关于等 | SettingGroup, SettingItem |
| SourceManagementView | SourceManagementView.ets | 数据源管理视图，支持增删改查、二维码登录 | SourceListViewModel, SettingViewModel |

---

### 7. common/ - 常量定义

| 常量类 | 文件 | 主要常量 |
|--------|------|----------|
| AppConstants | AppConstants.ets | USE_NEW_FEATURE - API 版本检测 |
| BreakpointConstants | BreakpointConstants.ets | BREAKPOINT_SM/MD/LG, RANGE_SM/MD/LG |
| SourceDatabaseConstants | SourceDatabaseConstants.ets | 数据库配置、表结构、字段名 |
| EmitEventConstants | EmitEventConstants.ets | SOURCE_URL_TOKEN_UPDATED - 事件 ID |

---

### 8. data/ - 数据源管理

**文件**：`src/main/ets/data/SourceDataSource.ets`

**主要方法**：
- `initialize()` - 初始化关系型数据库
- `getAllSources()` - 获取所有数据源
- `getSourceById()` - 根据 ID 获取数据源
- `insertSource()` - 插入数据源
- `updateSource()` - 更新数据源
- `deleteSource()` - 删除数据源
- `sync()` - 推送/拉取同步
- `syncFromRemoteDevices()` - 从远程设备拉取并合并数据
- `fullSync()` - 完整同步
- `onRemoteDataChange()` - 注册远程数据变化回调

**分布式同步策略**：
1. 首次同步 - 拉取所有远程设备的数据，合并到本地（按时间戳去重，保留最新）
2. 推送本地数据到远程设备
3. 通过 dataChange 事件进行增量同步

---

## 数据模型

### 核心数据模型（adapter/ 目录）
| 文件 | 描述 | 主要字段 |
|------|------|----------|
| `Song.ets` | 歌曲模型 | id, name, artists, album, duration, privilege, lyric, sourceId |
| `Playlist.ets` | 播放列表模型 | id, name, type, cover, description, size, tracks, sourceId |
| `Artist.ets` | 艺术家模型 | id, name, avatar, sourceId |
| `Album.ets` | 专辑模型 | id, name, cover, artists, sourceId |
| `User.ets` | 用户模型 | id, name, avatar, sourceId |
| `Lyric.ets` | 歌词模型 | version, lyric |
| `Privilege.ets` | 权限模型 | st, pl, dl, sp |
| `Types.ets` | 类型定义 | id, PlaylistType, Bitrate |

### 辅助数据模型
| 文件 | 描述 | 主要字段 |
|------|------|----------|
| `Source.ets` | 数据源模型 | id, name, type, url, description, token, updated_at, user |
| `ContinueData.ets` | 应用接续数据 | page, id, sourceId, playlist |
| `WindowProperties.ets` | 窗口属性 | currentBreakpoint, winWidth, winHeight, topRect, bottomRect |

---

## 测试与质量

### 测试文件
| 文件 | 类型 |
|------|------|
| `src/test/List.test.ets` | 单元测试 |
| `src/test/LocalUnit.test.ets` | 本地单元测试 |
| `src/ohosTest/ets/test/Ability.test.ets` | Ability 测试 |
| `src/ohosTest/etsets/test/List.test.ets` | 列表 UI 测试 |

### 质量工具
- `code-linter.json5` - 代码检查配置
- `obfuscation-rules.txt` - 混淆规则

---

## 常见问题 (FAQ)

### Q: 如何添加新的 OMSP API？
A: 在 `adapter/omsp.ets` 中添加静态方法，遵循现有命名约定和响应式模式。

### Q: 如何创建新页面？
A:
1. 在 `pages/` 或 `pages/dialog/` 目录创建 ArkTS 文件
2. 导出 `@Builder` 函数（如 `PageNameBuilder`）
3. 在 `src/main/resources/base/profile/route_map.json` 中注册路由

### Q: 如何持久化数据？
A:
- 数据源配置：使用 `SourceDataSource`（基于 RelationalStore）
- 用户设置：使用 `PreferencesUtil`（基于 Preferences API）

### Q: 如何实现响应式布局？
A:
- 使用 `BreakpointConstants` 定义断点
- 使用 `WindowProperties` 获取当前断点和安全区
- 根据断点动态调整布局

### Q: 如何实现跨设备数据同步？
A:
- 使用 `SourceDataSource` 的分布式同步功能
- 数据通过 RelationalStore 自动同步到组网内设备
- 使用 `updated_at` 字段解决冲突（最后写入优先策略）

---

## 相关文件清单

### 核心源码
- `src/main/ets/adapter/omsp.ets` - OMSP 协议适配器
- `src/main/ets/entryability/EntryAbility.ets` - 应用入口
- `src/main/ets/entrybackupability/EntryBackupAbility.ets` - 备份能力
- `src/main/ets/data/SourceDataSource.ets` - 数据源管理器
- `src/main/ets/pages/Index.ets` - 主页面

### 视图
- `src/main/ets/view/HomeView.ets` - 首页视图
- `src/main/ets/view/LibraryView.ets` - 库视图
- `src/main/ets/view/MyView.ets` - 我的视图
- `src/main/ets/view/SettingsView.ets` - 设置视图
- `src/main/ets/view/SourceManagementView.ets` - 数据源管理视图

### 视图模型
- `src/main/ets/viewmodel/CurrentSourceViewModel.ets` - 当前数据源
- `src/main/ets/viewmodel/SourceListViewModel.ets` - 数据源列表
- `src/main/ets/viewmodel/PlaylistViewModel.ets` - 播放列表
- `src/main/ets/viewmodel/SettingViewModel.ets` - 设置

### 工具
- `src/main/ets/utils/Logger.ets` - 日志
- `src/main/ets/utils/PreferencesUtil.ets` - 首选项
- `src/main/ets/utils/Tools.ets` - 通用工具
- `src/main/ets/utils/WindowUtil.ets` - 窗口工具
- `src/main/ets/utils/SouceRequest.ets` - 数据源请求工具
- `src/main/ets/utils/ImageColorExtractor.ets` - 图片颜色提取
- `src/main/ets/utils/Continue.ets` - 应用接续

### 常量
- `src/main/ets/common/AppConstants.ets` - 应用常量
- `src/main/ets/common/BreakpointConstants.ets` - 断点常量
- `src/main/ets/common/SourceDatabaseConstants.ets` - 数据库常量
- `src/main/ets/common/EmitEventConstants.ets` - 事件常量

### 配置
- `module.json5` - 模块配置
- `oh-package.json5` - 依赖配置
- `build-profile.json5` - 构建配置
- `obfuscation-rules.txt` - 混淆规则

### 资源
- `src/main/resources/base/element/string.json` - 字符串资源
- `src/main/resources/base/element/color.json` - 颜色资源
- `src/main/resources/base/element/float.json` - 浮点数资源
- `src/main/resources/base/profile/main_pages.json` - 页面配置
- `src/main/resources/base/profile/route_map.json` - 路由映射
