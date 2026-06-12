import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../core/sync/sync_providers.dart';
import 'router.dart';
import 'theme/app_theme.dart';

class BookDnaApp extends ConsumerWidget {
  const BookDnaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    // Arm the sync orchestrator (auth/connectivity/mutation triggers).
    ref.watch(syncControllerProvider);
    return MaterialApp.router(
      title: 'BookDNA',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: mode,
      routerConfig: router,
    );
  }
}
