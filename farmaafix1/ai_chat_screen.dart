import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/ai_service.dart';
import '../../../generated/l10n/app_localizations.dart';

class AIChatScreen extends ConsumerStatefulWidget {
  const AIChatScreen({super.key});

  @override
  ConsumerState<AIChatScreen> createState() => _AIChatScreenState();
}

class _AIChatScreenState extends ConsumerState<AIChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<_ChatMessage> _messages = [];
  List<String> _suggestions = [
    'Current rice prices',
    'Pest control for wheat',
    'Government schemes',
    'Millet cultivation tips',
  ];
  bool _isTyping = false;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      _messages.add(_ChatMessage(
        text: AppLocalizations.of(context).howCanIHelp,
        isUser: false,
        timestamp: DateTime.now(),
      ));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ── Send message ──────────────────────────────────────────────────────────

  Future<void> _handleSend([String? predefinedText]) async {
    final text = (predefinedText ?? _controller.text).trim();
    if (text.isEmpty || _isTyping) return;

    _controller.clear();
    setState(() {
      _messages.add(_ChatMessage(
        text: text,
        isUser: true,
        timestamp: DateTime.now(),
      ));
      _isTyping = true;
      _suggestions = [];
    });
    _scrollToBottom();

    try {
      // Build history for context (last 10 messages)
      final history = _messages
          .take(_messages.length - 1) // exclude the one we just added
          .skip(_messages.length > 11 ? _messages.length - 11 : 0)
          .map((m) => <String, String>{
                'role': m.isUser ? 'user' : 'assistant',
                'content': m.text,
              })
          .toList();

      // Add current message
      history.add({'role': 'user', 'content': text});

      final response = await AIService.instance.getChatResponse(history);

      if (mounted) {
        setState(() {
          _isTyping = false;
          _messages.add(_ChatMessage(
            text: response.content,
            isUser: false,
            timestamp: DateTime.now(),
          ));
          _suggestions = response.suggestions;
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isTyping = false;
          _messages.add(_ChatMessage(
            text: "Sorry, I'm having trouble connecting right now. Please try again.",
            isUser: false,
            timestamp: DateTime.now(),
            isError: true,
          ));
        });
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _clearChat() {
    setState(() {
      _messages.clear();
      _messages.add(_ChatMessage(
        text: AppLocalizations.of(context).howCanIHelp,
        isUser: false,
        timestamp: DateTime.now(),
      ));
      _suggestions = [
        'Current rice prices',
        'Pest control tips',
        'Government schemes',
        'Millet prices',
      ];
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: AppTheme.surfaceCream,
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Text('🤖', style: TextStyle(fontSize: 16)),
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Farmaa ${l.aiAssistant}',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const Text(
                  'Powered by LLaMA 3.1',
                  style: TextStyle(
                      fontSize: 10,
                      color: AppTheme.primaryGreenLight,
                      fontWeight: FontWeight.w400),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Clear chat',
            onPressed: _clearChat,
          ),
        ],
      ),
      body: Column(
        children: [
          // Message list
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: _messages.length,
              itemBuilder: (ctx, i) => _ChatBubble(
                message: _messages[i],
                onLongPress: () {
                  Clipboard.setData(ClipboardData(text: _messages[i].text));
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Copied to clipboard')),
                  );
                },
              ),
            ),
          ),

          // Typing indicator
          if (_isTyping)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      gradient: AppTheme.primaryGradient,
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: Text('🤖', style: TextStyle(fontSize: 14)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: AppTheme.radiusLarge,
                      boxShadow: AppTheme.cardShadow,
                    ),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppTheme.primaryGreen,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          l.aiThinking,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.textLight,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          // Suggestion chips
          if (_suggestions.isNotEmpty && !_isTyping)
            Container(
              height: 40,
              margin: const EdgeInsets.only(bottom: 4),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _suggestions.length,
                itemBuilder: (ctx, i) => GestureDetector(
                  onTap: () => _handleSend(_suggestions[i]),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryGreen.withValues(alpha: 0.08),
                      borderRadius: AppTheme.radiusRound,
                      border: Border.all(
                          color: AppTheme.primaryGreen.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      _suggestions[i],
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.primaryGreen,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // Input bar
          _buildInputBar(l),
        ],
      ),
    );
  }

  Widget _buildInputBar(AppLocalizations l) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          12, 8, 12, MediaQuery.of(context).padding.bottom + 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            offset: const Offset(0, -4),
            blurRadius: 12,
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              textCapitalization: TextCapitalization.sentences,
              maxLines: 4,
              minLines: 1,
              enabled: !_isTyping,
              decoration: InputDecoration(
                hintText: l.askAnything,
                filled: true,
                fillColor: AppTheme.surfaceCream,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                isDense: true,
              ),
              onSubmitted: (_) => _handleSend(),
            ),
          ),
          const SizedBox(width: 8),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            child: CircleAvatar(
              radius: 22,
              backgroundColor:
                  _isTyping ? AppTheme.textLight : AppTheme.primaryGreen,
              child: IconButton(
                icon: Icon(
                  _isTyping ? Icons.hourglass_empty : Icons.send_rounded,
                  color: Colors.white,
                  size: 18,
                ),
                onPressed: _isTyping ? null : () => _handleSend(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Chat message model ────────────────────────────────────────────────────────

class _ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final bool isError;

  const _ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.isError = false,
  });
}

// ── Chat bubble widget ────────────────────────────────────────────────────────

class _ChatBubble extends StatelessWidget {
  final _ChatMessage message;
  final VoidCallback? onLongPress;

  const _ChatBubble({required this.message, this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                shape: BoxShape.circle,
              ),
              child: const Center(
                  child: Text('🤖', style: TextStyle(fontSize: 12))),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: GestureDetector(
              onLongPress: onLongPress,
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.78,
                ),
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isUser
                      ? AppTheme.primaryGreen
                      : message.isError
                          ? AppTheme.errorRed.withValues(alpha: 0.08)
                          : Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(18),
                    bottomLeft: Radius.circular(isUser ? 18 : 4),
                    bottomRight: Radius.circular(isUser ? 4 : 18),
                  ),
                  boxShadow: isUser ? null : AppTheme.cardShadow,
                  border: message.isError
                      ? Border.all(
                          color: AppTheme.errorRed.withValues(alpha: 0.2))
                      : null,
                ),
                child: Text(
                  message.text,
                  style: TextStyle(
                    color: isUser
                        ? Colors.white
                        : message.isError
                            ? AppTheme.errorRed
                            : AppTheme.textDark,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
              ),
            ),
          ),
          if (isUser) const SizedBox(width: 34),
          if (!isUser) const SizedBox(width: 34),
        ],
      ),
    );
  }
}
