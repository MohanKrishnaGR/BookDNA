import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/analytics/analytics.dart';
import '../../core/db/database.dart';
import '../../core/providers.dart';
import '../../widgets/book_cover.dart';
import '../../widgets/common.dart';
import 'ai_models.dart';
import 'ai_repository.dart';

class AiAnalysisScreen extends ConsumerStatefulWidget {
  const AiAnalysisScreen({super.key});

  @override
  ConsumerState<AiAnalysisScreen> createState() => _AiAnalysisScreenState();
}

enum _Phase { idle, working, done }

class _AiAnalysisScreenState extends ConsumerState<AiAnalysisScreen> {
  _Phase _phase = _Phase.idle;
  int _step = 0;
  Timer? _stepTimer;
  ShelfAnalysis? _analysis;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Show the latest cached analysis on revisit.
    ref.read(aiRepositoryProvider)?.cachedAnalysis().then((cached) {
      if (cached != null && mounted && _phase == _Phase.idle) {
        setState(() {
          _analysis = cached;
          _phase = _Phase.done;
        });
      }
    });
  }

  @override
  void dispose() {
    _stepTimer?.cancel();
    super.dispose();
  }

  List<String> get _steps {
    final count = (ref.read(booksProvider).value ?? const []).length;
    return [
      'Reading $count spines…',
      'Mapping genres & eras…',
      'Finding blind spots…',
      'Building your profile…',
    ];
  }

  Future<void> _run() async {
    final repo = ref.read(aiRepositoryProvider);
    if (repo == null) {
      showToast(context,
          'No backend configured — run with the Supabase dart-defines');
      return;
    }
    setState(() {
      _phase = _Phase.working;
      _step = 0;
      _error = null;
    });
    _stepTimer = Timer.periodic(const Duration(milliseconds: 620), (_) {
      if (mounted && _step < 3) setState(() => _step++);
    });

    try {
      final result = await repo.analyze();
      Analytics.instance.log('ai_analysis_run', {
        'is_demo': result.isDemo ? 1 : 0,
      });
      if (!mounted) return;
      setState(() {
        _analysis = result;
        _phase = _Phase.done;
      });
    } on AiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        // Fall back to the cached result if we have one.
        _phase = _analysis != null ? _Phase.done : _Phase.idle;
      });
      showToast(context, e.message);
    } finally {
      _stepTimer?.cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI analysis'),
        leading: BackButton(onPressed: () => context.pop()),
        actions: [
          IconButton(
            onPressed: () => context.push('/ai/chat'),
            icon: const Icon(Icons.forum_outlined),
          ),
        ],
      ),
      body: switch (_phase) {
        _Phase.idle => _idle(theme),
        _Phase.working => _working(theme),
        _Phase.done => _done(theme),
      },
    );
  }

  Widget _idle(ThemeData theme) {
    final scheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(32),
              ),
              child: Icon(Icons.auto_awesome_rounded,
                  size: 44, color: scheme.onPrimaryContainer),
            ),
            const SizedBox(height: 22),
            Text('Decode your library',
                style: theme.textTheme.headlineSmall),
            const SizedBox(height: 10),
            Text(
              'BookDNA reads your whole shelf and tells you what it says '
              'about you — and what\'s missing.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium!
                  .copyWith(color: scheme.onSurfaceVariant),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall!
                      .copyWith(color: scheme.error)),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _run,
              style: FilledButton.styleFrom(minimumSize: const Size(0, 50)),
              icon: const Icon(Icons.psychology_rounded),
              label: const Text('Analyze my library'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _working(ThemeData theme) {
    final scheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 1, end: 1.08),
              duration: const Duration(milliseconds: 1100),
              curve: Curves.easeInOut,
              builder: (context, scale, child) =>
                  Transform.scale(scale: scale, child: child),
              child: Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(32),
                ),
                child: Icon(Icons.auto_awesome_rounded,
                    size: 44, color: scheme.onPrimaryContainer),
              ),
            ),
            const SizedBox(height: 26),
            Text(_steps[_step], style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('This takes a few seconds.',
                style: theme.textTheme.bodySmall!
                    .copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 22),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: SizedBox(
                width: 220,
                child: LinearProgressIndicator(
                  value: (_step + 1) / 4,
                  minHeight: 8,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _done(ThemeData theme) {
    final scheme = theme.colorScheme;
    final analysis = _analysis!;
    final books = ref.watch(booksProvider).value ?? const <Book>[];
    Book? byShortId(String shortId) {
      for (final b in books) {
        if (b.id.startsWith(shortId)) return b;
      }
      return null;
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        if (analysis.isDemo)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Card(
              color: scheme.tertiaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'Demo result — connect ANTHROPIC_API_KEY on the server '
                  'for a real analysis.',
                  style: theme.textTheme.labelMedium!
                      .copyWith(color: scheme.onTertiaryContainer),
                ),
              ),
            ),
          ),

        // Reading profile.
        Card(
          color: scheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('READING PROFILE',
                    style: theme.textTheme.labelMedium!.copyWith(
                        color: scheme.onPrimaryContainer
                            .withValues(alpha: 0.7),
                        letterSpacing: 1.2)),
                const SizedBox(height: 6),
                Text(analysis.archetype,
                    style: theme.textTheme.headlineSmall!
                        .copyWith(color: scheme.onPrimaryContainer)),
                const SizedBox(height: 8),
                Text(analysis.readingProfile,
                    style: theme.textTheme.bodyMedium!.copyWith(
                        color: scheme.onPrimaryContainer
                            .withValues(alpha: 0.9))),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final t in analysis.traits)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: scheme.onPrimaryContainer
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(t,
                            style: theme.textTheme.labelMedium!.copyWith(
                                color: scheme.onPrimaryContainer)),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Blind spots.
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.visibility_off_rounded,
                      size: 20, color: scheme.error),
                  const SizedBox(width: 8),
                  Text('Blind spots', style: theme.textTheme.titleMedium),
                ]),
                const SizedBox(height: 12),
                for (final spot in analysis.blindSpots)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.radio_button_unchecked_rounded,
                            size: 16, color: scheme.onSurfaceVariant),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(spot.area,
                                  style: theme.textTheme.titleSmall),
                              Text(spot.why,
                                  style: theme.textTheme.bodySmall!.copyWith(
                                      color: scheme.onSurfaceVariant)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Read next.
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.auto_stories_rounded,
                      size: 20, color: scheme.primary),
                  const SizedBox(width: 8),
                  Text('Read next — from your own shelf',
                      style: theme.textTheme.titleMedium),
                ]),
                const SizedBox(height: 8),
                for (final pick in analysis.readNext)
                  if (byShortId(pick.bookId) case final Book book)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      onTap: () => context.push('/book/${book.id}'),
                      leading: BookCover(
                          title: book.title,
                          author: book.author,
                          hueShift: book.hueShift,
                          width: 36,
                          radius: 4,
                          shadow: false),
                      title: Text(book.title,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(pick.reason,
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                      trailing: const Icon(Icons.chevron_right_rounded),
                    ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Knowledge graph link.
        Card(
          color: scheme.tertiaryContainer,
          child: ListTile(
            onTap: () => context.push('/graph'),
            leading: Icon(Icons.hub_rounded,
                color: scheme.onTertiaryContainer),
            title: Text('Knowledge graph',
                style: TextStyle(color: scheme.onTertiaryContainer)),
            subtitle: Text(
                'How your books connect — clusters & bridges',
                style: TextStyle(
                    color: scheme.onTertiaryContainer
                        .withValues(alpha: 0.8))),
            trailing: Icon(Icons.chevron_right_rounded,
                color: scheme.onTertiaryContainer),
          ),
        ),
        const SizedBox(height: 8),

        // Chat link.
        Card(
          color: scheme.secondaryContainer,
          child: ListTile(
            onTap: () => context.push('/ai/chat'),
            leading: Icon(Icons.forum_rounded,
                color: scheme.onSecondaryContainer),
            title: Text('Ask your library anything',
                style: TextStyle(color: scheme.onSecondaryContainer)),
            subtitle: Text('"What do I own about AI agents?"',
                style: TextStyle(
                    color: scheme.onSecondaryContainer
                        .withValues(alpha: 0.8))),
            trailing: Icon(Icons.chevron_right_rounded,
                color: scheme.onSecondaryContainer),
          ),
        ),
        const SizedBox(height: 16),
        TextButton.icon(
          onPressed: _run,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Run a fresh analysis'),
        ),
      ],
    );
  }
}
