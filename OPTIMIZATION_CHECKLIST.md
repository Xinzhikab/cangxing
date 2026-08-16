# 藏星（cangxing）项目优化建议清单

> 全面代码审查后整理的 **7 大类 / 49 项**优化建议，按优先级（P0 必须 → P3 可选）排序。
>
> 生成日期：2026-08-16

---

## 目录

- [一、架构与设计（10 项）](#一架构与设计10-项)
- [二、性能与资源管理（10 项）](#二性能与资源管理10-项)
- [三、安全与稳定性（9 项）](#三安全与稳定性9-项)
- [四、代码质量与可维护性（8 项）](#四代码质量与可维护性8-项)
- [五、UI/UX（6 项）](#五uiux6-项)
- [六、数据一致性（3 项）](#六数据一致性3-项)
- [七、工程配置与平台（3 项）](#七工程配置与平台3-项)
- [建议修复顺序](#建议修复顺序)

---

## 一、架构与设计（10 项）

| # | 优先级 | 问题 | 位置 | 建议 |
|---|---|---|---|---|
| A1 | **P0** | **两套通知服务职责重叠**：`LocalNotificationReminder`（reminder_scheduler.dart#L39）与 `ReviewNotificationService`（review_notification_service.dart#L6）共享 channel id `review_reminders`，各自初始化 `FlutterLocalNotificationsPlugin`；`LearningPage` 直接 `new` 实例，而另一个走 Provider，存在重复初始化 / 双份调度风险 | 合并为单一通知 Provider，统一通过 `ReminderScheduler` 暴露，禁止业务层直接 `new FlutterLocalNotificationsPlugin()` |
| A2 | **P0** | **`LlmClient` 修改全局 Dio headers 存在竞态**：每个 API 调用前把 `Authorization` / `Content-Type` 写入 `dio.options.headers`，完成后回滚（llm_client.dart#L32-L36）。并发调用（文章对话多轮 + 保存页转录同时发起）会互相覆盖 header | 改用 `Options(headers:...)` 作为每次请求的参数；或在 `transcription_providers.dart` 里给 `llmClientProvider` 构造专用 Dio 实例，不与 `webContentFetcherProvider` 共享 |
| A3 | **P1** | **`categoryListProvider` 与 `categoriesListProvider` 逻辑完全重复**：同一文件内（category_tree_provider.dart#L18-L45）两个 `FutureProvider` 代码一模一样；`CategoriesPage` 使用 `categoryListProvider` 而其他页面用 `categoriesListProvider`，失效时各失效各的，刷新不同步 | 删除其中一个，全局统一；两侧 `invalidate` 的地方也统一走同一个 |
| A4 | **P1** | **`saveControllerProvider` 是全局单例**，状态跨保存页会话残留。目前靠 `reset()` + `SavePage.initState` 手动重置，但**任何忘记调用 reset 的入口都会显示上一次的成功 / 失败条幅**（例如未来的分享入口快速跳转等场景） | 改为 `.autoDispose`；或在 `save` 方法开头内置 reset；或让 save 页退出路由时 dispose 自动 invalidate |
| A5 | **P1** | **UI 层手动 invalidate 扩散**：40+ 处 `ref.invalidate(...)` 散落在各页面（read_page 20+ 处、collections_page 10+ 处、categories_page 等），很容易漏写导致数据不一致。例如修改分类时 `categoryArticlesProvider` 是否每次都失效取决于写代码的人是否记得 | Repository 内部写入成功后用事件总线广播刷新事件，UI 层不再手动失效；或引入「写入服务 → 变更事件 → Provider 监听自动刷新」模式 |
| A6 | **P1** | **`MaintenanceService` / `BackupService` / `StoragePathProvider` 绕过 Provider 直接 `new`**：维护服务 `StoragePathProvider()`、`DatabaseService.instance` 直接 new（非注入），无法在测试替换；`StoragePathProvider` 每次 new 出新对象（虽然是轻量，但与依赖注入风格不一致） | 统一通过 `ref.read(xxxProvider)` 注入；maintenanceServiceProvider 声明时补上这两个参数依赖 |
| A7 | **P2** | **`allTagsProvider` 每次 `repo.list()` 全量加载所有收藏**（collections_list_controller.dart#L97-L101），读所有文章只为统计标签。收藏量上千时会打开全部 meta + content 文件，性能极差 | 在 Repository 里新增 `groupByTags()` 直接用 SQL `tags_json` + `json_each`（SQLite 3.38+ 支持）聚合；或把 tags 拆成独立表 `collection_tags(col_id, tag)` |
| A8 | **P2** | **`CollectionsListController` 每次筛选变化都会重建新 StateNotifier 实例**（因为 `collectionsListProvider` 通过 `ref.watch(filter)` 生成），列表滚动位置 / 搜索焦点丢失。Riverpod 官方推荐是把筛选条件放内部 | 改为 `Notifier<AsyncValue<List<Collection>>>`，提供 `setFilter(...)` 方法，不再依赖外部 `collectionsFilterProvider` 触发重建 |
| A9 | **P2** | `CategoryRepositoryImpl.delete` 受影响收藏回退时是 `for (row in rows)` **串行** `loadMeta → saveMeta → db.update`，删除一个含 N 篇文章的分类时 IO 是 N×（1 读 meta + 1 写 meta + 1 写 DB），大分类删除用户感受仍然是"卡" | 先 `loadAllMetaByIds` 批量（如果能扩展文件存储 API）；或至少用 `package:pool` 做并行度 4-8 的并发 + `db.transaction` 批量 DB 更新 |
| A10 | **P3** | **枚举 / 常量散落在 3 处**：`app_constants.dart` 里有 `CollectionType / CollectionStatus / SourcePlatform` 3 套英文枚举 + `ItemType / ItemStatus / ItemPlatform` 3 套中文化别名，两套并存容易造成理解歧义 | 删除一套，统一命名 |

---

## 二、性能与资源管理（10 项）

| # | 优先级 | 问题 | 位置 | 建议 |
|---|---|---|---|---|
| B1 | **P0** | **`HeadlessWebExtractor` 硬编码 412×915 的真实 WebView 屏幕外挂载**（web_extract_page.dart#L112-L121），`left: -10000`；Android 上部分 OEM ROM（小米、OPPO 部分机型）会把负坐标 view 视为离屏直接暂停渲染 / JS 执行，导致提取永远卡在 polling | 改为 `Visibility(visible:false, maintainState:true, maintainSize:true)` + `Opacity(0)` + 尺寸 1×1，或把 WebView 放到真正可见的 `Stack` 顶层但置于透明 Container 下 |
| B2 | **P0** | **Dio 是单例共享的（`dioProvider` 提供）**，`LlmClient` 修改 headers 会污染 `WebContentFetcher`（同 A2 的另一视角）。如果用户在设置里调了 LLM baseUrl 为一个需要鉴权的站点，爬取该站点的请求会意外带上 `Authorization: Bearer xxx` header，触发 403 / 反爬 | 为每个用途建独立 Dio：`scraperDioProvider` / `llmDioProvider`，各自配置独立的 `BaseOptions`、interceptor、timeout |
| B3 | **P1** | **`collections_list_controller.dart#L97` 的 `allTagsProvider` 每打开标签页全量 list**（同 A7），但补充性能量化：假设 1000 篇，每篇 3KB meta + 10KB content，就是 13MB IO；而且**走 `FileStorageService.loadContent` 还会把正文读出来再丢弃** | 增加 `listMetaOnly()` 方法只读 DB 列，不碰文件系统，标签计数用 `tags_json` 列即可 |
| B4 | **P1** | **`collectionsListProvider.list()`** 用 `Future.wait(rows.map(_rowToCollection))` 并发读所有文章的 meta + content 文件（collection_repository_impl.dart#L60）。列表只需要展示标题 / 时间 / 摘要等 meta 信息，完全**不需要读 content**。100 篇文章 = 100 × 2 次文件打开 | `list()` 只走 DB 行 + meta 文件，**不读 content**；增加 `getFull(collectionId)` / `getWithContent()` 供阅读页单独调用 |
| B5 | **P1** | **Headless WebView 未显式 dispose controller**：`HeadlessWebExtractor._finish()` 只 remove OverlayEntry，没有调用 `_controller.clearCache()`（webview_flutter 未公开 dispose，但至少 clearLocalStorage / clearCache 可避免内存中 WebViewController 越积越多） | 在 `_finish` 里加 `await _controller.clearCache()`，并在 finish 后异步 `unawaited(_controller.clearLocalStorage())`（可选）；或做一个池（最多同时 1-2 个实例） |
| B6 | **P1** | **图片下载失败重试为 0，失败图直接丢失**：`ImageDownloader.downloadImages` 单张失败直接 null，没有重试。网络抖动时 30 张图可能丢 3-5 张 | 加指数退避（每图重试 2 次，间隔 500ms / 1.5s），失败写入失败列表供用户事后手动补抓 |
| B7 | **P2** | **`_triggerLazyImages` 固定 3.5s sleep**（web_extract_page.dart#L360），大多数情况不需要那么久，部分慢机器又可能不够 | 轮询「图片 src 非空数量停止增长」= 就绪，超时才 fallback 固定等待 |
| B8 | **P2** | **文章对话** 上下文硬编码 12000 字截断（article_chat_page.dart），超过部分丢弃无提示。对超长篇文章（小黑盒万字攻略很常见）AI 无法引用后半段内容 | 在 UI 上显示「已截断 12000 字」提示 + 提供「切换摘要模式」选项（先让 AI 总结全文再问答） |
| B9 | **P2** | **`database_service.dart` 的 FTS5 搜索** 中文靠 LIKE 兜底，但 LIKE 是全表扫描且无法命中索引。搜索词 2 字时速度可接受，搜索 1 字会对 `collections` 表做 4 次 LIKE，上千条数据时慢 | 集成中文分词库（Simple Chinese tokenizer + FTS5 unicode61 remove_diacritics 2 + tokenchars 自定义）；最朴素折中：LIKE 只对 `title / author` 做，长正文只走 FTS5（虽然词粒度大，但避免全表扫 content） |
| B10 | **P3** | **阅读页 Markdown** 所有图片都用 `cacheWidth` 按屏幕宽度解码，但 gallery 模式（点开看图）需要原图。这让大图列表浏览很流畅，但用户点进去会看到模糊图 | 在 `_ArticleBody` 对图片 tap 时，先弹出 `InteractiveViewer` + 从本地文件重新加载原图解码，而不是复用 widget imageProvider |

---

## 三、安全与稳定性（9 项）

| # | 优先级 | 问题 | 位置 | 建议 |
|---|---|---|---|---|
| C1 | **P0** | **空 catch 吞错 20 处**（全局 grep `catch (_) {}` 命中 20+ 处）：最危险的是 `SaveController.save` 降级保存内部的 `catch (_) {}`（save_controller.dart#L306）——**降级保存本身失败时用户以为保存成功了但实际上啥都没写**，无任何报错可见 | 改为最少 `print('[$runtimeType] $e\n$stackTrace')` 或打日志进 TranscriptionLog；降级保存 catch 后继续设置 failed 状态，不得静默 |
| C2 | **P0** | **`LlmClient` 非原子 header 切换**（同 A2）+ 有 Dio 异常或超时后回滚 headers 靠各 catch 分支手写字节——**任何新 catch 分支漏写就永久把下一次请求的 Authorization 留在全局 Dio 里**（可能泄漏 API key 到非 LLM 站点） | 改每次请求传 `Options(headers: {'Authorization': 'Bearer $key'})` 局部参数，彻底移除全局 header 修改 |
| C3 | **P0** | **SMTP 密码 / LLM API Key 明文存 SharedPreferences**：`AppSettings.smtpPassword` / `llmApiKey` 直接 `setString`，无任何加密。root 设备 / 备份可直接读得用户密钥 | 改用 `flutter_secure_storage` 存储所有敏感字段：llmApiKey、smtpPassword、Cookie 字符串；SharedPreferences 只存非敏感配置 |
| C4 | **P1** | **`web_extract_page.dart#L148` 的 Cookie 注入无 HTTPOnly / Secure 约束**：只要 host 包含就 setCookie，且没有 path / domain 规范化。用户配了一个宽泛的域名会被注入到其他子域，有 cookie 盗用风险 | Cookie 注入前加路径匹配白名单、domain 精确等于或上级域校验、`path: '/'` 默认 |
| C5 | **P1** | **`CategoryRepositoryImpl.delete` 用 LIKE 判断 category**：`category_json LIKE '%"游戏攻略"%'`（category_repository_impl.dart#L112-L114）——如果有一个分类叫「攻略」，删除分类「攻略」时也会命中「游戏攻略」→ 误把属于「游戏攻略」的文章改到「未分类」 | 改用：先把 `category_json` JSON 解码出数组 → 逐行在 Dart 层精确比较（对多行可 `CASE WHEN ...` SQL 或拆成独立表 `collection_categories(col_id, idx, name)` 有索引） |
| C6 | **P1** | **`save_page.dart#L126-L147` 的抓取 → 降级** 双 try/catch，**如果 `Dio fetch` 抛的不是网络异常而是其他（比如解析异常）则直接跳过 WebView 降级**——`catch(_)` 之后没有任何日志，用户看到 "正在后台提取" → 结束 → 没正文 → 以为 AI 没用 | 抓取失败必须进 WebView 降级，**只判断 `isLikelyUrl && !saveOnlyRaw`**，别区分 Dio 失败原因；并把错误写进 `preExtractLog` |
| C7 | **P2** | **`maintenance_service.dart#L32-L40`** 重建 FTS 索引时用**正则从 meta JSON 字符串硬匹配** title / note，而不是 `jsonDecode`。如果用户标题带转义引号 `"他说\"好\""`，正则匹配失败，索引灌空串 | 直接 `jsonDecode(lines)` 读字段，meta 文件是自己生成的 JSON，肯定合法；正则的好处是省内存，但对合法 JSON 没必要省 |
| C8 | **P2** | **`ReadPage._ArticleBody` 用 `Markdown` 展示 `[图N]` 本地文件**，但没有文件存在性校验。如果图片下载了一半或损坏，会抛异常整个页面红屏（flutter_markdown 对 imageBuilder 异常不 catch） | 给 `imageBuilder` 包 `try/catch` + `ErrorWidget` 兜底 |
| C9 | **P3** | **backupService 的拷贝** 用递归 `entity.copy`，如果拷贝中途被用户杀进程，目标目录会是一个半截目录，下次再 import 会以半截状态当成功。目前没有"原子 rename 提交" | 先写 `target.tmp/` 再 `Directory.rename` 原子切换；或每批都写 `.backup_manifest.json` 校验和 + 条目数，导入时先校验 |

---

## 四、代码质量与可维护性（8 项）

| # | 优先级 | 问题 | 位置 | 建议 |
|---|---|---|---|---|
| D1 | **P0** | **`setState(() {})` 空回调 4 处**（save_page、meta_edit_dialog、tag_confirm_dialog、categories_page），只为触发 rebuild。这类写法极不稳定，Flutter 团队不推荐，且重构时极易被"优化"掉导致功能静默损坏 | 改为显式 setState 赋真正的标志位（如 `_inputChanged`），或把 TextField 换成 `ListenableBuilder` 监听 controller |
| D2 | **P1** | **`LlmClient` 每个方法 3-4 次 `originalHeaders = ...; try ... on TimeoutException { restore; rethrow; } on DioException { restore; rethrow; } catch (e) { restore; rethrow; }`** 样板代码重复 10+ 行 × 3 方法 | 抽 `_withAuthHeaders(config, () async { ... })` 通用闭包，finally 里 restore |
| D3 | **P1** | **`CollectionsFilter.copyWith` + `CategoryArticlesFilter` + meta 类几乎一样的样板**：Collection / AppSettings / ListFieldStyle / ReadingStyle 全手写 `copyWith`，字段增删很容易漏 | 引入 `freezed` 或 `copy_with_extension_gen` 代码生成 |
| D4 | **P2** | **`save_page.dart` 的 `_doSave` 30 行 + SaveController.save() 150+ 行** 都是大方法，难以单元测试、难以调试 | 拆：`_fetchWebContent()` / `_runWebViewFallback()` / `_normalizeAndConfirm()` / `_persistCollection()` 4 个私有方法 |
| D5 | **P2** | **大量魔法字符串**：`'未分类'`、`'article'`、`'comment'`、`'learning'`、`'done'`、`'collected_at'` 散落在各处 SQL、SQL 参数名、sort 列名、状态值。改一个字段名要全局 grep | sortBy 建 enum `CollectionSortField { collectedAt, publishedAt, title }` 到 `_mapSortColumn` 做唯一映射；status / type / platform 全用常量，不要在页面里再出现字符串字面量 |
| D6 | **P2** | **日志不统一**：一半用 `_addLog('...')`（转录流程）、一半吞错（C1）。线上几乎没法排查用户问题 | 加一个全局 `loggerProvider`（`Logger` 或自建），分 INFO / WARN / ERROR 三档，ERROR 必打 stackTrace；并提供「导出日志到文件」的设置项 |
| D7 | **P3** | **Headless WebView 的 JS 代码 500+ 行字符串** 在 Dart 里硬编码，无法 lint、无法单测，改一个 selector 风险很大 | 抽成 `assets/extract/extract.js` 文件，运行时 `rootBundle.loadString` 读取 + Dart 端拼接 `_selectorChainJs` 作为参数注入；并写简单的 node + jsdom 单测 |
| D8 | **P3** | **没有单元测试**：`pubspec.yaml` 看不到测试依赖，`test/` 下只有 `widget_test.dart` 模板。AI 归一化逻辑、标签匹配、SQL 迁移等高风险代码完全裸奔 | 至少给 `_normalizeTags`、`_normalizeCategory`、`TypeDetector.detectType`、`_legacyPromptMigration` 这 4 个纯函数补测试 |

---

## 五、UI/UX（6 项）

| # | 优先级 | 问题 | 位置 | 建议 |
|---|---|---|---|---|
| E1 | **P1** | **分类选择对话框用 `SimpleDialog`**，**分类超过 20 个时超出屏幕高度不可滚动**。目前 SavePage 和 ReadPage 用的是 `SimpleDialog`（children 是 Column 语义），超过高度直接 overflow | 改为 `AlertDialog` + `SingleChildScrollView` / `Dialog` + `ListView`；或复用和 `_CategoryDrawer` 一样的 `buildTreeView` 扁平渲染 |
| E2 | **P1** | **转录中用户退出保存页，后台抓取 / AI 调用仍在跑**，`SaveController` 是全局单例 → 再进保存页看到的是上一次的残留进度；Overlay 的 WebView 也还挂着（如果 `_finish` 没跑）。用户感觉"卡住了 / 慢了" | SavePage `dispose` 时调 `SaveController.cancel()`（目前 `retryLast` 是空实现，扩展 cancel）；并 `await extractor.cancel()` / 标记 `_done=true` |
| E3 | **P1** | **AI 对话流式回复** 是"整段回复" → 一次 setState。对超长篇输出（>500 字）用户要等 15-30 秒看空白 CircularProgress，体验极差 | `LlmClient.chat` 支持 SSE（`Accept: text/event-stream` + stream=True）+ `Dio` 的 `responseType: ResponseType.stream`，逐字写入 message 气泡 |
| E4 | **P2** | **想学「再学一次」Dialog（1/3/7/14/30）** 缺少"自定义天数"输入，用户希望 21 天（艾宾浩斯最后一步）或"某个具体日期"只能多次加 | Dialog 加 `TextField` + `showDatePicker` 入口 |
| E5 | **P2** | **删除收藏无回收站**：误删立刻永久丢失 meta / content / images（包括 100+ 图片）。用户手滑成本极高 | 建 `trash` 目录 + `trash_items` 表，删除走 move 而不是 delete；设置页加"回收站"入口，可恢复 / 清空 |
| E6 | **P3** | **首页卡片 compact 模式** 没有图片。收藏大量图帖时列表看起来千篇一律（全是文字） | compact 模式在卡片左侧加 40×40 正方形首图缩略图（用 `ResizedImage` 做内存缓存） |

---

## 六、数据一致性（3 项）

| # | 优先级 | 问题 | 位置 | 建议 |
|---|---|---|---|---|
| F1 | **P0** | **文件存储与 SQLite 非原子写入**：`CollectionRepositoryImpl.create`（#L72-L82）顺序是 `saveMeta → saveContent → db.insert → db.rawInsert FTS`。如果**在 db.insert 之后、FTS 之前**崩溃（被杀进程、断电），下次打开会看到"有收藏、搜不到"，且没有修复机制 | 加"启动自检"：对 `collections` 表的每个 id，检查 meta 文件存在 → 不存在走删除；检查 FTS rowid 存在 → 不存在补写；加 `DatabaseService.selfCheckAndRepair()` 在 `init` 后跑一次，结果写入日志供用户查看 |
| F2 | **P1** | **分类删除时，只改 meta + DB，不触发 FTS**（注释里写了"分类不进 FTS"，但是——如果以后有人加了 categoryJson 进 FTS 或搜索时想按分类搜，之前的代码会立刻出错），且没有任何注释 / FTS schema 文档说明"哪些字段在 FTS 里" | 在 `DatabaseService` 的建表 SQL 上方加注释块，列出 FTS 字段来源表 + 同步时机；`CategoryRepositoryImpl.delete` 注释扩充：明确说明「分类不进 FTS 字段，因此这里无需 flush FTS」，让未来重构者一眼看到修改后果 |
| F3 | **P1** | **DB `tags` 表 + collections.tags_json 双写**。`addTag / deleteTag / renameTag` 事务内双写同步，但是**从 UI 添加标签到 collection 时（比如 MetaEditDialog 新增一个标签名）**，是直接写 collections.tags_json **没有同步写入 tags 注册表**——结果是注册表只包含"在设置页手动新建的标签"，实际文章里出现的标签大量不在注册表，`allTagsProvider` 用 putIfAbsent 兜底所以 UI 上不明显，但逻辑是脏的 | MetaEditDialog 保存后调用 `repo.addTag(name)`（幂等）为每个新增的标签入库；或干脆**废弃 tags 表**，统一靠 `allTagsProvider` 从所有收藏聚合（这是现在实际的行为） |

---

## 七、工程配置与平台（3 项）

| # | 优先级 | 问题 | 位置 | 建议 |
|---|---|---|---|---|
| G1 | **P0** | **release 签名用 debug keys**：`build.gradle.kts` 写着 `signingConfig signingConfigs.getByName("debug")` + TODO。上架 Google Play / 国内任何商店都会被拒；且 debug keystore 每台机器不同，卸载重装数据因为签名不一致不可共享 | 建 `keystore.properties` + `.gitignore`，release 块读取 `storeFile / storePassword / keyAlias / keyPassword`；README 补"签名配置"节 |
| G2 | **P1** | **`compileSdk = 36` 是预发布版**（Android 15 是 35，Android 16 预览才是 36），file_picker 的 `flutter_plugin_android_lifecycle` 强迫拉高，但：1）Lint 可能打 36-only API 警告；2）Google Play 审核会要求 targetSdk ≥ 当前主流（35）。目前 `targetSdk` 跟随 Flutter 默认，未必等于 35 | 显式写 `targetSdk = 35` 并注释 compileSdk=36 原因 + 上游链接；Flutter 升级支持 compileSdk=35 时跟进 |
| G3 | **P2** | **应用名 / 包名未品牌化**：`applicationId com.example.fav_app`、`label 藏星`、GitHub 仓库 `cangxing` 三者不一致。用户分享 APK、日志截图、Play Store 列表互相找不到对应 | 统一：包名改为 `com.yourbrand.cangxing` / `fav_app.cangxing`，`applicationId` 与 Manifest `package` 统一；README 说明命名 |

---

## 建议修复顺序

按投入产出比（ROI）推荐的修复批次：

### 第一批（本周必须修，P0 — 8 项）

- **A1** 通知服务合并
- **A2 / C2** Dio headers 竞态修复（同一问题，两处入口）
- **C1** 空 catch 补日志（特别是降级保存的那个 catch）
- **C3** 敏感字段加密（flutter_secure_storage）
- **C5** LIKE 误匹配分类（高数据损坏风险）
- **B1** WebView 负坐标风险（部分机型 100% 提取失败）
- **F1** 启动自检（防崩溃后一致性损坏）
- **G1** release 签名配置

### 第二批（高收益 — 10 项）

- **A3** 重复 Provider 合并
- **A5** 手动 invalidate 收敛
- **B2** Dio 实例拆分（scraper / llm）
- **B3 / B4** 全量 IO 优化（list() 不读 content、allTagsProvider 不 list() 全文）
- **B9** FTS 中文搜索改进
- **D1** setState(() {}) 空回调整改
- **D7** JS 抽离为 asset 文件
- **E1** 分类对话框滚动溢出修复

### 第三批（中期优化 — 9 项）

- **A8** 筛选不再重建 Notifier
- **A7 / F3** 标签表策略决策（拆表或废弃）
- **B5** WebView 缓存清理
- **C4** Cookie 注入安全约束
- **C6** Dio 失败一律走 WebView 降级
- **E2** 转录可取消
- **D2** LlmClient 样板代码抽取
- **D5** 魔法字符串消灭
- **D6** 统一 logger

### 第四批（有空再做 — P2/P3 其余 22 项）

- freezed 代码生成、logger、单元测试、SSE 流式回复、回收站、timezone 单次初始化、分类删除并行 IO、StoragePathProvider 注入一致化、枚举命名统一、图片重试、懒加载轮询优化、对话截断提示、图片 gallery 原图重加载、compact 模式卡片缩略图、正则→jsonDecode、Markdown imageBuilder 容错、备份原子 rename、targetSdk 显式 35、包名品牌化、自定义复习天数、维护服务 DI 一致化、saveController autoDispose
