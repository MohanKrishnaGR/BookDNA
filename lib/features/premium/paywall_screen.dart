import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/analytics/analytics.dart';
import '../../core/haptics/haptics.dart';
import '../../widgets/common.dart';
import 'entitlement.dart';

const _features = [
  (Icons.psychology_rounded, 'AI knowledge graph',
      'See how every book on your shelf connects'),
  (Icons.photo_camera_rounded, 'Shelf photo recognition',
      'Add 30 books from one photo of your shelf (coming soon)'),
  (Icons.insights_rounded, 'Advanced analytics',
      'Diversity, worth, blind spots — full depth'),
  (Icons.forum_rounded, 'Unlimited Library GPT',
      'Ask your shelf anything, without limits'),
  (Icons.description_rounded, 'Custom reports',
      'Monthly PDF wrapped, export everything'),
];

class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key});

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  bool _yearly = false;
  bool _busy = false;

  Future<void> _subscribe() async {
    final premium = ref.read(premiumProvider).value;
    if (premium?.active ?? false) return;
    setState(() => _busy = true);
    try {
      final next =
          await ref.read(premiumProvider.notifier).startTrial();
      Analytics.instance.log('trial_started', {'plan': _yearly ? 'yearly' : 'monthly'});
      Haptics.success();
      if (!mounted) return;
      showToast(context,
          'Trial started — Premium until ${next.until!.day}/${next.until!.month}');
      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted) context.pop();
    } on PremiumException catch (e) {
      if (!mounted) return;
      Haptics.error();
      showToast(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final premium = ref.watch(premiumProvider).value ?? const PremiumState();

    return Scaffold(
      appBar: AppBar(leading: BackButton(onPressed: () => context.pop())),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        children: [
          Center(
            child: Column(children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Icon(Icons.workspace_premium_rounded,
                    size: 36, color: scheme.onPrimaryContainer),
              ),
              const SizedBox(height: 14),
              Text('BookDNA Premium',
                  style: theme.textTheme.headlineMedium),
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 280),
                child: Text(
                  premium.active
                      ? 'Premium is active — ${premium.daysLeft} day${premium.daysLeft == 1 ? '' : 's'} left.'
                      : 'Your shelf has more to say. Unlock the full intelligence layer.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge!
                      .copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 26),

          for (final (icon, title, sub) in _features)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: scheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon,
                      size: 20, color: scheme.onSecondaryContainer),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleSmall),
                      Text(sub,
                          style: theme.textTheme.bodySmall!
                              .copyWith(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ]),
            ),
          const SizedBox(height: 14),

          // Plan toggle.
          Row(children: [
            _plan(theme, 'Monthly', '₹199', '/mo', !_yearly, () {
              Haptics.selection();
              setState(() => _yearly = false);
            }),
            const SizedBox(width: 10),
            _plan(theme, 'Yearly', '₹1,499', '/yr · save 37%', _yearly, () {
              Haptics.selection();
              setState(() => _yearly = true);
            }),
          ]),
          const SizedBox(height: 18),

          FilledButton.icon(
            onPressed: _busy || premium.active ? null : _subscribe,
            style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
            icon: Icon(premium.active
                ? Icons.check_rounded
                : Icons.workspace_premium_rounded),
            label: Text(premium.active
                ? 'You are Premium'
                : premium.trialUsed
                    ? 'Subscribe ${_yearly ? 'yearly' : 'monthly'} (store coming soon)'
                    : 'Start ${_yearly ? 'yearly' : 'monthly'} — 7 days free'),
          ),
          const SizedBox(height: 10),
          Center(
            child: TextButton(
              onPressed: () async {
                await ref.read(premiumProvider.notifier).refresh();
                if (context.mounted) {
                  showToast(context, 'Entitlement refreshed');
                }
              },
              child: const Text('Restore purchases'),
            ),
          ),
          Center(
            child: Text(
              premium.trialUsed && !premium.active
                  ? 'Store billing arrives with the Play Store release.'
                  : 'Cancel anytime · Trial converts only after store launch',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall!
                  .copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  Widget _plan(ThemeData theme, String label, String price, String sub,
      bool selected, VoidCallback onTap) {
    final scheme = theme.colorScheme;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected ? scheme.primaryContainer : null,
            borderRadius: BorderRadius.circular(16),
            border: selected
                ? null
                : Border.all(color: scheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: theme.textTheme.labelMedium!.copyWith(
                      color: selected
                          ? scheme.onPrimaryContainer
                          : scheme.onSurfaceVariant)),
              const SizedBox(height: 4),
              Text(price,
                  style: theme.textTheme.titleLarge!.copyWith(
                      color: selected
                          ? scheme.onPrimaryContainer
                          : scheme.onSurface)),
              Text(sub,
                  style: theme.textTheme.bodySmall!.copyWith(
                      color: selected
                          ? scheme.onPrimaryContainer.withValues(alpha: 0.8)
                          : scheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}
