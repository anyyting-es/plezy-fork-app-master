import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../mixins/disposable_change_notifier_mixin.dart';
import '../services/offline_mode_source.dart';

enum OfflineModeReason {
  online,
  noNetworkConnection,
  waitingForServerStatus,
  noKnownVisibleServers,
  onlyAuthErrorServers,
  noServerConnection,
}

/// Tracks offline mode status based on network connectivity and server reachability.
class OfflineModeProvider extends ChangeNotifier with DisposableChangeNotifierMixin implements OfflineModeSource {
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  bool _hasNetworkConnection = true;
  bool _lastOfflineState = false;
  bool _isInitialized = false;

  List<ConnectivityResult> _lastConnectivityResults = const [];
  bool _lastWifiOrEthernetState = false;

  /// Whether the current connection is WiFi or Ethernet (unmetered-ish).
  bool get hasWifiOrEthernet =>
      _lastConnectivityResults.contains(ConnectivityResult.wifi) ||
      _lastConnectivityResults.contains(ConnectivityResult.ethernet);

  OfflineModeProvider(dynamic serverManager, {dynamic multiServerProvider}) {
    _lastOfflineState = isOffline;
  }

  @override
  bool get isOffline => offlineReason == OfflineModeReason.noNetworkConnection;

  OfflineModeReason get offlineReason {
    if (!_hasNetworkConnection) return OfflineModeReason.noNetworkConnection;
    return OfflineModeReason.online;
  }

  bool get hasNetworkConnection => _hasNetworkConnection;

  bool get hasServerConnection => _hasNetworkConnection;

  void updateMultiServerProvider(dynamic provider) {}

  Future<void> _updateConnectionFlags() async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity().timeout(
        const Duration(seconds: 3),
        onTimeout: () => [ConnectivityResult.other],
      );
      _lastConnectivityResults = connectivityResult;
      _lastWifiOrEthernetState = hasWifiOrEthernet;
      _hasNetworkConnection = !connectivityResult.contains(ConnectivityResult.none);
    } catch (e) {
      _hasNetworkConnection = true;
    }
  }

  void _notifyIfOfflineChanged() {
    final offline = isOffline;
    if (_lastOfflineState == offline) return;
    _lastOfflineState = offline;
    safeNotifyListeners();
  }

  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;

    await _updateConnectionFlags();

    runZonedGuarded(
      () {
        _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
          (results) {
            _lastConnectivityResults = results;
            _hasNetworkConnection = !results.contains(ConnectivityResult.none);
            final wifiNow = hasWifiOrEthernet;
            if (wifiNow != _lastWifiOrEthernetState) {
              _lastWifiOrEthernetState = wifiNow;
              _lastOfflineState = isOffline;
              safeNotifyListeners();
            } else {
              _notifyIfOfflineChanged();
            }
          },
          onError: (e) {
            _hasNetworkConnection = true;
          },
        );
      },
      (error, stack) {
        _hasNetworkConnection = true;
      },
    );

    _lastOfflineState = isOffline;
    safeNotifyListeners();
  }

  Future<void> refresh() async {
    await _updateConnectionFlags();
    _lastOfflineState = isOffline;
    safeNotifyListeners();
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }
}
