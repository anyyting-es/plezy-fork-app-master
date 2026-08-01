import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../connection/connection.dart';
import '../connection/connection_registry.dart';
import '../mixins/disposable_change_notifier_mixin.dart';
import '../services/storage_service.dart';
import '../utils/app_logger.dart';
import 'profile.dart';
import 'profile_merge.dart';
import 'profile_registry.dart';

/// Holds the currently active [Profile] and a merged list of all available
/// profiles — local rows from [ProfileRegistry].
class ActiveProfileProvider extends ChangeNotifier with DisposableChangeNotifierMixin {
  ActiveProfileProvider({
    required this._registry,
    required this._connections,
    StorageService? storage,
  }) : _storage = storage;

  final ProfileRegistry _registry;
  final ConnectionRegistry _connections;
  StorageService? _storage;

  Profile? _active;
  List<Profile> _profiles = const [];
  List<Profile> _localProfiles = const [];
  final Map<String, List<dynamic>> _plexHomeUsers = const {};
  Map<String, Connection> _connectionsById = const {};

  StreamSubscription<List<Profile>>? _localSub;
  StreamSubscription<List<Connection>>? _connSub;
  Future<void>? _initializeFuture;
  bool _initialized = false;

  bool _isBinding = false;
  bool _lastBindingSucceeded = true;
  final List<Completer<bool>> _bindingSettleWaiters = [];

  Profile? get active => _active;
  String? get activeId => _active?.id;
  List<Profile> get profiles => _profiles;
  bool get hasMultipleProfiles => _profiles.length > 1;
  bool get isInitialized => _initialized;

  /// True while [ActiveProfileBinder] is wiring servers/tokens for the
  /// active profile. The picker reads this so it can stay open (and stay
  /// behind any PIN dialog the binder pops) until binding settles.
  bool get isBinding => _isBinding;

  /// Outcome of the most recent settled bind. False after a PIN cancel,
  /// failed user switch, or any error inside the binder.
  bool get lastBindingSucceeded => _lastBindingSucceeded;

  /// Called by [ActiveProfileBinder] at the start of a rebind cycle.
  /// Re-entrant — no-ops if already in [isBinding].
  void markBindingStarted() {
    if (_isBinding) return;
    _isBinding = true;
    _lastBindingSucceeded = true;
    safeNotifyListeners();
  }

  /// Called by [ActiveProfileBinder] when the rebind settles. [success]
  /// means the active profile was applied successfully. A local profile with
  /// no connections is successful and intentionally exposes no servers.
  void markBindingFinished({required bool success}) {
    if (!_isBinding && _lastBindingSucceeded == success) return;
    _isBinding = false;
    _lastBindingSucceeded = success;
    safeNotifyListeners();
  }

  /// Resolves once the binder reports done. Returns immediately when no
  /// rebind is in flight. The boolean reflects [lastBindingSucceeded] at
  /// the moment binding settles, so the picker can decide whether to
  /// dismiss or surface an error.
  Future<bool> awaitBindingSettle() {
    if (!_isBinding) return Future.value(_lastBindingSucceeded);
    final completer = Completer<bool>();
    _bindingSettleWaiters.add(completer);
    void listener() {
      if (_isBinding) return;
      removeListener(listener);
      if (_bindingSettleWaiters.remove(completer) && !completer.isCompleted) {
        completer.complete(_lastBindingSucceeded);
      }
    }

    addListener(listener);
    return completer.future;
  }

  Future<void> initialize() {
    if (_initialized) return Future.value();
    final pending = _initializeFuture;
    if (pending != null) return pending;

    final future = _initialize().catchError((Object error, StackTrace stackTrace) {
      _initializeFuture = null;
      Error.throwWithStackTrace(error, stackTrace);
    });
    _initializeFuture = future;
    return future;
  }

  /// Re-read connections, local profiles, and active id.
  Future<void> reloadFromStorage() async {
    await initialize();
    await _reloadSnapshot();
    safeNotifyListeners();
  }

