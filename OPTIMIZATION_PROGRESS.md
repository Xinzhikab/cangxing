# 藏星（cangxing）优化进度报告

> 生成日期：2026-08-16
> 状态：✅ **P0 全部完成 · P1（第二批）全部完成** · 剩余 P2/P3 待后续

---

## 执行总览

| 批次 | 数量 | 状态 |
|------|------|------|
| **第一批（P0 最高优先级，必修）** | **8 项 + 3 项附加（包名/MD3设置页/关于页）** | ✅ 全部完成 |
| **第二批（P1 高收益）** | **8 项（清单建议 10 项，合并 2 项后 8 项）** | ✅ 全部完成 |
| **第三批（P2 中期优化）** | 9 项 | ⏳ 未开始 |
| **第四批（P2/P3 其余）** | 22 项 | ⏳ 未开始 |

**累计完成：19 项优化（含 3 项用户附加需求）**，`flutter analyze` 验证 **0 error** 通过。

---

## ✅ 第一批（P0 — 8 项）完成清单

### A1. 两套通知服务合并 ✅

**问题**：`LocalNotificationReminder` 与 `ReviewNotificationService` 各自初始化 `FlutterLocalNotificationsPlugin`，共享 channel id `review_reminders`；`LearningPage` 直接 `new` 实例，存在重复初始化 / 双份调度风险。

**修复**：
- 新增 `UnifiedLocalNotificationChannel` 单一 channel 抽象，合并重复的 init/schedule/cancel 逻辑。
- `ReminderScheduler` 改为 `fromSettings(settings)` 异步工厂 + `_` 私有构造。
- 新增 Riverpod Provider：`reminderSchedulerProvider = Provider<Future<ReminderScheduler>>`（所有业务通过 `ref.watch` 拿，禁止直接 new）。
- `notificationPayloadProvider = Provider<ValueListenable<String?>>`，通过 `_FutureValueListenable` 桥接通知点击 payload 的跨帧初始化。
- `LearningPage` 改用 `await ReminderScheduler.fromSettings(settings)`，移除直接 import `flutter_local_notifications.dart`。
- `review_notification_provider.dart` 改为转发兼容层：`export reminder_scheduler` 内 Provider 名，保留 `reviewNotificationServiceProvider`（旧接口占位）。

