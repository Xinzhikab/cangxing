import 'dart:async';

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
  final bool isSystem;
  final String text;
  _ChatMessage(this.isUser, this.text, {this.isSystem = false});
}

class _ArticleChatPageState extends ConsumerState<ArticleChatPage> {
  final List<_ChatMessage> _messages = [];
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  bool _sending = false;
  bool _loaded = false;
  String _articleText = '';
  bool _showTruncateBanner = false;
  int _truncatedChars = 0;
  StreamSubscription<String>? _streamSub;
  int? _streamingIdx;

  @override
  void initState() {
    super.initState();
    _loadArticle();
  }

  @override
  void dispose() {
    _streamSub?.cancel();
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
    const maxChars = 12000;
    if (text.length > maxChars) {
      _truncatedChars = text.length - maxChars;
      _showTruncateBanner = true;
      text = text.substring(0, maxChars);
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
      if (_showTruncateBanner && !_messages.any((m) => m.isSystem)) {
        const maxChars = 12000;
        _messages.insert(0, _ChatMessage(
          false,
          '⚠️ 正文过长（${maxChars + _truncatedChars} 字），为节省 token 已截取前 $maxChars 字。'
          '如需完整上下文可切换到【摘要模式】（即将上线）。',
          isSystem: true,
        ));
      }
      _messages.add(_ChatMessage(true, question));
      _inputCtrl.clear();
    });

    // 构建对话历史（此时 _messages 还未包含 assistant 占位消息）
    final history = <Map<String, String>>[
      {
        'role': 'system',
        'content': '你是一个阅读助手。以下是用户收藏的一篇文章，'
            '请基于文章内容回答用户的问题；文章中没有的信息请如实说明，'
            '不要编造。回答使用中文。\n\n=== 文章正文 ===\n$_articleText',
      },
      for (final m in _messages)
        if (m.isSystem)
          {'role': 'system', 'content': m.text}
        else
          {'role': m.isUser ? 'user' : 'assistant', 'content': m.text},
    ];

    // 先添加一条空的 assistant 消息，随流逐步更新
    setState(() {
      _messages.add(_ChatMessage(false, ''));
      _streamingIdx = _messages.length - 1;
    });
    _scrollToBottom();
    final assistantIdx = _streamingIdx!;

    final client = ref.read(llmClientProvider);
    String fullReply = '';
    try {
      _streamSub = client
          .chatStream(config: config, messages: history)
          .listen(
        (token) {
          fullReply += token;
          if (!mounted) return;
          setState(() {
            _messages[assistantIdx] = _ChatMessage(false, fullReply);
          });
          _scrollToBottom();
        },
        onDone: () {
          _streamSub = null;
          if (!mounted) return;
          if (fullReply.isEmpty) {
            setState(() {
              _messages[assistantIdx] = _ChatMessage(false, '（回复为空）');
            });
          }
          setState(() {
            _sending = false;
            _streamingIdx = null;
          });
        },
        onError: (e) {
          _streamSub = null;
          if (!mounted) return;
          setState(() {
            // 流中断时保留已收到的部分回复；若一点没收到则提示错误
            if (fullReply.isEmpty) {
              _messages[assistantIdx] = _ChatMessage(false, '请求失败：$e');
            }
            _sending = false;
            _streamingIdx = null;
          });
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (fullReply.isEmpty) {
          _messages[assistantIdx] = _ChatMessage(false, '请求失败：$e');
        }
        _sending = false;
        _streamingIdx = null;
      });
    }
  }

  /// 取消正在进行的流式回复，保留已收到的部分内容。
  void _stopStreaming() {
    _streamSub?.cancel();
    _streamSub = null;
    setState(() {
      _sending = false;
      _streamingIdx = null;
    });
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
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      height: _showTruncateBanner ? 36 : 0,
                      color: scheme.tertiaryContainer,
                      child: _showTruncateBanner
                          ? Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: Row(
                                children: [
                                  Icon(Icons.info_outline, size: 16, color: scheme.onTertiaryContainer),
                                  const SizedBox(width: 6),
                                  Text(
                                    '已截断 $_truncatedChars 字，仅使用前 12000 字作为上下文',
                                    style: TextStyle(fontSize: 12, color: scheme.onTertiaryContainer),
                                  ),
                                  const Spacer(),
                                  IconButton(
                                    icon: Icon(Icons.close, size: 16, color: scheme.onTertiaryContainer),
                                    visualDensity: VisualDensity.compact,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    onPressed: () => setState(() => _showTruncateBanner = false),
                                  ),
                                ],
                              ),
                            )
                          : null,
                    ),
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
                              itemCount: _messages.length,
                              itemBuilder: (_, i) {
                                final m = _messages[i];
                                if (m.isSystem) {
                                  return Container(
                                    margin: const EdgeInsets.symmetric(vertical: 6),
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: scheme.tertiaryContainer.withValues(alpha: 0.5),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
                                    ),
                                    child: Text(
                                      m.text,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: scheme.onTertiaryContainer,
                                        height: 1.4,
                                      ),
                                    ),
                                  );
                                }
                                final streaming = _sending && i == _streamingIdx;
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
                                      streaming ? '${m.text}▋' : m.text,
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
                              icon: Icon(_sending ? Icons.stop : Icons.send),
                              onPressed: _sending ? _stopStreaming : _send,
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
