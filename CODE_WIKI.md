# 藏星（cangxing / fav_app）Code Wiki

> 本地优先的内容收藏 App：把链接 / 文章 / 评论一键收藏到本地，AI 自动生成标签并归类到已有文件夹，随时全文阅读、回顾，还能和文章直接对话。
>
> 仓库：<https://github.com/Xinzhikab/cangxing>

---

## 目录

- [1. 项目概述](#1-项目概述)
- [2. 技术栈与依赖](#2-技术栈与依赖)
- [3. 整体架构](#3-整体架构)
- [4. 目录结构](#4-目录结构)
- [5. 核心模块职责](#5-核心模块职责)
  - [5.1 core 核心层](#51-core-核心层)
  - [5.2 collections 收藏模块](#52-collections-收藏模块)
  - [5.3 save 转录与保存模块](#53-save-转录与保存模块)
  - [5.4 read 阅读模块](#54-read-阅读模块)
  - [5.5 learning 学习回顾模块](#55-learning-学习回顾模块)
  - [5.6 settings 设置模块](#56-settings-设置模块)
  - [5.7 onboarding 引导模块](#57-onboarding-引导模块)
- [6. 关键类与函数说明](#6-关键类与函数说明)
  - [6.1 数据模型](#61-数据模型)
  - [6.2 数据访问层（Repository）](#62-数据访问层repository)
  - [6.3 服务层（Service）](#63-服务层service)
  - [6.4 状态管理（Provider）](#64-状态管理provider)
- [7. 数据存储设计](#7-数据存储设计)
- [8. 核心业务流程](#8-核心业务流程)
  - [8.1 转录保存流程](#81-转录保存流程)
  - [8.2 全文搜索流程](#82-全文搜索流程)
  - [8.3 AI 标签与文件夹归一化](#83-ai-标签与文件夹归一化)
  - [8.4 回顾提醒流程](#84-回顾提醒流程)
- [9. 路由与页面导航](#9-路由与页面导航)
- [10. 主题与 Material You](#10-主题与-material-you)
- [11. Provider 依赖关系图](#11-provider-依赖关系图)
- [12. Android 平台配置](#12-android-平台配置)
- [13. 项目运行方式](#13-项目运行方式)
- [14. 工程约定与设计要点](#14-工程约定与设计要点)

---

## 1. 项目概述

**藏星**是一款本地优先（local-first）的 Flutter 内容收藏应用。它的核心定位是：

- **多形式收藏**：链接 / 文章 / 评论，支持剪贴板自动识别与系统分享接入
- **智能转录**：WebView/Dio 抓取正文与图片（含轮播图懒加载触发），标题、作者、时间、平台取自页面提取结果；AI 仅负责生成标签
- **标签与文件夹归一**：AI 推荐自动匹配本地已有标签与文件夹，**不新建文件夹**，保存前统一确认
- **与文章对话**：以全文为上下文的多轮问答
- **本地全文搜索**：SQLite + FTS5，毫秒级检索
- **本地优先**：数据全部存本地（SQLite + 文件系统），目录拷贝即可迁移；LLM API 可选可配置
- **Material You**：MD3 动态取色，界面配色跟随壁纸

应用包名为 `fav_app`，入口标题 `藏星`，无任何自有后端服务器，所有数据与计算均在本地完成，LLM 调用为可选的外部依赖。

---

## 2. 技术栈与依赖

### 2.1 核心技术栈

| 领域 | 技术 |
|---|---|
| 框架 | Flutter（Dart SDK ≥ 3.0.0） |
| 状态管理 | Riverpod（`flutter_riverpod` 2.6） |
| 路由 | go_router 14.6（`StatefulShellRoute` + 预测性返回） |
| 网络 | Dio 5.7（禁用自动状态码校验，手动检查） |
| HTML 解析 | `html` 0.15 |
| 本地数据库 | sqflite + sqflite_common_ffi + sqlite3_flutter_libs（**捆绑 FTS5**） |
| 文件系统 | path_provider + path |
| 偏好存储 | shared_preferences |
| Markdown | flutter_markdown + markdown |
| WebView | webview_flutter 4.8 |
| 分享接收 | share_handler 0.0.25 |
| 本地通知 | flutter_local_notifications 18 + timezone |
| 邮件 | mailer 6.3 |
| 日历 | add_2_calendar 3.0 |
| 动态取色 | dynamic_color 1.7（Monet） |
| 其它 | uuid、intl、file_picker、permission_handler、url_launcher |

### 2.2 依赖覆盖（dependency_overrides）

`file_picker` 通过本地路径 `third_party/file_picker` 覆盖官方版本，原因：`flutter_plugin_android_lifecycle` 依赖要求 `compileSdk 36`，本地版本已适配。

完整依赖见 [pubspec.yaml](file:///h:/xiangmu/pubspec.yaml)。

---

## 3. 整体架构

藏星采用 **Feature-First 分层架构**，结合 Riverpod 的依赖注入实现松耦合。整体分为四层：

```
┌─────────────────────────────────────────────────────────┐
│  presentation（页面 / 组件）                              │
│  Pages · Widgets · Dialogs                              │
├─────────────────────────────────────────────────────────┤
│  state（Provider / Controller）                          │
│  Riverpod Providers · AsyncNotifier · StateNotifier     │
├─────────────────────────────────────────────────────────┤
│  domain / data（Repository 接口与实现）                   │
│  CollectionRepository · CategoryRepository              │
├─────────────────────────────────────────────────────────┤
│  services（基础设施）                                     │
│  DatabaseService · FileStorageService · LlmClient ·     │
│  WebContentFetcher · ImageDownloader · ReminderScheduler│
└─────────────────────────────────────────────────────────┘
```

**架构特点**：

1. **本地优先**：无后端，所有状态由本地 SQLite + 文件系统支撑，LLM 是可选增强项
2. **双存储模型**：元数据存 SQLite（便于查询/排序/分组），正文存文件系统（`meta/*.json` + `content/*.md` + `images/{id}/*`），两者通过 `id` 关联
3. **Provider 驱动**：Riverpod Provider 既做依赖注入（Repository/Service），又做状态管理（列表/设置/样式），通过 `ref.invalidate` 手动失效缓存
4. **领域隔离**：每个 feature 目录内自治，`data`（模型/仓库/服务）与 `presentation`（页面/组件）分离

---

## 4. 目录结构

```
lib/
├── main.dart                      # 入口：初始化 FFI SQLite + ProviderScope
├── app.dart                       # MaterialApp 根组件（动态取色 + 路由 + 通知监听）
└── core/                          # 核心层（跨 feature 共享）
    ├── constants/
    │   ├── app_constants.dart     # 全局常量（DB 版本、目录名、枚举）
    │   └── category_templates.dart# 文件夹推荐模板与批量导入
    ├── router/
    │   └── app_router.dart        # go_router 路由表 + 引导重定向
    ├── theme/
    │   └── app_theme.dart         # Material You 主题构建
    └── utils/
        └── storage_path_provider.dart # 本地存储根目录解析
└── features/                      # 功能模块（feature-first）
    ├── collections/               # 收藏、分类、标签、笔记
    ├── save/                      # 转录与保存（LLM、抓取、图片下载）
    ├── read/                      # 阅读页、文章 AI 对话
    ├── learning/                  # 回顾队列与提醒通知
    ├── onboarding/                # 首次启动引导
    └── settings/                  # 设置（转录 & AI、外观、Cookie、备份等）
test/
└── widget_test.dart
third_party/
└── file_picker/                  # 本地覆盖的 file_picker 插件
android/ · ios/                   # 原生壳工程
```

每个 feature 内部统一为 `data/`（models · providers · repositories · services）与 `presentation/`（pages · widgets）两层。

---

## 5. 核心模块职责

### 5.1 core 核心层

#### [app_constants.dart](file:///h:/xiangmu/lib/core/constants/app_constants.dart)

定义全局常量与枚举：

- `AppConstants`：`dbName = 'fav_app.db'`、`dbVersion = 5`、`pageSize = 20`、目录名 `meta/content/images`、`defaultCategoryName = '未分类'`
- `CollectionType`：`article` / `comment`
- `CollectionStatus`：`unread` / `read` / `learning` / `done`（已读/未读功能已移除，状态筛选仅保留 `learning` / `done`）
- `SourcePlatform`：`douyin` / `xiaoheihe` / `coolapk` / `other`
- 对应枚举：`ItemType`、`ItemStatus`、`ItemPlatform`

#### [category_templates.dart](file:///h:/xiangmu/lib/core/constants/category_templates.dart)

- `kCategoryTemplate`：6 个推荐顶层文件夹（游戏攻略 / 数码评测 / 电脑技巧 / 软件工具 / 教程学习 / 杂谈娱乐）
- `importCategoryTemplate(repo, names)`：批量导入模板，跳过已存在同名顶层文件夹，返回新建数量

#### [app_router.dart](file:///h:/xiangmu/lib/core/router/app_router.dart)

`AppRouter.createRouter(ref)` 构建 `GoRouter`：

- `initialLocation: '/collections'`
- `redirect`：未完成引导 → 强制跳 `/onboarding`；已完成却访问引导页 → 跳回 `/collections`
- `StatefulShellRoute.indexedStack`：4 分支底部导航（收藏 / 想学 / 分类 / 设置），保留各分支状态
- 子路由：`/categories/articles`、`/save`、`/read/:id`、`/read/:id/chat`、`/settings/{llm,list-style,cookies,smtp}`

#### [app_theme.dart](file:///h:/xiangmu/lib/core/theme/app_theme.dart)

`AppTheme` 类构建 Material You 主题：

- `lightTheme({dynamicScheme})` / `darkTheme({dynamicScheme})`：传入 Monet 动态配色，否则回退种子色 `#2196F3`
- MD3 细节：左对齐 AppBar 标题、`primaryContainer` FAB、填充式输入框、胶囊 `NavigationBar` 指示器、28dp 圆角对话框
- `PredictiveBackPageTransitionsBuilder`：Android 预测性返回动画

#### [storage_path_provider.dart](file:///h:/xiangmu/lib/core/utils/storage_path_provider.dart)

`StoragePathProvider`：本地存储根目录为 `getApplicationDocumentsDirectory()/fav_data`，提供 `getRootDir()` 与 `ensureDir(subDir)`。

### 5.2 collections 收藏模块

负责收藏内容的存储、检索、分类、标签、笔记。

#### 数据层

- **[Collection](file:///h:/xiangmu/lib/features/collections/data/models/collection.dart)**：核心数据模型（见 [6.1](#61-数据模型)）
- **[Category](file:///h:/xiangmu/lib/features/collections/data/models/category.dart)**：分类节点（id / name / parentId / sortOrder / createdAt），支持树形结构
- **[CollectionNote](file:///h:/xiangmu/lib/features/collections/data/models/collection_note.dart)**：评论区笔记（id / collectionId / content / createdAt）
- **[DatabaseService](file:///h:/xiangmu/lib/features/collections/data/services/database_service.dart)**：单例，管理 SQLite 初始化与版本迁移（见 [7](#7-数据存储设计)）
- **[FileStorageService](file:///h:/xiangmu/lib/features/collections/data/services/file_storage_service.dart)**：三层文件存储（meta JSON / content MD / images 目录）
- **[CollectionRepositoryImpl](file:///h:/xiangmu/lib/features/collections/data/repositories/collection_repository_impl.dart)**：CRUD + FTS 搜索 + 分组统计 + 笔记 + 标签注册表（见 [6.2](#62-数据访问层repository)）
- **[CategoryRepositoryImpl](file:///h:/xiangmu/lib/features/collections/data/repositories/category_repository_impl.dart)**：分类树 CRUD，删除时递归子分类并将受影响收藏回退「未分类」

#### 状态层

- `collectionRepositoryProvider` / `categoryRepositoryProvider`：仓库实例
- `collectionsListProvider`（StateNotifier）+ `collectionsFilterProvider`：列表与筛选条件
- `categoryTreeProvider` / `categoriesListProvider`：分类树
- `collectionDetailProvider`（autoDispose family）：单篇详情
- `categoryArticlesProvider`（family）：按分类/平台/作者/标签筛选
- `groupStatsProvider`：三组分组统计
- `allTagsProvider`：标签计数聚合
- `collectionNotesProvider`（family）：笔记列表

#### 页面层

- **[CollectionsPage](file:///h:/xiangmu/lib/features/collections/presentation/pages/collections_page.dart)**：主页，搜索/筛选/排序/批量选择/分类抽屉
- **[CategoriesPage](file:///h:/xiangmu/lib/features/collections/presentation/pages/categories_page.dart)**：TabBar 四维度浏览（文件夹/标签/平台/作者）
- **[CategoryArticlesPage](file:///h:/xiangmu/lib/features/collections/presentation/pages/category_articles_page.dart)**：分类文章列表
- **[CollectionsShell](file:///h:/xiangmu/lib/features/collections/presentation/widgets/collections_shell.dart)**：底部导航容器 + 剪贴板检测 + 分享接入
- **[MetaEditDialog](file:///h:/xiangmu/lib/features/collections/presentation/widgets/meta_edit_dialog.dart)**：元信息编辑共享组件（标题/作者/平台/时间/标签）

### 5.3 save 转录与保存模块

负责内容抓取、AI 转录、标签生成、图片下载、保存入库。

#### 数据层

- **[TranscriptionResult](file:///h:/xiangmu/lib/features/save/data/models/transcription_models.dart)**：转录结果（tags / category / contentMd / imageUrls / aiReasoning / aiRawOutput / aiError）
- **[TranscriptionProgress](file:///h:/xiangmu/lib/features/save/data/models/transcription_models.dart)**：进度（step: fetching/transcribing/downloadingImages/done/failed）
- **[TranscriptionException](file:///h:/xiangmu/lib/features/save/data/models/transcription_models.dart)**：`{network, llmError, parseError, timeout, unknown}`
- **[WebContentFetcher](file:///h:/xiangmu/lib/features/save/data/services/web_content_fetcher.dart)**：Dio + html 解析抓取网页，块级感知文本提取 + 图片占位符
- **[SiteRuleRegistry](file:///h:/xiangmu/lib/features/save/data/services/site_rule.dart)**：站点专属规则（小黑盒等），按域名匹配选择器与图片过滤
- **[LlmClient](file:///h:/xiangmu/lib/features/save/data/services/llm_client.dart)**：OpenAI 兼容接口客户端（transcribe / chat / fetchModels / testConnection）
- **[ImageDownloader](file:///h:/xiangmu/lib/features/save/data/services/image_downloader.dart)**：图片下载，带浏览器 UA + Referer 防盗链
- **[TranscriptionService](file:///h:/xiangmu/lib/features/save/data/services/transcription_service.dart)**：编排抓取→图片下载→AI 转录→占位符替换
- **[ShareInputService](file:///h:/xiangmu/lib/features/save/data/services/share_input_service.dart)**：系统分享接收
- **[TypeDetector](file:///h:/xiangmu/lib/features/save/data/utils/type_detector.dart)**：极简类型识别（含"回复@"→评论，否则文章）
- **[SaveController](file:///h:/xiangmu/lib/features/save/data/providers/save_controller.dart)**：转录编排核心，含标签/文件夹归一化（见 [6.4](#64-状态管理provider) 与 [8](#8-核心业务流程)）

#### 页面层

- **[SavePage](file:///h:/xiangmu/lib/features/save/presentation/pages/save_page.dart)**：粘贴链接/文本→类型识别→选分类→转录保存
- **[WebExtractPage](file:///h:/xiangmu/lib/features/save/presentation/pages/web_extract_page.dart)**：`HeadlessWebExtractor` 无头 WebView 提取 JS 渲染站点
- **[TagConfirmDialog](file:///h:/xiangmu/lib/features/save/presentation/widgets/tag_confirm_dialog.dart)**：标签确认弹窗

### 5.4 read 阅读模块

- **[ReadPage](file:///h:/xiangmu/lib/features/read/presentation/pages/read_page.dart)**：Markdown 正文 + 全屏评论区（PageView），排版设置、笔记、想学标记、分类修改、删除
- **[ArticleChatPage](file:///h:/xiangmu/lib/features/read/presentation/pages/article_chat_page.dart)**：以全文（截断 12000 字）为上下文的多轮 AI 对话

### 5.5 learning 学习回顾模块

- **[LearningQueueProvider](file:///h:/xiangmu/lib/features/learning/data/providers/learning_queue_provider.dart)**：按到期日分组（overdue/today/within3Days/later）
- **[ReminderScheduler](file:///h:/xiangmu/lib/features/learning/data/services/reminder_scheduler.dart)**：三渠道提醒（本地通知 / SMTP 邮件 / 日历事件）
- **[ReviewNotificationService](file:///h:/xiangmu/lib/features/learning/data/services/review_notification_service.dart)**：本地通知服务
- **[LearningPage](file:///h:/xiangmu/lib/features/learning/presentation/pages/learning_page.dart)**：想学队列展示与操作

### 5.6 settings 设置模块

- **[AppSettings](file:///h:/xiangmu/lib/features/settings/data/providers/app_settings_provider.dart)**：15 字段配置（LLM / 提示词 / 动态取色 / 剪贴板检测 / SMTP / 提醒渠道 / 引导完成等）
- **[CookieNotifier](file:///h:/xiangmu/lib/features/settings/data/providers/cookie_provider.dart)**：站点 Cookie 管理（按域名匹配）
- **[ListFieldStyleProvider](file:///h:/xiangmu/lib/features/settings/data/providers/list_field_style_provider.dart)**：首页卡片样式
- **[ReadingStyleProvider](file:///h:/xiangmu/lib/features/settings/data/providers/reading_style_provider.dart)**：阅读排版（字号/行距/页边距）
- **[StorageStatsProvider](file:///h:/xiangmu/lib/features/settings/data/providers/storage_stats_provider.dart)**：存储占用统计
- **[BackupService](file:///h:/xiangmu/lib/features/settings/data/services/backup_service.dart)**：备份导出/导入（目录拷贝）
- **[MaintenanceService](file:///h:/xiangmu/lib/features/settings/data/services/maintenance_service.dart)**：重建 FTS 索引、清理孤儿图片
- 页面：[SettingsPage](file:///h:/xiangmu/lib/features/settings/presentation/pages/settings_page.dart)、[LlmSettingsPage](file:///h:/xiangmu/lib/features/settings/presentation/pages/llm_settings_page.dart)、[CookiesPage](file:///h:/xiangmu/lib/features/settings/presentation/pages/cookies_page.dart)、[ListStyleSettingsPage](file:///h:/xiangmu/lib/features/settings/presentation/pages/list_style_settings_page.dart)、[SmtpSettingsPage](file:///h:/xiangmu/lib/features/settings/presentation/pages/smtp_settings_page.dart)

### 5.7 onboarding 引导模块

- **[OnboardingPage](file:///h:/xiangmu/lib/features/onboarding/presentation/pages/onboarding_page.dart)**：3 页功能介绍 + 1 页文件夹模板选择，完成后导入模板并跳转主页

---

## 6. 关键类与函数说明

### 6.1 数据模型

#### `Collection`（[collection.dart](file:///h:/xiangmu/lib/features/collections/data/models/collection.dart)）

收藏内容核心模型，不可变值对象。

| 字段 | 类型 | 说明 |
|---|---|---|
| `id` | `String` | UUID v4 主键 |
| `title` | `String` | 标题（取自页面精确标题） |
| `type` | `String` | `article` / `comment` |
| `sourcePlatform` | `String` | `douyin/xiaoheihe/coolapk/other` |
| `sourceUrl` | `String` | 原始链接 |
| `author` | `String` | 作者（页面提取） |
| `publishedAt` | `DateTime?` | 发布时间（页面提取） |
| `collectedAt` | `DateTime` | 收藏时间 |
| `category` | `List<String>` | 分类路径（如 `['游戏攻略']`） |
| `images` | `List<String>` | 本地图片路径列表 |
| `tags` | `List<String>` | 标签列表 |
| `note` | `String` | 最新笔记（供搜索） |
| `status` | `String` | `read` / `learning` / `done` |
| `reviewDueAt` | `DateTime?` | 回顾到期日 |
| `rawInput` | `String` | 原始输入 |
| `contentMd` | `String` | 正文 Markdown（仅运行时，不入库） |

提供 `fromJson` / `toJson` / `copyWith`。

#### `Category`、`CollectionNote`、`TranscriptionResult`、`TranscriptionProgress`、`SiteCookie`、`AppSettings`、`ListFieldStyle`、`ReadingStyle`、`StorageStats`

均为不可变值对象，配套 `fromJson`/`toJson`/`copyWith`。

### 6.2 数据访问层（Repository）

#### `CollectionRepository` / `CollectionRepositoryImpl`

实现位于 [collection_repository_impl.dart](file:///h:/xiangmu/lib/features/collections/data/repositories/collection_repository_impl.dart)，依赖 `DatabaseService` + `FileStorageService`。

关键方法：

```dart
// CRUD
Future<List<Collection>> list({categoryPath, platform, author, status, tag, sortBy, descending})
Future<Collection?> get(String id)
Future<Collection> create(Collection col, {required String contentMd})
Future<Collection> update(Collection col)
Future<void> delete(String id)

// 全文搜索：FTS5 前缀匹配 + LIKE 中文兜底
Future<List<Collection>> search(String keyword, {int limit = 50})

// 分组统计
Future<List<Map<String, int>>> groupByPlatform() / groupByAuthor() / groupByStatus()

// 评论区笔记
Future<List<CollectionNote>> listNotes(String collectionId)
Future<CollectionNote> addNote(CollectionNote note)
Future<void> deleteNote(String id)

// 标签注册表
Future<List<String>> listTags()
Future<void> addTag(String name) / deleteTag(String name) / renameTag(String oldName, String newName)
```

设计要点：
- `create`/`update` 同步写入 SQLite 与 FTS 索引（`collections_fts`）
- `_syncNoteForSearch`：笔记变更时同步 `collections.note` 列与 FTS，保证笔记可被搜索
- `deleteTag`/`renameTag` 在事务内同步更新所有收藏的 `tags_json`
- `groupByStatus` 过滤掉 `read`，仅保留 `learning`/`done`

#### `CategoryRepository` / `CategoryRepositoryImpl`

- `get ready`：初始化完成 Future（构造时调用 `ensureDefaultCategory()`）
- `childrenOf(parentId)`、`create`、`update`、`delete`
- `delete`：递归删除子分类，受影响收藏回退「未分类」（仅改 meta + DB `category_json`，不触发 FTS 重建，避免全量更新卡死）

### 6.3 服务层（Service）

#### `WebContentFetcher`（[web_content_fetcher.dart](file:///h:/xiangmu/lib/features/save/data/services/web_content_fetcher.dart)）

Dio 抓取网页正文，依赖 `SiteRuleRegistry` 与 `cookieResolver`。

关键方法：
- `static bool isLikelyUrl(String input)`：判断是否 URL
- `Future<FetchedContent> fetch(String url)`：抓取并返回正文（含 `[图N]` 占位符）+ 图片地址
- `_blockAwareText`：按 DOM 遍历在块级元素边界补换行（解决 `Element.text` 不分段问题）
- `_normalizeText`：压缩空白，规范换行
- `_visibleTextWithPlaceholders`：图片替换为 `[图N]` 占位符，过滤头像/图标/表情
- `_collectImages`：收集正文相关图片地址（支持 `data-src` 懒加载）

请求头强制带浏览器 UA，`validateStatus: (_) => true` 禁用自动状态码校验。

#### `LlmClient`（[llm_client.dart](file:///h:/xiangmu/lib/features/save/data/services/llm_client.dart)）

OpenAI 兼容接口客户端，依赖 `Dio`。

关键方法：
- `Future<TranscriptionResult> transcribe({config, rawText, collectionType, systemPrompt})`：转录，`temperature:0` + `response_format:json_object`，默认提示词要求 AI 仅输出 `{"tags":[...]}`；支持思考模型（`reasoning_content` 兜底解析）
- `Future<String> chat({config, messages})`：多轮对话（文章 AI 对话用）
- `Future<List<String>> fetchModels({config})`：查询可用模型
- `Future<void> testConnection({config})`：连通性测试

错误细分：超时→`timeout`、5xx→`llmError`、网络→`network`、解析失败→`parseError`。

#### `TranscriptionService`（[transcription_service.dart](file:///h:/xiangmu/lib/features/save/data/services/transcription_service.dart)）

编排转录流水线，依赖 `WebContentFetcher` + `LlmClient` + `ImageDownloader`。

`transcribe(...)` 流程：
1. 抓取正文（URL 模式，支持外部预提取内容跳过抓取）
2. 下载图片到本地（带进度回调）
3. AI 提取标签（失败不影响正文保存，记入 `aiError`）
4. 占位符 `[图N]` 替换为本地图片路径

#### `ImageDownloader`（[image_downloader.dart](file:///h:/xiangmu/lib/features/save/data/services/image_downloader.dart)）

`downloadImages(collectionId, urls)`：逐张下载，返回与 urls 一一对应的结果（成功为本地路径，失败为 null，避免占位符错位）；带浏览器 UA + 同域 Referer 防盗链。

#### `HeadlessWebExtractor`（[web_extract_page.dart](file:///h:/xiangmu/lib/features/save/presentation/pages/web_extract_page.dart)）

无头 WebView 提取 JS 渲染站点（小黑盒等 Dio 抓不全的页面）：
- 在根 Overlay 挂离屏 `WebViewWidget`（`left:-10000`，真实尺寸 412×915 保证渲染）
- 注入域名 Cookie（`WebViewCookieManager`）
- `_triggerLazyImages`：滚动 + 三重 fallback（Swiper API → 导航点点击 → DOM 操作）触发轮播懒加载
- 注入大段 JS 提取正文，图片多属性兜底（`data-src`/`data-original`/`data-lazy-src`）
- 标题/作者/时间多重兜底（精确选择器 → og:title → h1 → document.title）
- 硬超时 60s 兜底

#### `BackupService`、`MaintenanceService`、`ReminderScheduler`、`ReviewNotificationService`

- **BackupService**：`export()` 导出 `fav_backup_{stamp}` 目录（拷贝 meta/content/images + db）；`doImport()` 导入（旧数据备份为 `.importing_{ts}`）
- **MaintenanceService**：`rebuildSearchIndex()` 重建 FTS、`cleanOrphanImages()` 清理无主图片目录
- **ReminderScheduler**：三渠道提醒，按 `AppSettings.reminderChannels` 调度；`LocalNotificationReminder` 用 `zonedSchedule` + `exactAllowWhileIdle`
- **ReviewNotificationService**：本地通知服务，`payloadNotifier` 暴露点击通知 payload

### 6.4 状态管理（Provider）

项目混合使用多种 Riverpod 形态：

| Provider | 类型 | 职责 |
|---|---|---|
| `collectionRepositoryProvider` | `Provider` | 仓库实例 |
| `categoryRepositoryProvider` | `Provider` | 分类仓库实例 |
| `collectionsListProvider` | `StateNotifierProvider` | 收藏列表（带筛选） |
| `collectionsFilterProvider` | `StateProvider<CollectionsFilter>` | 筛选条件 |
| `collectionDetailProvider` | `FutureProvider.autoDispose.family<Collection?, String>` | 单篇详情 |
| `categoryArticlesProvider` | `FutureProvider.family<List<Collection>, CategoryArticlesFilter>` | 分类文章 |
| `collectionNotesProvider` | `FutureProvider.family<List<CollectionNote>, String>` | 笔记列表 |
| `categoryTreeProvider` | `Provider<AsyncValue<List<CategoryNode>>>` | 分类树 |
| `categoriesListProvider` | `FutureProvider<List<Category>>` | 扁平分类列表 |
| `groupStatsProvider` | `FutureProvider<Map<String, List<Map<String, int>>>>` | 三组统计 |
| `allTagsProvider` | `FutureProvider<Map<String, int>>` | 标签计数 |
| `saveControllerProvider` | `AsyncNotifierProvider<SaveController, SaveState>` | 转录编排 |
| `transcriptionServiceProvider` | `Provider` | 转录服务 |
| `webContentFetcherProvider` | `Provider` | 抓取器 |
| `llmClientProvider` | `Provider` | LLM 客户端 |
| `llmConfigFromSettingsProvider` | `Provider<LlmConfig?>` | 从设置构造 LLM 配置 |
| `imageDownloaderProvider` | `Provider` | 图片下载器 |
| `shareSubscriptionProvider` | `Provider<StreamSubscription>` | 分享订阅 |
| `appSettingsProvider` | `AsyncNotifierProvider` | 应用设置（乐观更新） |
| `cookieListProvider` | `NotifierProvider` | 站点 Cookie |
| `listFieldStyleProvider` | `NotifierProvider` | 卡片样式 |
| `readingStyleProvider` | `NotifierProvider` | 阅读排版 |
| `storageStatsProvider` | `FutureProvider` | 存储统计 |
| `learningQueueProvider` | `FutureProvider<Map<LearningGroup, List<Collection>>>` | 想学队列 |
| `reviewNotificationServiceProvider` | `Provider` | 通知服务 |
| `notificationPayloadProvider` | `Provider<ValueListenable<String?>>` | 通知 payload |

**`SaveController`** 是转录编排的核心，关键方法：

- `save({rawInput, type, categoryPath, saveOnlyRaw, preFetchedContent, preFetchedImages, preFetchedAuthor, preFetchedPublishedAt, preFetchedTitle, onConfirmTags})`：完整转录保存流程
- `_buildPrompt(base, tags, categories)`：拼装提示词，追加已有标签与本地文件夹列表引导 AI
- `_normalizeTags(aiTags, existingTags)`：标签模糊归一化（忽略大小写完全匹配 → 互相包含带长度护栏 → 保留原词）
- `_normalizeCategory(aiCategory, existingCategories)`：文件夹归一化（必须命中本地已有，未命中返回空串，**绝不新建**）
- `_collectExistingTags()` / `_collectExistingCategories()`：汇总已有标签/文件夹（注册表 + 实际使用）
- `_detectPlatform(rawInput)`：按 URL 域名确定性判断平台
- `_parseDate(s)`：解析发布时间（支持 `2026-08-02` 与 `08-02` 补年份，不合理返回 null）
- `reset()`：重置状态（保存页每次进入调用，清掉上次成功/失败条幅）

**`AppSettings`** 字段（15 个，SharedPreferences 持久化）：

| 字段 | 默认值 | 说明 |
|---|---|---|
| `llmBaseUrl` / `llmApiKey` / `llmModel` | `''` | LLM 配置（空 baseUrl 兜底 `https://api.openai.com/v1`） |
| `transcriptionPrompt` | 标签提取预设 | 转录提示词（启动自动迁移旧版） |
| `defaultReviewIntervalDays` | `1` | 默认复习间隔 |
| `hasCompletedOnboarding` | `false` | 引导完成标志 |
| `reminderChannels` | `{'local'}` | 提醒渠道集合（local/smtp/calendar） |
| `smtpHost`/`smtpPort`/`smtpSsl`/`smtpUsername`/`smtpPassword`/`smtpRecipient` | `''`/`465`/`true`/... | SMTP 配置 |
| `dynamicColor` | `true` | Monet 动态取色开关 |
| `clipboardDetection` | `true` | 剪贴板链接检测开关 |

`AppSettingsNotifier.updateSettings` 采用**乐观更新**：先下发状态再持久化，失败回滚。

---

## 7. 数据存储设计

### 7.1 三层文件布局

```
getApplicationDocumentsDirectory()/
└── fav_data/
    ├── meta/        # {id}.json   — 收藏元数据（Collection.toJson）
    ├── content/     # {id}.md     — 正文 Markdown
    └── images/      # {id}/img_001.jpg — 图片
└── databases/
    └── fav_app.db   # SQLite 数据库
```

**设计取舍**：元数据入 SQLite 便于查询/排序/分组统计，正文存文件系统避免大文本撑大数据库、便于备份与迁移。两者通过 `id` 关联，`_rowToCollection` 在读行时回填 `contentMd`。

### 7.2 SQLite 表结构（[database_service.dart](file:///h:/xiangmu/lib/features/collections/data/services/database_service.dart)）

- **`collections`**：主表，`id` 主键，含 title/type/source_platform/source_url/author/published_at/collected_at/category_json/images_json/note/status/review_due_at/tags
- **`categories`**：分类树，`id` 主键，`parent_id` 自引用，`sort_order` 排序
- **`tags`**：标签注册表（手动创建的标签，`name` 主键）
- **`collection_notes`**：笔记，`collection_id` 外键 + 索引
- **`collections_fts`**：FTS5 虚拟表，索引 `title`/`note`/`content_text`，独立表（非外部内容表，避免同步报错）

### 7.3 数据库迁移（`_onUpgrade`，当前版本 5）

| 版本 | 变更 |
|---|---|
| v1→v2 | 新增 `tags` 列 |
| v2→v3 | 评论区模式：新建 `collection_notes` 表，已有 note 迁移为首条笔记 |
| v3→v4 | FTS 改独立表，重建全文索引（正文从文件系统读回） |
| v4→v5 | 新增标签注册表 `tags` 表 |

`DatabaseService` 为单例，用 `Completer` 保证并发访问只初始化一次。启动时通过 `sqfliteFfiInit()` + `databaseFactory = databaseFactoryFfi` 使用捆绑的 SQLite（含 FTS5），避免 Android 系统 SQLite 缺少 fts5 模块。

---

## 8. 核心业务流程

### 8.1 转录保存流程

```
用户输入 (链接/文本)
   │
   ▼
SavePage._doSave
   │  TypeDetector.detectType → article/comment
   │  若 URL 且非仅存原文：
   │    1. WebContentFetcher.fetch (Dio + html) → 正文 + 图片
   │    2. 失败降级 → HeadlessWebExtractor (无头 WebView，JS 渲染)
   │       - 注入 Cookie、触发轮播懒加载、提取正文/标题/作者/时间
   ▼
SaveController.save
   │  1. 收集已有标签 + 本地顶层文件夹
   │  2. _buildPrompt 拼装提示词（追加标签/文件夹列表）
   │  3. TranscriptionService.transcribe:
   │     a. 图片下载 (ImageDownloader，带 UA+Referer)
   │     b. AI 仅提取标签 (LlmClient.transcribe，JSON {"tags":[...]})
   │     c. 占位符 [图N] 替换为本地路径
   │  4. 标签归一化 (_normalizeTags) + 文件夹归一化 (_normalizeCategory)
   │  5. onConfirmTags 回调 → TagConfirmDialog 让用户勾选
   │     (用户取消 → 中止整个保存)
   │  6. 平台识别 (_detectPlatform，按 URL 域名)
   │  7. 构造 Collection → repository.create (写 meta+content+DB+FTS)
   │  8. ref.invalidate 刷新列表/统计/标签/分类文章缓存
   ▼
成功 (lastCollectionId) / 失败 (降级保存原文)
```

**关键设计**：
- **标题/作者/时间/平台取自页面提取，不依赖 AI**；AI 只生成标签
- **AI 失败不阻断保存**：正文照常入库，错误记入 `aiError` 写入日志
- **降级保存**：转录失败时仍保存原文（标题加「（转录失败）」前缀），保留 `lastCollectionId` 供事后补全
- **保存日志**：全程记录时间戳日志，末尾附 AI 思考链 + 原始输出，便于排查

### 8.2 全文搜索流程

`CollectionRepositoryImpl.search(keyword)`：

1. **FTS5 前缀匹配**：每个词加 `*`（搜 "wi" 命中 "win"），多词 AND，`ORDER BY rank`
2. **LIKE 兜底**：`unicode61` 分词器把连续中文当一整个 token，中文词搜索 FTS 命中不了，靠 `title/author/tags/note LIKE` 补
3. 合并去重（`seen` Set），取前 `limit` 条

### 8.3 AI 标签与文件夹归一化

**标签归一化**（`_normalizeTags`，按优先级）：

1. 忽略大小写与首尾空白后**完全一致** → 替换为已有标签
2. **互相包含**（如 AI「地平线4」⊂ 已有「极限竞速地平线4」）且较短方 ≥2 字符、较短方 ≥ 较长方 50% → 替换（比例护栏防「游戏」吞并长标签）
3. 无匹配 → 保留 AI 原词（作为新标签候选，用户在确认框可剔除）

**文件夹归一化**（`_normalizeCategory`）：

1. 忽略大小写完全一致 → 命中
2. 互相包含且较短方 ≥2 → 命中
3. **未命中 → 返回空串（回退保存页选择目录），绝不新建文件夹**
4. AI 命中的顶层文件夹**静默应用**，不弹窗确认；未命中回退保存页选定目录

### 8.4 回顾提醒流程

```
ReadPage._showLearningDialog
   │  选 1/3/7/14/30 天后回顾 (reviewDueAt)
   │  status = 'learning'
   ▼
repository.update
   ▼
ReminderScheduler.schedule
   │  遍历 AppSettings.reminderChannels:
   │    - local: zonedSchedule (exactAllowWhileIdle, id=col.id.hashCode)
   │    - smtp:  不预排 (sendNow 即时发)
   │    - calendar: addEvent2Cal (起止 1 小时)
   ▼
到时触发通知 → 点击 → notificationPayloadProvider
   │  app.dart 监听 → _router.go('/read/$payload')
```

---

## 9. 路由与页面导航

`AppRouter.createRouter` 定义的路由表：

| 路径 | 页面 | 说明 |
|---|---|---|
| `/onboarding` | OnboardingPage | 引导页（未完成时强制） |
| `/collections` | CollectionsPage | 收藏主页（Shell 分支 1） |
| `/learning` | LearningPage | 想学队列（Shell 分支 2） |
| `/categories` | CategoriesPage | 分类浏览（Shell 分支 3） |
| `/settings` | SettingsPage | 设置主页（Shell 分支 4） |
| `/settings/llm` | LlmSettingsPage | LLM 配置 |
| `/settings/list-style` | ListStyleSettingsPage | 卡片样式 |
| `/settings/cookies` | CookiesPage | Cookie 管理 |
| `/settings/smtp` | SmtpSettingsPage | SMTP 配置 |
| `/categories/articles` | CategoryArticlesPage | 分类文章（`CategoryArticlesArgs`） |
| `/save` | SavePage | 保存页（`extra` 可为 String/Map） |
| `/read/:id` | ReadPage | 阅读页（`extra: bool fromLearning`） |
| `/read/:id/chat` | ArticleChatPage | 文章对话 |

`StatefulShellRoute.indexedStack` 实现 4 分支底部导航，各分支状态独立保留。`redirect` 守卫引导页完成状态。

---

## 10. 主题与 Material You

[app_theme.dart](file:///h:/xiangmu/lib/core/theme/app_theme.dart) 参考 legado-with-MD3 设计取向：

- **Monet 动态取色**：`DynamicColorBuilder` 在 [app.dart](file:///h:/xiangmu/lib/app.dart) 中取壁纸配色，Android 12+ 跟随壁纸；可在设置关闭，回退种子色 `#2196F3`
- **MD3 组件样式**：
  - AppBar 左对齐标题、滚动时表面色调提升
  - FAB 用 `primaryContainer` 容器色
  - 填充式输入框（`surfaceContainerHighest` 底色）
  - 胶囊指示器 `NavigationBar`
  - 28dp 圆角对话框
- **预测性返回**：`PredictiveBackPageTransitionsBuilder`（AndroidManifest `enableOnBackInvokedCallback="true"`）

阅读页 Markdown 样式：`MarkdownStyleSheet.fromTheme(...)` 作为基础（保留粗体/链接默认样式），再叠加自定义 blockquote 样式（浅灰底 + 细灰线 + 小字号）。

---

## 11. Provider 依赖关系图

```
appSettingsProvider ──┬─► llmConfigFromSettingsProvider ──► (TranscriptionService 间接)
                      └─► (dynamicColor / clipboardDetection 直接消费)

cookieListProvider ──► webContentFetcherProvider ──┐
dioProvider ──┬─► webContentFetcherProvider         ├─► transcriptionServiceProvider
              ├─► llmClientProvider ────────────────┤
              └─► imageDownloaderProvider ──────────┘

collectionRepositoryProvider ──┬─► categoryRepositoryProvider
                               ├─► categoryTreeProvider / categoriesListProvider
                               ├─► collectionDetailProvider (family)
                               ├─► collectionsListProvider (经 collectionsFilterProvider)
                               ├─► groupStatsProvider / allTagsProvider
                               ├─► categoryArticlesProvider (family)
                               ├─► collectionNotesProvider (family)
                               └─► learningQueueProvider

storagePathProvider ──┬─► storageStatsProvider
                      ├─► backupServiceProvider
                      └─► maintenanceServiceProvider

reviewNotificationServiceProvider ──► notificationPayloadProvider ──► app.dart 监听
```

---

## 12. Android 平台配置

[android/app/build.gradle.kts](file:///h:/xiangmu/android/app/build.gradle.kts)：

- `applicationId` / `namespace` = `com.example.fav_app`
- `compileSdk` = **36**（为 file_picker 的 `flutter_plugin_android_lifecycle` 依赖）
- `minSdk` / `targetSdk` 跟随 Flutter SDK 默认
- Java/Kotlin `VERSION_17`，启用 `coreLibraryDesugaring`（`desugar_jdk_libs:2.1.4`）
- release 签名暂用 debug keys（TODO 配置正式签名）

[AndroidManifest.xml](file:///h:/xiangmu/android/app/src/main/AndroidManifest.xml)：

- `android:label="藏星"`，`enableOnBackInvokedCallback="true"`
- `MainActivity`：`launchMode=singleTop`、`taskAffinity=""`、`windowSoftInputMode=adjustResize`，`configChanges` 覆盖大量配置变更（自处理，避免重建）
- `queries`：`PROCESS_TEXT`（text/plain）供 `ProcessTextPlugin` 查询
- 权限：无显式 `<uses-permission>`，通知/日历权限由对应插件运行时动态请求
- 分享接收入口：由 `share_handler` 插件在构建时合并 `<intent-filter android:action.SEND>`，代码层 `ShareInputService` + `pendingShareExtraProvider` + `CollectionsShell` 已完整处理

---

## 13. 项目运行方式

### 13.1 环境要求

- Flutter ≥ 3.0.0（Dart SDK ≥ 3.0.0）
- Android SDK compileSdk 36
- Java 17

### 13.2 构建运行命令

```bash
flutter pub get                 # 安装依赖（含本地 file_picker 覆盖）
flutter run                     # 调试运行（连接设备/模拟器）
flutter build apk --release     # 发布构建 APK
```

> Android 端已通过 `sqlite3_flutter_libs` 捆绑启用 FTS5 的 SQLite，无需额外配置。

### 13.3 首次使用

1. 启动后进入引导页（4 页介绍 + 文件夹模板选择）
2. 完成引导后导入推荐文件夹模板，跳转收藏主页
3. 在「设置 → 转录与 AI → LLM API 设置」配置 BaseURL / APIKey / 模型（可选，不配置则只能「仅存原文」）
4. 可选：在「设置 → 转录与 AI」配置 Cookie（小黑盒等需登录站点）、剪贴板检测开关

### 13.4 数据迁移

- **目录拷贝迁移**：直接拷贝 `fav_data/`（meta/content/images）+ `databases/fav_app.db` 到新设备同路径即可
- **应用内备份**：设置 → 数据与备份 → 导出备份（生成 `fav_backup_{时间戳}` 目录）/ 导入备份

---

## 14. 工程约定与设计要点

### 14.1 工程约定

- **包导入**：统一使用绝对路径 `package:fav_app/...`
- **Riverpod family 参数**：自定义对象用作 family 参数须实现 `==` 与 `hashCode`（如 `CategoryArticlesFilter`）
- **错误处理**：`TranscriptionException` 携带具体 `TranscriptionFailureReason`，转录失败不阻断原文保存
- **共享组件**：`MetaEditDialog` 从保存页、收藏列表（长按）、详情页三处复用
- **标签选择**：编辑弹窗展示已有标签（注册表 + 全部收藏）及使用次数，支持实时过滤与点选添加

### 14.2 关键设计要点

| 约束 | 实现位置 |
|---|---|
| 转录失败必须保存原始输入 | `SaveController.save` 的 `on TranscriptionException` 降级分支 |
| AI 只生成标签，标题/作者/时间/平台取自页面 | `SaveController` 用 `preFetched*` 字段，`LlmClient` 默认提示词要求仅输出 `{"tags":[...]}` |
| 旧提示词（含 `content_md`）启动自动迁移 | `AppSettingsNotifier.build` 的 `_legacyPromptMigration` |
| Dio 禁用自动状态码校验 | `WebContentFetcher` 的 `validateStatus: (_) => true` |
| WebView 注入域名 Cookie | `HeadlessWebExtractor._initWithCookie` + `WebViewCookieManager` |
| 图片提取失败 2 秒后重试 / 轮播滑动触发懒加载 | `HeadlessWebExtractor._triggerLazyImages` |
| 删除文章刷新标签计数缓存 | `SaveController` / `MetaEditDialog` 中 `ref.invalidate(allTagsProvider)` |
| Markdown 用 `fromTheme` 保留默认样式 | `ReadPage._ArticleBody` |
| 分类选择对话框：已有文件夹优先，「未分类」兜底置底 | `SavePage._openCategoryPicker` / `ReadPage._openCategoryDialog` |
| AI 文件夹建议静默应用，未命中回退保存页选择 | `SaveController._normalizeCategory` |
| 保存日志含本地文件夹列表与保存目录 | `SaveController._log('本地文件夹(N): ...')` |
| 剪贴板检测开关 + 不重复弹窗 | `CollectionsShell._checkClipboard` + 静态 `_lastPromptedClipboard` |
| 排版设置实时持久化 | `readingStyleProvider` |
| 标签确认弹窗 `barrierDismissible:false` | `showTagConfirmDialog` |

### 14.3 已知技术取舍

- **FTS5 中文分词**：`unicode61` 把连续中文当一整个 token，中文词搜索靠 LIKE 兜底（`title/author/tags/note LIKE`）
- **状态筛选**：已读/未读功能已移除，`groupByStatus` 仅保留 `learning`/`done`
- **通知服务重叠**：`ReminderScheduler.LocalNotificationReminder` 与 `ReviewNotificationService` 共享 channel id `review_reminders`，职责部分重叠，调用层需明确（`LearningPage` 直接 new `ReminderScheduler`）
- **release 签名**：暂用 debug keys，待配置正式签名
