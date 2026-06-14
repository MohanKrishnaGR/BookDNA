import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/haptics/haptics.dart';
import '../../core/providers.dart';
import '../../widgets/common.dart';
import 'ai_models.dart';
import 'ai_repository.dart';

const _suggestions = [
  'What do I own about AI agents?',
  'What should I read next?',
  'Which books mention leadership?',
  'Find my blind spots',
];

class _Message {
  _Message(this.isUser, this.text);

  final bool isUser;
  String text;
}

class AiChatScreen extends ConsumerStatefulWidget {
  const AiChatScreen({super.key});

  @override
  ConsumerState<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends ConsumerState<AiChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<_Message> _messages = [];
  bool _typing = false;

  @override
  void initState() {
    super.initState();
    _messages.add(_Message(
        false,
        'Hi! I know every book on your shelf. Ask me anything about '
        'your library.'));
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send(String raw) async {
    final text = raw.trim();
    if (text.isEmpty || _typing) return;
    final repo = ref.read(aiRepositoryProvider);
    if (repo == null) {
      showToast(context,
          'No backend configured — run with the Supabase dart-defines');
      return;
    }

    Haptics.tap();
    setState(() {
      _messages.add(_Message(true, text));
      _typing = true;
      _input.clear();
    });
    _scrollToEnd();

    // Send the trailing window of the conversation (skip the greeting).
    final turns = _messages
        .skip(1)
        .map((m) => (role: m.isUser ? 'user' : 'assistant', text: m.text))
        .toList();
    final window =
        turns.length > 18 ? turns.sublist(turns.length - 18) : turns;

    final reply = _Message(false, '');
    var replyShown = false;
    try {
      await for (final chunk in repo.chat(window)) {
        if (!mounted) return;
        setState(() {
          if (!replyShown) {
            _messages.add(reply);
            replyShown = true;
          }
          reply.text += chunk;
        });
        _scrollToEnd();
      }
    } on AiException catch (e) {
      if (!mounted) return;
      setState(() {
        if (replyShown) {
          _messages.remove(reply);
        }
        _messages.add(_Message(false, e.message));
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _messages
            .add(_Message(false, 'Connection hiccup — try that again.'));
      });
    } finally {
      if (mounted) setState(() => _typing = false);
      _scrollToEnd();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bookCount =
        (ref.watch(booksProvider).value ?? const []).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Library GPT'),
        leading: BackButton(onPressed: () => context.pop()),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: scheme.secondaryContainer,
              borderRadius: BorderRadius.circular(99),
            ),
            child: Row(children: [
              Icon(Icons.shelves,
                  size: 14, color: scheme.onSecondaryContainer),
              const SizedBox(width: 5),
              Text('$bookCount books indexed',
                  style: theme.textTheme.labelMedium!
                      .copyWith(color: scheme.onSecondaryContainer)),
            ]),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              itemCount: _messages.length + (_typing ? 1 : 0),
              itemBuilder: (context, i) {
                if (i == _messages.length) return const _TypingDots();
                final m = _messages[i];
                return Align(
                  alignment:
                      m.isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 5),
                    padding: const EdgeInsets.symmetric(
                        vertical: 11, horizontal: 15),
                    constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.82),
                    decoration: BoxDecoration(
                      color: m.isUser ? scheme.primary : scheme.surfaceContainer,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(20),
                        topRight: const Radius.circular(20),
                        bottomLeft: Radius.circular(m.isUser ? 20 : 6),
                        bottomRight: Radius.circular(m.isUser ? 6 : 20),
                      ),
                    ),
                    child: Text(
                      m.text,
                      style: theme.textTheme.bodyMedium!.copyWith(
                          color:
                              m.isUser ? scheme.onPrimary : scheme.onSurface),
                    ),
                  ),
                );
              },
            ),
          ),
          // Suggested prompts.
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final s in _suggestions)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ActionChip(
                      label: Text(s),
                      onPressed: _typing ? null : () => _send(s),
                    ),
                  ),
              ],
            ),
          ),
          // Input row.
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(children: [
                Expanded(
                  child: SizedBox(
                    height: 50,
                    child: TextField(
                      controller: _input,
                      onSubmitted: _send,
                      textInputAction: TextInputAction.send,
                      decoration: InputDecoration(
                        hintText: 'Ask your library…',
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 18),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(99),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _typing ? null : () => _send(_input.text),
                  iconSize: 22,
                  style: IconButton.styleFrom(
                      minimumSize: const Size(50, 50)),
                  icon: const Icon(Icons.arrow_upward_rounded),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          color: scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(20),
        ),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (i) {
              final phase = (_controller.value - i * 0.18) % 1.0;
              final lift = phase < 0.5 ? phase * 2 : (1 - phase) * 2;
              return Container(
                width: 7,
                height: 7,
                margin: const EdgeInsets.symmetric(horizontal: 2.5),
                transform:
                    Matrix4.translationValues(0, -3 * lift, 0),
                decoration: BoxDecoration(
                  color: scheme.onSurfaceVariant
                      .withValues(alpha: 0.3 + 0.7 * lift),
                  shape: BoxShape.circle,
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
