import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';

import 'package:fav_app/features/save/data/providers/transcription_providers.dart';
import 'package:fav_app/features/save/data/services/llm_client.dart';
import 'package:fav_app/features/settings/data/providers/app_settings_provider.dart';

class LlmSettingsPage extends ConsumerStatefulWidget {
  const LlmSettingsPage({super.key});

  @override
  ConsumerState<LlmSettingsPage> createState() => _LlmSettingsPageState();
}

class _LlmSettingsPageState extends ConsumerState<LlmSettingsPage> {
  final _baseUrlController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _modelController = TextEditingController();
  final _reviewIntervalController = TextEditingController();
  final _promptController = TextEditingController();
  bool _loadingModels = false;
  bool _testing = false;

  static const Map<String, ({String baseUrl, String model})> _presets = {
    'OpenAI': (baseUrl: 'https://api.openai.com/v1', model: 'gpt-4o-mini'),
    'DeepSeek': (baseUrl: 'https://api.deepseek.com/v1', model: 'deepseek-chat'),
    '智谱 GLM': (baseUrl: 'https://open.bigmodel.cn/api/paas/v4', model: 'glm-4-flash'),
    '通义千问 Qwen': (baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1', model: 'qwen-plus'),
    'Kimi Moonshot': (baseUrl: 'https://api.moonshot.cn/v1', model: 'moonshot-v1-8k'),
    '豆包 Doubao': (baseUrl: 'https://ark.cn-beijing.volces.com/api/v3', model: 'doubao-pro-32k'),
    'Anthropic Claude': (baseUrl: 'https://api.anthropic.com/v1', model: 'claude-3-5-haiku-latest'),
    '本地 Ollama': (baseUrl: 'http://localhost:11434/v1', model: 'llama3'),
  };

  @override
  void initState() {
    super.initState();
    final settings = ref.read(appSettingsProvider).valueOrNull;
    if (settings != null) {
      _baseUrlController.text = settings.llmBaseUrl;
      _apiKeyController.text = settings.llmApiKey;
      _modelController.text = settings.llmModel;
      _promptController.text = settings.transcriptionPrompt;
      _reviewIntervalController.text = settings.defaultReviewIntervalDays.toString();
    }
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _modelController.dispose();
    _reviewIntervalController.dispose();
    _promptController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final reviewInterval = int.tryParse(_reviewIntervalController.text) ?? 1;
    await ref.read(appSettingsProvider.notifier).updateSettings(
          llmBaseUrl: _baseUrlController.text.trim(),
          llmApiKey: _apiKeyController.text.trim(),
          llmModel: _modelController.text.trim(),
          transcriptionPrompt: _promptController.text.trim(),
          defaultReviewIntervalDays: reviewInterval,
        );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已保存')),
      );
      context.pop();
    }
  }

  void _showMessage(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red.shade700 : null,
      ),
    );
  }

  LlmConfig? _buildConfig() {
    final base = _baseUrlController.text.trim();
    final key = _apiKeyController.text.trim();
    final model = _modelController.text.trim();
    if (base.isEmpty || key.isEmpty || model.isEmpty) {
      _showMessage('请先填写 Base URL、API Key 和 Model', error: true);
      return null;
    }
    return LlmConfig(
      baseUrl: base,
      apiKey: key,
      model: model,
    );
  }

  Future<void> _fetchModels() async {
    final config = _buildConfig();
    if (config == null) return;
    setState(() => _loadingModels = true);
    try {
      final models = await ref
          .read(llmClientProvider)
          .fetchModels(config: config);
      if (!mounted) return;
      setState(() => _loadingModels = false);
      if (models.isEmpty) {
        _showMessage('未获取到模型列表，请检查服务商是否支持 /models 接口', error: true);
        return;
      }
      final selected = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('选择模型', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              ...models.map((m) => ListTile(
                    title: Text(m),
                    selected: m == _modelController.text,
                    onTap: () => Navigator.pop(ctx, m),
                  )),
            ],
          ),
        ),
      );
      if (selected != null) {
        setState(() => _modelController.text = selected);
      }
    } on DioException catch (e) {
      setState(() => _loadingModels = false);
      _showMessage('获取模型失败：${_dioError(e)}', error: true);
    } catch (e) {
      setState(() => _loadingModels = false);
      _showMessage('获取模型失败：$e', error: true);
    }
  }

  Future<void> _testConnection() async {
    final config = _buildConfig();
    if (config == null) return;
    setState(() => _testing = true);
    try {
      await ref.read(llmClientProvider).testConnection(config: config);
      if (!mounted) return;
      setState(() => _testing = false);
      _showMessage('连接成功，配置可用');
    } on DioException catch (e) {
      setState(() => _testing = false);
      _showMessage('连接失败：${_dioError(e)}', error: true);
    } catch (e) {
      setState(() => _testing = false);
      _showMessage('连接失败：$e', error: true);
    }
  }

  String _dioError(DioException e) {
    final resp = e.response;
    if (resp != null && resp.statusCode != null) {
      String? body;
      final data = resp.data;
      if (data is Map && data['error'] is Map) {
        body = (data['error'] as Map)['message']?.toString();
      } else if (data is Map && data['message'] != null) {
        body = data['message'].toString();
      }
      return 'HTTP ${resp.statusCode}${body == null ? '' : ' - $body'}';
    }
    return e.message ?? '网络错误';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('LLM 设置'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            decoration: const InputDecoration(
              labelText: '服务商预设',
              border: OutlineInputBorder(),
            ),
            hint: const Text('选择预设自动填充'),
            items: _presets.keys
                .map((k) => DropdownMenuItem(value: k, child: Text(k)))
                .toList(),
            onChanged: (name) {
              if (name == null) return;
              final p = _presets[name]!;
              _baseUrlController.text = p.baseUrl;
              _modelController.text = p.model;
            },
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _baseUrlController,
            decoration: const InputDecoration(
              labelText: 'Base URL',
              hintText: 'https://api.openai.com/v1',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _apiKeyController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'API Key',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _modelController,
            decoration: InputDecoration(
              labelText: 'Model',
              hintText: 'gpt-4o-mini / claude-3-haiku / deepseek-chat',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: '获取模型列表',
                icon: _loadingModels
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                onPressed: _loadingModels ? null : _fetchModels,
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _reviewIntervalController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '默认回顾间隔（天）',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          const Divider(height: 32),
          const Text(
            '转录提示词预设',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            decoration: const InputDecoration(
              labelText: '选择预设',
              border: OutlineInputBorder(),
            ),
            hint: const Text('选择转录风格预设'),
            items: transcriptionPromptPresets.keys
                .map((k) => DropdownMenuItem(value: k, child: Text(k)))
                .toList(),
            onChanged: (name) {
              if (name == null) return;
              _promptController.text = transcriptionPromptPresets[name]!;
            },
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _promptController,
            maxLines: 6,
            decoration: const InputDecoration(
              labelText: '转录提示词',
              hintText: '自定义 AI 转录时的系统提示词，可用 \$collectionType 表示内容类型',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 32),
          OutlinedButton.icon(
            onPressed: _testing ? null : _testConnection,
            icon: _testing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.wifi_tethering),
            label: const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text('测试连接'),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _save,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('保存'),
            ),
          ),
        ],
      ),
    );
  }
}
