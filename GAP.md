# Karakeep 改造差距分析（对照 IDEA.md v0.3）

> 基底：Karakeep main（28k★，AGPL-3.0，Next.js 16 + Expo RN 移动端 + SQLite + Meilisearch）
> 本地环境已跑通：web(localhost:3000) + workers + Meilisearch(7700) + SQLite（node 22 隔离环境）

## 一、直接可用（≈零改造）

| IDEA.md 功能 | Karakeep 现状 |
|---|---|
| A1 系统分享菜单直达 | ✅ mobile 用 expo-share-intent，text/image/pdf intent filters（apps/mobile/app.config.js:90） |
| C1 本地存储 | ✅ SQLite 单文件（DATA_DIR/db.db）+ 图片本地文件（默认不走 S3） |
| D1 文件夹式多级分类 | ✅ bookmarkLists 支持 parentId 嵌套树（manual + smart 两种） |
| D2 标题+全文搜索 | ✅ Meilisearch 索引（search-meilisearch 插件），中文有基础 CJK 支持 |
| D4 分类管理 | ✅ lists 重命名/移动；合并需补（list 间批量移动） |
| E1 排版阅读视图 | ✅ reader view（crawler 抓取 htmlContent） |
| E2 整篇笔记 | ✅ bookmarks.note 单条整篇笔记（schema.ts:241） |
| E3 跳转原帖 | ✅ link.url 直达 |
| web 中文界面 | ✅ i18next 自带 zh 简体 locale（apps/web/lib/i18n/locales/zh） |

## 二、配置/启用即可（小改造）

| 功能 | 做法 |
|---|---|
| B1 LLM 转录/排版 | 配 OPENAI_API_KEY（或 Ollama）→ 启用 inference worker（当前禁用）；summarize.ts + tagging.ts 已实现 |
| B1 网页抓取 | 配 BROWSER_WEB_URL（headless Chrome）→ 启用 crawler worker；或本机 Chrome `--remote-debugging-port` 方案 |
| C3 数据可迁移/导出 | backup worker 已启用，可打包导出 |

## 三、中等改造（加字段 + UI）

| 功能 | 差距 | 改造点 |
|---|---|---|
| A2 类型选择"文章/评论" | 只有 link/text/asset（types/bookmarks.ts:20） | schema 加 type 枚举 + 创建流程选择 + 移动端分享页 UI |
| B2 作者/原帖时间/平台元数据 | 无字段 | schema 加 author/published_at/source_platform + 抓取时提取 + 展示 |
| D3 按平台/作者筛选 | 无 | 字段 + Meilisearch filterableAttributes 配置（index.ts:191） |
| F2 收藏状态 未读/想学/已完成 | 只有 archived/favourited 布尔 | schema 加 status 枚举 + 状态机 UI + 列表角标 |
| 移动端中文 | mobile 无 i18n（无 locale 框架） | 加 i18n 或硬编码中文 |

## 四、自研（大改造）

| 功能 | 方案 |
|---|---|
| F1a 间隔回顾提醒 | schema 加 review_due_at + 新 worker（扫描到期入队）+ 本地通知（需加 expo-notifications 依赖 + 原生配置，eas.json 目前关闭推送）|
| 文章/评论差异化转录 | 不同类型走不同 LLM prompt（prompts.ts 扩展）|

## 五、关键环境事实（已踩坑记录）

1. **node 版本必须 22**：node 24 下 workers 进程退出时 better-sqlite3 native abort（`RemoveEnvironmentCleanupHook` 断言）；node 22.23.2 + `npm rebuild better-sqlite3 re2` 后稳定。启动脚本 start.ps1 已内置 PATH 切换。
2. **本机无 docker**：Meilisearch 用 D:\dev\meilisearch.exe 手动起（start.ps1 处理）；Chrome 抓取容器缺失 → crawler worker 禁用。
3. **AI worker 缺 key**：embeddings/inference 无 OPENAI_API_KEY 时禁用，避免空转。
4. **Gradle/依赖走国内镜像**：Android 构建时 maven 用腾讯 download.flutter.io 镜像方案（与本项目 Flutter 无关，是 Expo 构建时 maven 仓库问题，未实测）。
5. **expo SDK 56 / RN 0.85 / Android SDK 36 已就绪**，Android app 本地构建需 `expo prebuild` 生成 android/ 目录（CNG 模式）。

## 六、改造路线建议

Phase 1（闭环）：配 OpenAI key + Chrome → 启用全部 worker → 体验完整采集/转录/搜索/笔记闭环
Phase 2（个性化）：type 文章/评论 + 状态机（未读/想学/已完成）+ 平台/作者字段与筛选 + 移动端中文化
Phase 3（差异化）：间隔回顾提醒（review_due_at + 本地通知 + 想学队列 UI）
