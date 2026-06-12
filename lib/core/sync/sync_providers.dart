import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../supabase/client.dart';
import 'sync_engine.dart';
import 'sync_remote.dart';

final syncEngineProvider = Provider<SyncEngine?>((ref) {
  if (!supabaseConfigured) return null;
  return SyncEngine(ref.watch(databaseProvider), SupabaseRemote(supabase));
});

enum SyncPhase { disabled, idle, syncing, error }

class SyncStatus {
  const SyncStatus(this.phase, {this.lastSync, this.message});

  final SyncPhase phase;
  final DateTime? lastSync;
  final String? message;
}

/// Orchestrates when to sync: auth changes, connectivity regained,
/// local mutations (debounced), and explicit "Sync now".
final syncControllerProvider =
    NotifierProvider<SyncController, SyncStatus>(SyncController.new);

class SyncController extends Notifier<SyncStatus> {
  Timer? _debounce;
  StreamSubscription? _connectivitySub;
  StreamSubscription? _authSub;
  StreamSubscription? _mutationSub;

  @override
  SyncStatus build() {
    final engine = ref.watch(syncEngineProvider);
    if (engine == null) return const SyncStatus(SyncPhase.disabled);

    final db = ref.read(databaseProvider);

    _authSub = supabase.auth.onAuthStateChange.listen((change) async {
      final user = change.session?.user;
      if (user == null) return;
      // First sign-in for this identity on this device: adopt local data.
      final adoptedFor = await db.getPref('syncUserId');
      if (adoptedFor != user.id) {
        await engine.adoptLocalData();
        await db.setPref('syncUserId', user.id);
      }
      unawaited(syncNow());
    });

    _connectivitySub =
        Connectivity().onConnectivityChanged.listen((results) {
      if (!results.contains(ConnectivityResult.none)) {
        _scheduleSync();
      }
    });

    // Any local table change → debounced push/pull.
    _mutationSub = db.tableUpdates().listen((_) => _scheduleSync());

    ref.onDispose(() {
      _debounce?.cancel();
      _connectivitySub?.cancel();
      _authSub?.cancel();
      _mutationSub?.cancel();
    });

    return const SyncStatus(SyncPhase.idle);
  }

  void _scheduleSync() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 5), () => syncNow());
  }

  Future<void> syncNow() async {
    final engine = ref.read(syncEngineProvider);
    if (engine == null || !engine.canSync) return;
    if (state.phase == SyncPhase.syncing) return;
    state = SyncStatus(SyncPhase.syncing, lastSync: state.lastSync);
    try {
      await engine.syncNow();
      state = SyncStatus(SyncPhase.idle, lastSync: DateTime.now());
    } catch (e) {
      state = SyncStatus(SyncPhase.error,
          lastSync: state.lastSync, message: '$e');
    }
  }
}