  Future<void> _initialize() async {
    await _reloadSnapshot();

    _localSub = _registry.watchProfiles().listen((list) {
      if (listEquals(list, _localProfiles)) return;
      _localProfiles = list;
      _recomputeProfiles();
      _resolveActive();
      safeNotifyListeners();
    });
    _connSub = _connections.watchConnections().listen((list) {
      final byId = {for (final c in list) c.id: c};
      if (_sameConnections(byId, _connectionsById)) return;
      _connectionsById = byId;
      _recomputeProfiles();
      _resolveActive();
      safeNotifyListeners();
    });

    _initialized = true;
    safeNotifyListeners();
  }

  Future<void> _reloadSnapshot() async {
    _storage ??= await StorageService.getInstance();

    _localProfiles = await _registry.list();
    final initialConns = await _connections.list();
    _connectionsById = {for (final c in initialConns) c.id: c};
    _recomputeProfiles();
    _resolveActive();
  }

  /// [Connection] has no value equality; its persisted config is the
  /// cheapest faithful comparison key for the handful of rows involved.
  static bool _sameConnections(Map<String, Connection> a, Map<String, Connection> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      final other = b[entry.key];
      if (other == null) return false;
      if (identical(entry.value, other)) continue;
      if (jsonEncode(entry.value.toConfigJson()) != jsonEncode(other.toConfigJson())) return false;
    }
    return true;
  }

  void _recomputeProfiles() {
    _profiles = mergeLocalWithPlexHome(
      locals: _localProfiles,
      plexHomeByConnectionId: _plexHomeUsers,
      connectionsById: _connectionsById,
      storage: _storage,
    );
  }

  void _resolveActive() {
    if (_profiles.isEmpty) {
      _active = null;
      return;
    }
    final id = _storage?.getActiveProfileId();
    if (id == null) {
      _active = null;
      return;
    }
    for (final p in _profiles) {
      if (p.id == id) {
        _active = p;
        return;
      }
    }
    _active = null;
  }

  /// Activate [profile]. PIN-protected local profiles must supply a matching PIN.
  Future<bool> activate(Profile profile, {String? pin}) async {
    if (profile.isLocal && profile.isPinProtected) {
      final hash = profile.pinHash;
      if (pin == null || hash == null || !verifyPin(pin, hash)) {
        return false;
      }
    }
    final storage = _storage;
    if (storage == null) return false;
    await storage.setActiveProfileId(profile.id);
    final now = DateTime.now();
    await storage.markProfileUsed(profile.id, now);
    final activated = profile.copyWith(lastUsedAt: now);
    _active = activated;
    _profiles = sortProfilesByLastUsed([for (final p in _profiles) p.id == profile.id ? activated : p]);
    safeNotifyListeners();
    appLogger.i('ActiveProfileProvider: activated ${profile.displayName} (${profile.id})');
    if (profile.isLocal) {
      unawaited(
        _registry.markUsed(profile.id, now).catchError((Object e, StackTrace s) {
          appLogger.w('markUsed failed for ${profile.id}', error: e, stackTrace: s);
        }),
      );
    }
    return true;
  }

  /// Clear the selected profile in both storage and memory so the picker
  /// can force an explicit choice on the next screen.
  Future<void> clearActiveProfile() async {
    final storage = _storage ??= await StorageService.getInstance();
    await storage.clearActiveProfileId();
    _active = null;
    safeNotifyListeners();
  }

  @visibleForTesting
  Future<void> resetForTesting() async {
    await _localSub?.cancel();
    await _connSub?.cancel();
    _localSub = null;
    _connSub = null;
    _profiles = const [];
    _localProfiles = const [];
    _connectionsById = const {};
    _active = null;
    _initializeFuture = null;
    _initialized = false;
    _isBinding = false;
    _lastBindingSucceeded = true;
    for (final c in _bindingSettleWaiters) {
      if (!c.isCompleted) c.complete(_lastBindingSucceeded);
    }
    _bindingSettleWaiters.clear();
  }

  @override
  void dispose() {
    for (final c in _bindingSettleWaiters) {
      if (!c.isCompleted) c.complete(_lastBindingSucceeded);
    }
    _bindingSettleWaiters.clear();
    _initializeFuture = null;
    _localSub?.cancel();
    _connSub?.cancel();
    super.dispose();
  }
}
