import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fav_app/features/collections/data/providers/collection_repository_provider.dart';
import 'package:fav_app/features/save/data/providers/transcription_providers.dart';

/// 与当前文章对话：加载全文作为 AI 上下文，支持多轮提问。
/// 正文过长时截断（保留开头），避免超出模型上下文窗口。
class ArticleChatPage extends ConsumerStatefulWidget {
  final String collectionId;

  const ArticleChatPage({super.key, required this.collectionId});

  @override
  ConsumerState<ArticleChatPage> createState() => _ArticleChatPageState();
}

class _ChatMessage {
  final bool isUser;
  final String text;
  _ChatMessage(this.isUser, this.text);
}

class _ArticleChatPageState extends ConsumerState<ArticleChatPage> {
  final List<_ChatMessage> _messages = [];
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  bool _sending = false;
  bool _loaded = false;
  String _articleText = '';

  @override
  void initState() {
    super.initState();
    _loadArticle();
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadArticle() async {
    final col = await ref.read(collectionRepositoryProvider).get(widget.collectionId);
    if (!mounted) return;
    if (col == null) {
      setState(() => _loaded = true);
      return;
    }
    var text = col.contentMd.trim();
    // 截断超长正文：保留开头部分作上下文
    const maxChars = 12000;
    if (text.length > maxChars) {
      text = '${text.substring(0, maxChars)}\n\n……（原文过长已截断）';
    }
    setState(() {
      _articleText = text;
      _loaded = true;
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final question = _inputCtrl.text.trim();
    if (question.isEmpty || _sending) return;

    final config = ref.read(llmConfigFromSettingsProvider);
    if (config == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未配置 LLM，请先在设置中填写 API Key')),
      );
      return;
    }

    setState(() {
      _sending = true;
      _messages.add(_ChatMessage(true, question));
      _inputCtrl.clear();
    });
    _scrollToBottom();

    try {
      // 构造多轮消息：system 带全文 + 历史对话
      final history = <Map<String, String>>[
        {
          'role': 'system',
          'content': '你是一个阅读助手。以下是用户收藏的一篇文章，'
              '请基于文章内容回答用户的问题；文章中没有的信息请如实说明，'
              '不要编造。回答使用中文。\n\n=== 文章正文 ===\n$_articleText',
        },
        for (final m in _messages)
          {'role': m.isUser ? 'user' : 'assistant', 'content': m.text},
      ];
      final reply = await ref.read(llmClientProvider).chat(
            config: config,
            messages: history,
          );
      setState(() => _messages.add(_ChatMessage(false, reply)));
    } catch (e) {
      setState(() => _messages.add(_ChatMessage(false, '请求失败：$e')));
    } finally {
      setState(() => _sending = false);
      _scrollToBottom();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('与文章对话')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : _articleText.isEmpty
              ? const Center(child: Text('该收藏没有正文，无法对话'))
              : Column(
                  children: [
                    Expanded(
                      child: _messages.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.forum_outlined,
                                      size: 56, color: scheme.outline),
                                  const SizedBox(height: 12),
                                  Text('已读完全文，随便问点什么',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyLarge),
                                  const SizedBox(height: 8),
                                  const Text('例如：这篇文章的核心观点是什么？'),
                                ],
                              ),
                            )
                          : ListView.builder(
                              controller: _scrollCtrl,
                              padding: const EdgeInsets.all(12),
                              itemCount: _messages.length + (_sending ? 1 : 0),
                              itemBuilder: (_, i) {
                                if (i == _messages.length) {
                                  return const Align(
                                    alignment: Alignment.centerLeft,
                                    child: Padding(
                                      padding: EdgeInsets.all(12),
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    ),
                                  );
                                }
                                final m = _messages[i];
                                return Align(
                                  alignment: m.isUser
                                      ? Alignment.centerRight
                                      : Alignment.centerLeft,
                                  child: Container(
                                    margin: const EdgeInsets.symmetric(
                                        vertical: 4),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 10),
                                    constraints: BoxConstraints(
                                      maxWidth:
                                          MediaQuery.of(context).size.width *
                                              0.78,
                                    ),
                                    decoration: BoxDecoration(
                                      color: m.isUser
                                          ? scheme.primary
                                          : scheme.surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Text(
                                      m.text,
                                      style: TextStyle(
                                        color: m.isUser
                                            ? scheme.onPrimary
                                            : scheme.onSurface,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _inputCtrl,
                                minLines: 1,
                                maxLines: 4,
                                decoration: const InputDecoration(
                                  hintText: '基于这篇文章提问...',
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                ),
                                onSubmitted: (_) => _send(),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton.filled(
                              icon: const Icon(Icons.send),
                              onPressed: _sending ? null : _send,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