**文件**：
- [reminder_scheduler.dart](file:///h:/xiangmu/lib/features/learning/data/services/reminder_scheduler.dart)
- [review_notification_provider.dart](file:///h:/xiangmu/lib/features/learning/data/providers/review_notification_provider.dart)
- [learning_page.dart](file:///h:/xiangmu/lib/features/learning/presentation/pages/learning_page.dart)

---

### A2 / C2. Dio headers 竞态修复（Dio 拆分） ✅

**问题**：`LlmClient` 在请求前后临时改 `dio.options.headers` 并在各种 catch 分支回滚。并发调用（文章对话多轮 + 保存页转录同时发起）会互相覆盖 `Authorization`，可能把 API key 泄漏到非 LLM 站点。

**修复**：
- `transcription_providers.dart` 从共享的 `dioProvider` 拆为两个独立 Dio：
  - `scraperDioProvider`：timeout 30s，不配置任何鉴权 header，纯网页抓取用。
  - `llmDioProvider`：timeout 60s，接受 settings 变更时通过 `updateSettings` 重建实例。
- `LlmClient` 完全移除全局 header 修改（`var o = dio.options.headers; try{...restore}finally{restore}` 那一大段），改为每次请求传 `Options(headers: {'Authorization': 'Bearer $key'})` 局部参数。

**文件**：
- [transcription_providers.dart](file:///h:/xiangmu/lib/features/save/data/providers/transcription_providers.dart)
- [llm_client.dart](file:///h:/xiangmu/lib/features/save/data/services/llm_client.dart)

---

### B1. WebView 负坐标风险修复 ✅

**问题**：`HeadlessWebExtractor` 用 `Positioned(left: -10000)` 把 412×915 真实尺寸的 WebView 挂到屏幕外。Android 小米/OPPO 等 OEM ROM 会把负坐标 View 直接暂停渲染 / 挂起 JS，导致轮询 `_hasContent()` 永远 false。

**修复**：
- 改为 `Stack` 内：
  - 外层 `Visibility(visible: true, maintainSize: true, maintainState: true, maintainInteractivity: true)`
  - 内层 `Opacity(always 0.001, 不设 0 避免 WebView 被识别为不可见)`
  - 尺寸 `1×1 px`（不是 412×915），配 `OverflowBox(minWidth/maxWidth/minHeight/maxHeight` 撑内容）
  - `SizedBox.shrink()` 覆盖顶层吞掉命中测试事件，避免用户点击漏到透明 WebView。

**文件**：
- [web_extract_page.dart](file:///h:/xiangmu/lib/features/save/presentation/pages/web_extract_page.dart)

---

### C1. 空 catch 吞错修复 ✅

**问题**：全局 `catch (_) {}` 空吞错 20+ 处。最危险的是 `SaveController.save` 降级保存内部的 `catch (_) {}`——**降级保存本身失败时用户以为成功了，实际上没写任何文件**。

**修复**：
- 所有空 catch 改为 `catch (e, st) { debugPrint('[ClassName] $e\n$st'); }`
- 降级保存的 catch 改为：打日志后 **继续设置 `SaveStatus.failed` / 错误信息**，不得静默成功。
- 其余非关键 catch 保留 debugPrint 日志，必要时 `rethrow`（关键保存路径）。

**文件**：
- [save_controller.dart](file:///h:/xiangmu/lib/features/save/data/providers/save_controller.dart)
- 其他相关页面/服务。

---

### C3. 敏感字段加密（flutter_secure_storage） ✅

**问题**：`AppSettings.llmApiKey`、`smtpPassword`、`cookiejar_entries` 全部明文存 SharedPreferences，root 设备 / adb backup 可直接读密钥。

**修复**：
- **app_settings_provider.dart**：
  - 新增 key：`sec_llm_api_key` / `sec_smtp_password`
  - build() 时从 `FlutterSecureStorage` 读；并做**一次迁移**：如果 `prefs` 里旧明文值非空，写入 secure + prefs.remove 清掉明文。
  - `updateSettings()` 仅当 `settings.xxx != current.xxx` 时才 `secure.write(...)`，乐观更新逻辑保持不变。
- **cookie_provider.dart**：
  - `CookieNotifier` 从 `Notifier<List>` → **`AsyncNotifier<List>`**（build 本身异步，能 await secure 读）。
  - build() 内迁移：旧 `prefs.getString('cookiejar_entries')` 非空 → 写入 `secure(key: sec_cookiejar_entries)` + prefs.remove。
  - `_persist()` / `_load()` 全部改用 `secure.write/read`，`jsonEncode/decode` 不变。
  - `upsert()` / `remove()` 改为 `Future<void>`，使用 `AsyncValue.data(value)` 乐观更新。
  - `matchForUrl()` **保持同步**，内部用 `state.valueOrNull`。
- **cookies_page.dart / save_page.dart** 适配：
  - cookies_page：`ref.watch(cookieListProvider)` 改为 `.when(loading/error/data)` 分支。
  - save_page：`ref.read(cookieListProvider)` → `.valueOrNull ?? const []`。

**文件**：
- [app_settings_provider.dart](file:///h:/xiangmu/lib/features/settings/data/providers/app_settings_provider.dart)
- [cookie_provider.dart](file:///h:/xiangmu/lib/features/settings/data/providers/cookie_provider.dart)
- [cookies_page.dart](file:///h:/xiangmu/lib/features/settings/presentation/pages/cookies_page.dart)

---

### C5. LIKE 误匹配分类修复 ✅

**问题**：`CategoryRepositoryImpl.delete` 用 `category_json LIKE '%"攻略"%'` —— 如果分类 A 叫「攻略」，会命中分类 B「游戏攻略」，把属于游戏攻略的文章误删 / 改到未分类。

**修复**：
- 不再用 LIKE 子串匹配，改为：
  1. `db.query('collections', columns: ['id', 'category_json'])` 先把所有候选行的 JSON 抓出来。
  2. 在 Dart 层 `jsonDecode(row['category_json'])` 解码数组。
  3. 精确比较 `element['name'] == catName` 且 `(element['path'] ?? []).join('/') == catPath`（path 相同才是同一个分类，否则同名不同父目录不删）。
  4. 批量 UPDATE 时只 UPDATE 命中的 id 列表。

**文件**：
- [category_repository_impl.dart](file:///h:/xiangmu/lib/features/collections/data/repositories/category_repository_impl.dart)

---

### F1. 启动自检（meta/DB/FTS 一致性修复） ✅

**问题**：`CollectionRepositoryImpl.create` 的写入顺序是 `saveMeta → saveContent → db.insert → fts.insert`。如果在 db.insert 之后 fts 之前被杀进程，下次会出现"有收藏、搜不到"，没有修复机制。

**修复**：
- `DatabaseService` 新增 `selfCheckAndRepair()` 方法，每次打开数据库后（**不是版本升级回调**）都自动执行。步骤：
  1. **FTS 补写**：查 `collections` 所有 (rowid, id, title, note)，对每个 rowid 若 `collections_fts` 没有对应行，从 `content/$id.md` 读 content_text 补写 INSERT → 计数 `ftsRowsInserted`。
  2. **孤儿 DB 行清理**：遍历所有 id，若 `meta/$id.json` 不存在（文件残缺），DELETE `collections` + `collections_fts` → 计数 `orphanDbRowsDeleted`。
  3. **错误不抛**：任何异常 `errors.add('$e')` 收集，不阻塞用户启动。
- `debugPrint` 打印结果 + 错误明细（如果有的话）。

**文件**：
- [database_service.dart](file:///h:/xiangmu/lib/features/collections/data/services/database_service.dart)

---

### G1. release 签名配置 ✅

**问题**：release 用 debug keystore（每台机器不同，卸载重装签名不一致、Play 审核必拒）。

**修复**：
- 新模板：`android/keystore.properties.template`（4 字段模板 + 安全说明），用户复制为 `keystore.properties` 填真实值。
- `android/app/build.gradle.kts` `signingConfigs`：
  - 先读 `rootProject.file("keystore.properties")`（存在才加载，不存在 fallback 到 debug，保证 gradle sync 不会失败）。
  - `create("release")`：存在 storeFile → 用 release；否则 copy debug signingConfig。
  - `buildTypes.release.signingConfig = signingConfigs.getByName("release")`。
- `.gitignore` 新增 `android/keystore.properties`，避免误提交。

**文件**：
- [keystore.properties.template](file:///h:/xiangmu/android/keystore.properties.template)
- [build.gradle.kts](file:///h:/xiangmu/android/app/build.gradle.kts)

---

## 🎁 用户附加需求（非清单内，本轮一并完成）

### 🎁 1. 包名品牌化：cn.cangxing.mobile ✅

| 维度 | 变更前 | 变更后 |
|------|--------|--------|
| Android namespace/applicationId | com.example.fav_app | **cn.cangxing.mobile** |
| Android package（main/debug/profile 3 个 Manifest） | 未声明 | **cn.cangxing.mobile** |
| iOS Bundle ID（Runner 3 配置 + RunnerTests 3 配置） | com.example.fav_app | **cn.cangxing.mobile** + .RunnerTests |
| MainActivity.kt | kotlin/com/example/fav_app/ | **kotlin/cn/cangxing/mobile/** |
| pubspec description | A Flutter favorites app. | **藏星 - 本地优先的内容收藏与间隔复习工具** |

---

### 🎁 2. 设置页 MD3 风格升级（参考 legado-with-MD3） ✅

**[settings_page.dart](file:///h:/xiangmu/lib/features/settings/presentation/pages/settings_page.dart)**：
- 顶部新增精简 **Hero 小卡片**：主色容器半透明背景 + 20 圆角 + auto_stories_rounded 图标 +「藏星 / 本地优先 · 收藏与间隔复习」，可点击跳关于页。
- 「关于」小节改为入口：「关于藏星 → 版本信息、开源协议、致谢项目」。

---

### 🎁 3. 独立关于页（/settings/about） ✅

**新建 [about_page.dart](file:///h:/xiangmu/lib/features/settings/presentation/pages/about_page.dart)**：
- **Hero 大卡片**：`surfaceContainerHighest` + 28 圆角，72px 主色「📚」图标 + 标题「藏星」+ 副标题「cn.cangxing.mobile · v1.0.0+1」。
- **应用信息分组**：应用描述、包名、版本号、Flutter 版本（4 项）。
- **开源与支持分组**：
  - 致谢项目 → SimpleDialog 列出 7 项（gedoor/legado、HapeLee/legado-with-MD3、Riverpod、sqflite/sqlite3、flutter_local_notifications、dio、flutter_secure_storage），每项配色调图标。
  - 开源协议 → 调用 Flutter 自带 `showLicensePage(context, applicationName: '藏星')`，展示所有依赖 LICENSE。
  - 反馈问题（占位）/ 检查更新（Switch 占位，留后续接入自动更新）。

**路由**：[app_router.dart](file:///h:/xiangmu/lib/core/router/app_router.dart) 新增子路由 `/settings/about`。

---

## ✅ 第二批（P1 高收益 — 8 项）完成清单

### A3. 重复 Provider 合并 ✅

**问题**：`categoryListProvider` 与 `categoriesListProvider` 同一文件内定义完全相同的 `FutureProvider`，CategoriesPage 用一个，其他页面用另一个；两边 invalidate 独立触发，刷新不同步。

**修复**：
- 删除 `categoryListProvider` 定义；保留唯一源 `categoriesListProvider`。
- 末尾加 `@Deprecated('Use categoriesListProvider instead') final categoryListProvider = categoriesListProvider;` 兼容别名（旧 import 不断红，仅 deprecation warning）。
- CategoriesPage 全部改为 `categoriesListProvider`（watch + invalidate 都换），消除 warning。

**文件**：
- [category_tree_provider.dart](file:///h:/xiangmu/lib/features/collections/data/providers/category_tree_provider.dart)
- [categories_page.dart](file:///h:/xiangmu/lib/features/collections/presentation/pages/categories_page.dart)

---

### A5. 手动 invalidate 收敛（基础设施） ✅

**问题**：40+ 处 `ref.invalidate(...)` 散落在各页面，写代码的人容易忘记写对应 invalidate 导致脏读。

**修复（轻量方案）**：
- 新建 **`collectionsRefreshProvider = StateProvider<int>((ref) => 0)`**（refresh token），搭配 `extension RefreshBump { bump() => state++; }`。
- Repository 注入回调：
  - `CollectionRepositoryImpl({ ..., required void Function()? onChanged })` → 8 个写入方法末尾 `onChanged?.call()`：create/update/delete/addNote/deleteNote/addTag/deleteTag/renameTag。
  - `CategoryRepositoryImpl({ ..., required void Function()? onChanged })` → 3 个写入方法：create/update/delete。
- Provider 注入 bump：`collection_repository_provider.dart` / `category_repository_provider.dart` 构造 impl 时传 `onChanged: () => ref.read(collectionsRefreshProvider.notifier).bump()`。
- 6 个关键 Provider 建立 token 依赖（首行 `ref.watch(collectionsRefreshProvider)`）：
  - collectionsListProvider / groupStatsProvider / allTagsProvider / categoryArticlesProvider（collections_list_controller.dart）
  - collectionNotesProvider（collection_repository_provider.dart）
  - categoriesListProvider → categoryTreeProvider 跟随重查（category_tree_provider.dart）
- **说明**：未一次性移除所有手动 invalidate，先搭好基础设施；现有手动 invalidate 与 bump 共存只会多刷一次，后续 P2 再清理。

**文件**：
- [collections_refresh_provider.dart](file:///h:/xiangmu/lib/features/collections/data/providers/collections_refresh_provider.dart)

---

### B3 + B4. 全量 IO 性能优化（list() 不读 content） ✅

**问题 B4**：`collectionsListProvider.list()` 用 `Future.wait(rows.map(_rowToCollection))`，每篇文章都读 **meta.json + content.md**。列表只展示标题/摘要，不需要读 content.md，100 篇 = 200 次文件打开。

**问题 B3**：`allTagsProvider` 为了统计 tags 调 `repo.list()`，同样把所有 content.md 读出来再丢弃，纯浪费 IO。

**修复**：
- 新增 `_rowToCollectionMetaOnly(row)` 同步函数：跳过 `_storage.loadContent(id)`，`contentMd` 直接 `''`。
- `list()` 改为使用 `_rowToCollectionMetaOnly`；`get(String id)`（详情页用的）保持原逻辑继续读全文。
- Repository 接口新增 `Future<List<Collection>> listMetaOnly([filter])`，impl 实现相同查询但只走 metaOnly。
- `allTagsProvider` 从 `repo.list()` → **`repo.listMetaOnly()`**。

**文件**：
- [collection_repository.dart](file:///h:/xiangmu/lib/features/collections/data/repositories/collection_repository.dart)
- [collection_repository_impl.dart](file:///h:/xiangmu/lib/features/collections/data/repositories/collection_repository_impl.dart)
- [collections_list_controller.dart](file:///h:/xiangmu/lib/features/collections/data/providers/collections_list_controller.dart)

---

### B9. FTS 中文 LIKE 缩小范围 ✅

**问题**：LIKE 兜底原来扫 4 列（title/author/tags/note 或部分实现扫 4 列 + content），1-2 字中文短查询会触发全表扫描正文大字符串，上千条数据时卡死。

**修复**：
- LIKE 兜底从 4 列缩到 **3 列（title / author / note）**，去掉 tags 大 JSON / content_text；
- 新增门限 **`query.length < 3` 才执行 LIKE 兜底**，3 字及以上只走 FTS（3 字中文大多能命中分词后的 token）。
- 方法上方加「搜索策略」注释块，明确 FTS → LIKE 的优先级和范围，未来调优一眼看懂。

**文件**：
- [collection_repository_impl.dart search()](file:///h:/xiangmu/lib/features/collections/data/repositories/collection_repository_impl.dart)

---

### D1. 4 处 setState((){}) 空回调修复 ✅

**问题**：4 处 `setState(() {})` 空回调只为"强制重绘"，Flutter 团队不推荐，极易被"优化"掉导致功能静默损坏。

**修复（全部改为 ListenableBuilder，等价语义且可维护）**：

| 位置 | 旧实现 | 新实现 |
|------|--------|--------|
| save_page | `_rawInputCtrl.addListener(() { setState(() {}); })` | `ListenableBuilder(listenable: _rawInputCtrl, builder: (ctx, _) => body)` |
| meta_edit_dialog | `onChanged: (_) => setState(() => _stateVer++)` + `_stateVer` 死字段 | 删除死字段；`ListenableBuilder(listenable: _tagCtrl, builder: ...query 计算...)` |
| tag_confirm_dialog | `onChanged: (_) => setState(() => _v++)` + `_v` 死字段 | 删除死字段；`ListenableBuilder(listenable: _inputCtrl, builder: ...query+others 计算...)` |
| categories_page | `_tabCtrl.addListener(() { setState(() => _tabIdx = _tabCtrl.index); })` + 未使用 `_tabIdx` 死字段 | 删除 listener + 死字段；`ListenableBuilder(listenable: _tabCtrl, builder: (_, _) => Scaffold(...))`，Tab 切换 AppBar actions 自动重建 |

**文件**：
- [save_page.dart](file:///h:/xiangmu/lib/features/save/presentation/pages/save_page.dart)
- [meta_edit_dialog.dart](file:///h:/xiangmu/lib/features/collections/presentation/widgets/meta_edit_dialog.dart)
- [tag_confirm_dialog.dart](file:///h:/xiangmu/lib/features/save/presentation/widgets/tag_confirm_dialog.dart)
- [categories_page.dart](file:///h:/xiangmu/lib/features/collections/presentation/pages/categories_page.dart)

---

### D7. Headless WebView JS 抽出为 Asset 文件 ✅

**问题**：`web_extract_page.dart` 内 500+ 行 JS 硬编码在 Dart 字符串里，无法 lint / 单测，加一个 selector 要区分 `$` 是 jQuery 还是 Dart 插值，风险高。

**修复**：
- 新建 `assets/extract/` 目录，抽 6 个独立 JS 文件（jQuery `$` / JS 模板字符串 `${}` 原样保留，仅 Dart 侧变量改为注释占位符）：
  - `trigger_lazy_scroll.js` / `trigger_lazy_swiper.js` / `trigger_lazy_dots.js` / `trigger_lazy_dom.js`（4 种懒加载触发策略）
  - `has_content.js`（正文是否渲染完成检查，含 `/*__SELECTOR_CHAIN__*/` 占位）
  - `extract.js`（主提取逻辑 ~230 行，3 个占位：`/*__BANNED_CLASSES__*/` / `/*__BANNED_URLS__*/` / `/*__SELECTOR_CHAIN__*/`）
- `pubspec.yaml` `flutter.assets` 下注册 6 个文件路径。
- Dart 端：
  - `HeadlessWebExtractor` 新增 6 个缓存字段（避免每次提取都读 asset IO），新增 `_loadJsAssets()` 单例加载。
  - `start()` 先 await 加载，失败降级 `finish(null)`。
  - 注入 JS 时用 `.replaceAll('/*__XXX__*/', var)` 把 Dart 变量注入。
  - 完全删除 4 段 ~230 行 `'''(function(){...})()'''` 硬编码。

**文件**：
- [assets/extract/](file:///h:/xiangmu/assets/extract/)（6 个 .js）
- [pubspec.yaml assets 节](file:///h:/xiangmu/pubspec.yaml)
- [web_extract_page.dart](file:///h:/xiangmu/lib/features/save/presentation/pages/web_extract_page.dart)

---

### E1. 分类对话框溢出修复 ✅

**问题**：SavePage + ReadPage 的分类选择用 `SimpleDialog(children: [...])`，分类超过 20 个时超出屏幕高度 **overflow 无法滚动**，用户看到下半部分被切掉。

**修复**：
```
SimpleDialog → AlertDialog(
  title: const Text('选择分类'),
  content: SizedBox(
    width: double.maxFinite,
    child: SingleChildScrollView(
      child: Column(mainAxisSize: MainAxisSize.min,
        children: [...],   // 原来的 RadioListTile
      ),
    ),
  ),
  actions: [TextButton(onPressed: pop, child: Text('取消'))],
)
```
两处（save_page.dart + read_page.dart）同样改造。50+ 分类也能滑动查看 + 随时取消。

**文件**：
- [save_page.dart 分类 Dialog](file:///h:/xiangmu/lib/features/save/presentation/pages/save_page.dart#L239-L286)
- [read_page.dart 分类 Dialog](file:///h:/xiangmu/lib/features/read/presentation/pages/read_page.dart#L310-L353)

---

### G2 + F2. targetSdk 显式 35 + FTS 同步注释 ✅

#### G2. targetSdk 显式 35

```kotlin
// compileSdk 36 原因：上游 third_party/file_picker 要求 flutter_plugin_android_lifecycle
// 使用 Android 16 预览 API (36)；待上游升级支持 35 后回落。
compileSdk = 36
...
defaultConfig {
    minSdk = flutter.minSdkVersion
    // Android 15 (API 35) — 当前主流稳定版本，2026/08 Google Play 审核标准
    targetSdk = 35
    ...
}
```

#### F2. FTS 字段同步文档化

- **DatabaseService 建表 SQL 上方**：14 行注释块，列出
  - collections_fts 每个字段的来源列（title/note/content_text 入，category_json 和 tags_json 不入）
  - 3 个同步时机：CRUD / rebuildSearchIndex / selfCheckAndRepair
  - 关键声明：CategoryRepositoryImpl 的 delete/rename 只改 category_json，**因为 category_json 不在 FTS 里，因此无需同步 FTS**
- **CategoryRepositoryImpl.delete 开头**：4 行注释再次声明 + 警告未来重构者"如果你加分类入 FTS，这里必须同步 flushFts"。

**文件**：
- [build.gradle.kts](file:///h:/xiangmu/android/app/build.gradle.kts)
- [database_service.dart FTS 注释块](file:///h:/xiangmu/lib/features/collections/data/services/database_service.dart#L171-L188)
- [category_repository_impl.dart delete 注释](file:///h:/xiangmu/lib/features/collections/data/repositories/category_repository_impl.dart#L83-L86)

---

## 📊 质量验证

| 验证项 | 结果 |
|--------|------|
| `flutter analyze --no-fatal-infos` | **144 issues / 0 error ✅** |
| issue 构成（info 级） | • 大头：`third_party/file_picker` 的 Windows `SIGDN_FILESYSPATH` 弃用警告<br>• 其余：项目原有 `require_trailing_commas`、`prefer_const_constructors`、`deprecated_member_use` 等 info lint<br>• **与本次改动相关 error：0 ✅** |

---

## ⏳ 第三批 & 第四批待办（参考 [OPTIMIZATION_CHECKLIST.md](file:///h:/xiangmu/OPTIMIZATION_CHECKLIST.md)）

### 第三批（中期优化 — 9 项，建议下次开工）

| # | 项 | 说明 |
|---|---|---|
| A8 | collectionsListProvider 改为 Notifier 内部 setFilter，筛选变化不再重建 StateNotifier | 滚动位置/搜索焦点不会丢 |
| A7 + F3 | 标签策略决策：废弃 tags 注册表 or 拆表 collection_tags(col_id,tag) | 目前注册表逻辑已脏 |
| B5 | Headless WebView `_finish()` 时加 `clearCache()` / `clearLocalStorage()` + 最多 1-2 实例池 | 防止 WebViewController 内存越积越多 |
| C4 | Cookie 注入：domain 精确匹配 + path 默认 `/` + 子域注入白名单校验 | 防 Cookie 盗用跨子域 |
| C6 | Dio 抓取失败（不管是网络/解析/其他）一律走 WebView 降级；异常写入 preExtractLog | 用户不会以为"AI没用" |
| E2 | SavePage dispose 时 `SaveController.cancel()` + HeadlessExtractor 标记 `_done=true` | 退页后后台不挂僵尸 |
| D2 | LlmClient 抽 `_withAuthHeaders(Options, () async {...})` finally restore | 去 10+ 行/方法 重复样板 |
| D5 | 魔法字符串消灭：status/type/platform/sortBy 全 enum + 唯一常量映射 | 改一个字段名不用 grep |
| D6 | 统一 loggerProvider INFO/WARN/ERROR + 设置页「导出日志到文件」 | 线上可排查用户问题 |

### 第四批（有空再做 — 其余 22 项）
详见 [OPTIMIZATION_CHECKLIST.md 第四批](file:///h:/xiangmu/OPTIMIZATION_CHECKLIST.md#L158-L160)。
