import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fav_app/features/settings/data/providers/app_settings_provider.dart';

/// SMTP 邮件提醒配置子页：从设置页「回顾提醒」组点入。
class SmtpSettingsPage extends ConsumerStatefulWidget {
  const SmtpSettingsPage({super.key});

  @override
  ConsumerState<SmtpSettingsPage> createState() => _SmtpSettingsPageState();
}

class _SmtpSettingsPageState extends ConsumerState<SmtpSettingsPage> {
  late final TextEditingController _hostCtrl;
  late final TextEditingController _portCtrl;
  late final TextEditingController _userCtrl;
  late final TextEditingController _passCtrl;
  late final TextEditingController _rcptCtrl;
  late bool _ssl;

  @override
  void initState() {
    super.initState();
    final s = ref.read(appSettingsProvider).valueOrNull;
    _hostCtrl = TextEditingController(text: s?.smtpHost ?? '');
    _portCtrl = TextEditingController(text: (s?.smtpPort ?? 465).toString());
    _userCtrl = TextEditingController(text: s?.smtpUsername ?? '');
    _passCtrl = TextEditingController(text: s?.smtpPassword ?? '');
    _rcptCtrl = TextEditingController(text: s?.smtpRecipient ?? '');
    _ssl = s?.smtpSsl ?? true;
  }

  @override
  void dispose() {
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _rcptCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await ref.read(appSettingsProvider.notifier).updateSettings(
          smtpHost: _hostCtrl.text.trim(),
          smtpPort: int.tryParse(_portCtrl.text.trim()) ?? 465,
          smtpSsl: _ssl,
          smtpUsername: _userCtrl.text.trim(),
          smtpPassword: _passCtrl.text,
          smtpRecipient: _rcptCtrl.text.trim(),
        );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('SMTP 配置已保存')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('邮件提醒配置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _hostCtrl,
            decoration: const InputDecoration(
              labelText: 'SMTP 服务器地址',
              hintText: '如 smtp.qq.com / smtp.gmail.com',
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: TextField(
                  controller: _portCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '端口',
                    hintText: '465 / 587',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SwitchListTile(
                  title: const Text('SSL'),
                  value: _ssl,
                  onChanged: (v) => setState(() => _ssl = v),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _userCtrl,
            decoration: const InputDecoration(
              labelText: '用户名 / 邮箱账号',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passCtrl,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: '密码 / 授权码',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _rcptCtrl,
            decoration: const InputDecoration(
              labelText: '收件人邮箱（留空同用户名）',
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text('保存配置'),
          ),
        ],
      ),
    );
  }
}
