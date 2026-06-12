import 'package:fl_chart/fl_chart.dart' hide RadarChart;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/book_accent.dart';
import '../../core/providers.dart';
import '../../core/utils/format.dart';
import '../../widgets/common.dart';
import '../tracker/heatmap.dart';
import 'charts/radar_chart.dart';
import 'logic/formulas.dart';
import 'logic/personality.dart';

class InsightsScreen extends ConsumerWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final books = ref.watch(booksProvider).value ?? [];
    final sessions = ref.watch(allSessionsProvider).value ?? [];
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final stats = computeLibraryStats(books, sessions);
    final genres = genreBreakdown(books);
    final personality = computePersonality(books, sessions);
    final diversity = computeDiversity(books);
    final evo = evolution(books);
    final heat = readingHeatmap(sessions, weeks: 18);
    final streak = currentStreak(sessions);
    final best = bestStreak(sessions);
    final authors = topAuthors(books);
    final valuable = [...books]..sort((a, b) =>
        (b.estValue ?? b.price ?? 0).compareTo(a.estValue ?? a.price ?? 0));

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            // Header.
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Insights', style: theme.textTheme.headlineSmall),
                    Text('Your bookshelf, decoded',
                        style: theme.textTheme.bodySmall!
                            .copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
                FilledButton.tonalIcon(
                  onPressed: () => context.push('/wrapped'),
                  icon: const Icon(Icons.play_circle_rounded, size: 18),
                  label: const Text('Wrapped'),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Counter rail.
            SizedBox(
              height: 86,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _counter(context, stats.owned, 'Books'),
                  _counter(context, stats.uniqueAuthors, 'Authors'),
                  _counter(context, stats.uniqueGenres, 'Genres'),
                  _counter(context, stats.totalPages, 'Pages'),
                  _counter(context, stats.readingHours, 'Hours read'),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Shelf DNA donut.
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Shelf DNA', style: theme.textTheme.titleMedium),
                    Text('What your collection is made of',
                        style: theme.textTheme.bodySmall!
                            .copyWith(color: scheme.onSurfaceVariant)),
                    const SizedBox(height: 16),
                    Row(children: [
                      SizedBox(
                        width: 158,
                        height: 158,
                        child: Stack(alignment: Alignment.center, children: [
                          PieChart(
                            PieChartData(
                              sectionsSpace: 2,
                              centerSpaceRadius: 52,
                              startDegreeOffset: -90,
                              sections: [
                                for (final g in genres)
                                  PieChartSectionData(
                                    value: g.pct,
                                    showTitle: false,
                                    radius: 22,
                                    color: accentFor(
                                            hueShiftForGenre(g.name),
                                            theme.brightness)
                                        .main,
                                  ),
                              ],
                            ),
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('${stats.owned}',
                                  style: theme.textTheme.titleLarge),
                              Text('books',
                                  style: theme.textTheme.bodySmall!.copyWith(
                                      color: scheme.onSurfaceVariant)),
                            ],
                          ),
                        ]),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final g in genres)
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 4),
                                child: Row(children: [
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: accentFor(
                                              hueShiftForGenre(g.name),
                                              theme.brightness)
                                          .main,
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(g.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodyMedium),
                                  ),
                                  Text('${g.pct.round()}%',
                                      style: theme.textTheme.labelMedium),
                                ]),
                              ),
                          ],
                        ),
                      ),
                    ]),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Personality.
            Card(
              color: scheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.architecture_rounded,
                        size: 32, color: scheme.onPrimaryContainer),
                    const SizedBox(height: 10),
                    Text('READING PERSONALITY',
                        style: theme.textTheme.labelMedium!.copyWith(
                            color: scheme.onPrimaryContainer
                                .withValues(alpha: 0.7),
                            letterSpacing: 1.2)),
                    const SizedBox(height: 4),
                    Text(personality.archetype,
                        style: theme.textTheme.headlineSmall!
                            .copyWith(color: scheme.onPrimaryContainer)),
                    const SizedBox(height: 8),
                    Text(personality.description,
                        style: theme.textTheme.bodyMedium!.copyWith(
                            color: scheme.onPrimaryContainer
                                .withValues(alpha: 0.9))),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final t in personality.traits)
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

            // Evolution curve.
            if (evo.length >= 2)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Reading evolution',
                          style: theme.textTheme.titleMedium),
                      Text('Your dominant theme, year by year',
                          style: theme.textTheme.bodySmall!
                              .copyWith(color: scheme.onSurfaceVariant)),
                      const SizedBox(height: 18),
                      SizedBox(
                        height: 172,
                        child: LineChart(
                          LineChartData(
                            gridData: const FlGridData(show: false),
                            titlesData: FlTitlesData(
                              leftTitles: const AxisTitles(),
                              topTitles: const AxisTitles(),
                              rightTitles: const AxisTitles(),
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  interval: 1,
                                  getTitlesWidget: (v, meta) {
                                    final i = v.toInt();
                                    if (i < 0 || i >= evo.length) {
                                      return const SizedBox.shrink();
                                    }
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: Text(
                                        i.isEven ? evo[i].year : '',
                                        style: theme.textTheme.labelSmall,
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                            borderData: FlBorderData(show: false),
                            lineTouchData: LineTouchData(
                              touchTooltipData: LineTouchTooltipData(
                                getTooltipItems: (spots) => [
                                  for (final s in spots)
                                    LineTooltipItem(
                                      '${evo[s.x.toInt()].year} · ${evo[s.x.toInt()].topic}',
                                      theme.textTheme.labelMedium!.copyWith(
                                          color: scheme.onInverseSurface),
                                    ),
                                ],
                              ),
                            ),
                            lineBarsData: [
                              LineChartBarData(
                                isCurved: true,
                                barWidth: 3,
                                color: scheme.primary,
                                dotData: FlDotData(
                                  show: true,
                                  checkToShowDot: (spot, _) =>
                                      spot.x == evo.length - 1,
                                ),
                                belowBarData: BarAreaData(
                                  show: true,
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      scheme.primary
                                          .withValues(alpha: 0.28),
                                      scheme.primary.withValues(alpha: 0),
                                    ],
                                  ),
                                ),
                                spots: [
                                  for (var i = 0; i < evo.length; i++)
                                    FlSpot(i.toDouble(), evo[i].v),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Trajectory: ${evo.map((e) => e.topic).toSet().take(4).join(' → ')}.',
                        style: theme.textTheme.bodySmall!
                            .copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),

            // Heatmap + streaks.
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Reading activity',
                            style: theme.textTheme.titleMedium),
                        Text('last 18 weeks',
                            style: theme.textTheme.labelMedium!
                                .copyWith(color: scheme.onSurfaceVariant)),
                      ],
                    ),
                    const SizedBox(height: 14),
                    HeatmapGrid(data: heat),
                    const SizedBox(height: 12),
                    Row(children: [
                      Icon(Icons.local_fire_department_rounded,
                          size: 18, color: scheme.tertiary),
                      const SizedBox(width: 6),
                      Text('$streak-day streak · best $best',
                          style: theme.textTheme.labelLarge),
                    ]),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Diversity radar.
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Diversity score',
                                style: theme.textTheme.titleMedium),
                            Text('How wide your world is',
                                style: theme.textTheme.bodySmall!.copyWith(
                                    color: scheme.onSurfaceVariant)),
                          ],
                        ),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('${diversity.score}',
                                style: theme.textTheme.headlineMedium),
                            Text('/100', style: theme.textTheme.bodyMedium),
                          ],
                        ),
                      ],
                    ),
                    Center(
                        child:
                            RadarChart(points: diversity.points, size: 250)),
                    Text(
                      'Weakest axis: ${diversity.weakest.axis.toLowerCase()} — the easiest place to grow your range.',
                      style: theme.textTheme.bodySmall!
                          .copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Author analytics.
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Author analytics',
                        style: theme.textTheme.titleMedium),
                    const SizedBox(height: 14),
                    for (var i = 0; i < authors.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Text(authors[i].name,
                                    style: theme.textTheme.bodyMedium),
                                Text(
                                    '${authors[i].owned} owned · ${authors[i].read} read',
                                    style: theme.textTheme.labelMedium!
                                        .copyWith(
                                            color:
                                                scheme.onSurfaceVariant)),
                              ],
                            ),
                            const SizedBox(height: 5),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(99),
                              child: LinearProgressIndicator(
                                value: authors[i].owned / authors.first.owned,
                                minHeight: 8,
                                color: accentFor(i * 60, theme.brightness)
                                    .main,
                                backgroundColor:
                                    scheme.surfaceContainerHighest,
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

            // Library worth.
            Card(
              color: scheme.secondaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Library worth',
                        style: theme.textTheme.titleMedium!
                            .copyWith(color: scheme.onSecondaryContainer)),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AnimatedCounter(
                              value: stats.libraryValue.round(),
                              format: formatInr,
                              style: theme.textTheme.headlineSmall!.copyWith(
                                  color: scheme.onSecondaryContainer),
                            ),
                            Text('estimated value',
                                style: theme.textTheme.bodySmall!.copyWith(
                                    color: scheme.onSecondaryContainer
                                        .withValues(alpha: 0.75))),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AnimatedCounter(
                              value: stats.totalInvestment.round(),
                              format: formatInr,
                              style: theme.textTheme.headlineSmall!.copyWith(
                                  color: scheme.onSecondaryContainer
                                      .withValues(alpha: 0.8)),
                            ),
                            Text('invested',
                                style: theme.textTheme.bodySmall!.copyWith(
                                    color: scheme.onSecondaryContainer
                                        .withValues(alpha: 0.75))),
                          ],
                        ),
                      ),
                    ]),
                    const SizedBox(height: 14),
                    Text('MOST VALUABLE',
                        style: theme.textTheme.labelSmall!.copyWith(
                            color: scheme.onSecondaryContainer
                                .withValues(alpha: 0.7),
                            letterSpacing: 1)),
                    const SizedBox(height: 6),
                    for (final b in valuable.take(3))
                      InkWell(
                        onTap: () => context.push('/book/${b.id}'),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(children: [
                            Expanded(
                              child: Text(b.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium!.copyWith(
                                      color: scheme.onSecondaryContainer)),
                            ),
                            Text(formatInr(b.estValue ?? b.price ?? 0),
                                style: theme.textTheme.labelLarge!.copyWith(
                                    color: scheme.onSecondaryContainer)),
                          ]),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Unread knowledge.
            Card(
              color: scheme.tertiaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Unread knowledge',
                        style: theme.textTheme.titleMedium!
                            .copyWith(color: scheme.onTertiaryContainer)),
                    const SizedBox(height: 14),
                    Row(children: [
                      _unreadStat(context, '${stats.unread}', 'books'),
                      _unreadStat(context,
                          formatNumber(stats.unreadPages), 'pages'),
                      _unreadStat(
                          context, '${stats.unreadHours}h', 'of knowledge'),
                    ]),
                    const SizedBox(height: 12),
                    Text(
                      stats.unreadHours > 0
                          ? 'At your current pace, that\'s ${(stats.unreadHours / 365).toStringAsFixed(1)} years of reading already sitting on your shelf.'
                          : 'Your shelf is fully read — time to scan something new.',
                      style: theme.textTheme.bodySmall!.copyWith(
                          color: scheme.onTertiaryContainer
                              .withValues(alpha: 0.85)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // AI analysis entry point.
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: scheme.outlineVariant),
              ),
              color: Colors.transparent,
              child: ListTile(
                onTap: () => context.push('/ai'),
                leading: Icon(Icons.auto_awesome_rounded,
                    color: scheme.primary),
                title: const Text('Go deeper with AI analysis'),
                subtitle:
                    const Text('Blind spots, next reads, knowledge graph'),
                trailing: const Icon(Icons.chevron_right_rounded),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _counter(BuildContext context, int value, String label) {
    final theme = Theme.of(context);
    return Container(
      width: 104,
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedCounter(
              value: value,
              format: (v) => formatNumber(v),
              style: theme.textTheme.titleLarge),
          Text(label,
              style: theme.textTheme.labelMedium!
                  .copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _unreadStat(BuildContext context, String value, String label) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: theme.textTheme.titleLarge!
                  .copyWith(color: scheme.onTertiaryContainer)),
          Text(label,
              style: theme.textTheme.bodySmall!.copyWith(
                  color:
                      scheme.onTertiaryContainer.withValues(alpha: 0.75))),
        ],
      ),
    );
  }
}
