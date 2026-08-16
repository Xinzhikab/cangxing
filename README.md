# 藏星（cangxing）

本地优先的内容收藏 App：把链接、文章、动态、评论一键收藏到本地，AI 自动生成标签并归类到已有文件夹，随时全文阅读、回顾，还能和文章直接对话。

## 特性

- **多形式收藏**：链接 / 文章 / 评论，支持剪贴板自动识别，一键转录
- **智能转录**：WebView 抓取正文与图片（含轮播图懒加载触发），标题、作者、时间、平台取自页面提取结果；AI 只负责生成标签
- **标签与文件夹归一**：AI 推荐自动匹配本地已有标签与文件夹，不新建文件夹，保存前统一确认
- **与文章对话**：以全文为上下文的多轮问答，快速回顾和理解收藏内容
- **本地全文搜索**：SQLite + FTS5，毫秒级检索所有收藏
- **本地优先**：数据全部存本地（SQLite + 文件系统），目录拷贝即可完成迁移；LLM API 可选可配置
- **Material You**：MD3 动态取色，界面配色跟随壁纸

## 技术栈

Flutter · Riverpod · go_router · Dio · WebView · sqlite3_flutter_libs（FTS5）

## 构建运行

```bash
flutter pub get
flutter run                 # 调试运行
flutter build apk --release # 发布构建
```

> Android 端已通过 sqlite3_flutter_libs 捆绑启用 FTS5 的 SQLite，无需额外配置。

## 目录结构

```
lib/
├── core/             # 路由、主题、常量等
└── features/
    ├── collections/  # 收藏、分类、标签
    ├── save/         # 转录与保存（LLM 客户端、抓取服务）
    ├── read/         # 阅读页、文章 AI 对话
    ├── learning/     # 回顾队列与提醒通知
    ├── onboarding/   # 首次启动引导
    └── settings/     # 设置（转录 & AI、外观、卡片样式、Cookie、备份等）
```
