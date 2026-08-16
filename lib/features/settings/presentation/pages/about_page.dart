import 'package:flutter/material.dart';

const _appVersion = '1.0.0+1';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('关于应用')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Material(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(28),
              elevation: 0,
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () {},
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 28),
                  child: Column(
                    children: [
                      Icon(Icons.auto_stories_rounded,
                          size: 72, color: scheme.primary),
                      const SizedBox(height: 14),
                      Text('藏星',
                          style: theme.textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      Text('cn.cangxing.mobile · v$_appVersion',
                          style: TextStyle(
                              color: scheme.onSurfaceVariant, fontSize: 13)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          _SettingsSection(
            title: '应用信息',
            children: const [
              _AboutTile(
                icon: Icons.description_outlined,
                title: '应用描述',
                subtitle: '本地优先的内容收藏与间隔复习工具',
              ),
              _AboutTile(
                icon: Icons.android_outlined,
                title: '包名',
                subtitle: 'cn.cangxing.mobile',
              ),
              _AboutTile(
                icon: Icons.verified_outlined,
                title: '版本号',
                subtitle: 'v$_appVersion',
              ),
              _AboutTile(
                icon: Icons.bolt_outlined,
                title: 'Flutter 版本',
                subtitle: '3.x (Dart 3)',
              ),
            ],
          ),
          _SettingsSection(
            title: '开源与支持',
            children: [
              _AboutTile(
                icon: Icons.collections_bookmark_outlined,
                title: '致谢项目',
                subtitle:
                    'gedoor/legado · HapeLee/legado-with-MD3 · Riverpod · sqflite 等',
                onTap: () => _showThanksDialog(context),
              ),
              _AboutTile(
                icon: Icons.gavel_outlined,
                title: '开源协议',
                subtitle: 'MIT License',
                onTap: () {
                  showLicensePage(
                    context: context,
                    applicationName: '藏星',
                    applicationVersion: 'v$_appVersion',
                  );
                },
              ),
              _AboutTile(
                icon: Icons.bug_report_outlined,
                title: '反馈问题',
                subtitle: '欢迎提交 Issue 与 PR',
                onTap: () {},
              ),
              _AboutTile.switchTile(
                icon: Icons.update_outlined,
                title: '检查更新',
                value: false,
                onChanged: (v) {},
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  void _showThanksDialog(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('致谢项目'),
        children: [
          _ThanksItem(
            icon: Icons.menu_book_outlined,
            tint: scheme.primaryContainer,
            tintFg: scheme.onPrimaryContainer,
            name: 'gedoor/legado',
            desc: 'UI 灵感与阅读 App 经验',
          ),
          _ThanksItem(
            icon: Icons.palette_outlined,
            tint: scheme.secondaryContainer,
            tintFg: scheme.onSecondaryContainer,
            name: 'HapeLee/legado-with-MD3',
            desc: 'MD3 设计参考',
          ),
          _ThanksItem(
            icon: Icons.account_tree_outlined,
            tint: scheme.tertiaryContainer,
            tintFg: scheme.onTertiaryContainer,
            name: 'flutter_riverpod',
            desc: '状态管理',
          ),
          _ThanksItem(
            icon: Icons.storage_outlined,
            tint: scheme.errorContainer,
            tintFg: scheme.onErrorContainer,
            name: 'sqflite / sqlite3',
            desc: 'SQLite + FTS5 搜索',
          ),
          _ThanksItem(
            icon: Icons.notifications_outlined,
            tint: scheme.primaryContainer,
            tintFg: scheme.onPrimaryContainer,
            name: 'flutter_local_notifications',
            desc: '本地通知',
          ),
          _ThanksItem(
            icon: Icons.language_outlined,
            tint: scheme.secondaryContainer,
            tintFg: scheme.onSecondaryContainer,
            name: 'dio',
            desc: '网络请求',
          ),
          _ThanksItem(
            icon: Icons.enhanced_encryption_outlined,
            tint: scheme.tertiaryContainer,
            tintFg: scheme.onTertiaryContainer,
            name: 'flutter_secure_storage',
            desc: '敏感字段加密',
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('关闭'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThanksItem extends StatelessWidget {
  final IconData icon;
  final Color tint;
  final Color tintFg;
  final String name;
  final String desc;

  const _ThanksItem({
    required this.icon,
    required this.tint,
    required this.tintFg,
    required this.name,
    required this.desc,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: ListTile(
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: tint,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20, color: tintFg),
        ),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(desc),
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SettingsSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Material(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: Column(children: children),
            ),
          ),
        ],
      ),
    );
  }
}

class _AboutTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool? switchValue;
  final ValueChanged<bool>? onChanged;

  const _AboutTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
  })  : switchValue = null,
        onChanged = null;

  const _AboutTile.switchTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required ValueChanged<bool>? this.onChanged,
    required bool value,
  })  : switchValue = value,
        onTap = null;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final leading = Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 20, color: scheme.onSecondaryContainer),
    );

    final trailing = switchValue != null
        ? Switch(value: switchValue!, onChanged: onChanged)
        : (onTap != null ? const Icon(Icons.chevron_right) : null);

    return ListTile(
      leading: leading,
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: trailing,
      onTap: switchValue != null ? null : onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }
}
