import 'dart:async';
import 'package:flutter/foundation.dart';

import '../connection/connection_registry.dart';
import '../models/companion_remote/remote_command.dart';
import '../models/companion_remote/remote_session.dart';
import '../profiles/active_profile_provider.dart';
import '../profiles/profile.dart';
import '../profiles/profile_connection_registry.dart';
import '../mixins/disposable_change_notifier_mixin.dart';

class CompanionRemoteProvider with ChangeNotifier, DisposableChangeNotifierMixin {
  CompanionRemoteProvider();

  bool get isInSession => false;
  bool get isHost => false;
  bool get isRemote => false;
  bool get isConnected => false;
  RemoteSession? get session => null;
  RemoteSessionStatus get status => RemoteSessionStatus.disconnected;
  dynamic get connectedDevice => null;
  bool get isPlayerActive => false;
  bool get isHostServerRunning => false;
  int get reconnectAttempts => 0;

  dynamic onCommandReceived;

  void bindProfileServices({
    required ConnectionRegistry connections,
    required ActiveProfileProvider activeProfile,
    required ProfileConnectionRegistry profileConnections,
    dynamic plexHome,
  }) {}

  Future<bool> ensureCryptoReady({
    required Profile profile,
    required ConnectionRegistry connections,
    required ProfileConnectionRegistry profileConnections,
    dynamic plexHome,
  }) async {
    return true;
  }

  Future<void> resetForLogout() async {}

  Future<void> startHostServer() async {}

  Future<void> stopHostServer() async {}

  void stopDiscovery() {}

  Future<void> connectToDiscoveredHost(dynamic host) async {}

  Future<void> connectToManualHost(String hostAddress) async {}

  void sendCommand(RemoteCommandType type, {Map<String, dynamic>? data}) {}

  void retryReconnectNow() {}

  void cancelReconnect() {}

  Future<void> leaveSession() async {}

  @override
  void dispose() {
    super.dispose();
  }
}
