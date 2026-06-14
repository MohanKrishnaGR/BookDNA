import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/haptics/haptics.dart';

/// 5-tab navigation shell with the scan FAB on Home and Library.
class MainShell extends StatelessWidget {
  const MainShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    final showFab = shell.currentIndex == 0 || shell.currentIndex == 1;
    return Scaffold(
      body: shell,
      floatingActionButton: showFab
          ? FloatingActionButton(
              onPressed: () => context.push('/scanner'),
              child: const Icon(Icons.qr_code_scanner_rounded),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) {
          if (i != shell.currentIndex) Haptics.selection();
          shell.goBranch(i, initialLocation: i == shell.currentIndex);
        },
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Home'),
          NavigationDestination(
              icon: Icon(Icons.shelves),
              selectedIcon: Icon(Icons.shelves),
              label: 'Library'),
          NavigationDestination(
              icon: Icon(Icons.insights_outlined),
              selectedIcon: Icon(Icons.insights_rounded),
              label: 'Insights'),
          NavigationDestination(
              icon: Icon(Icons.groups_outlined),
              selectedIcon: Icon(Icons.groups_rounded),
              label: 'Community'),
          NavigationDestination(
              icon: Icon(Icons.person_outline_rounded),
              selectedIcon: Icon(Icons.person_rounded),
              label: 'Profile'),
        ],
      ),
    );
  }
}
