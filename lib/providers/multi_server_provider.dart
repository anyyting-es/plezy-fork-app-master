import 'dart:async';
import 'package:flutter/foundation.dart';
import '../mixins/disposable_change_notifier_mixin.dart';
import '../services/data_aggregation_service.dart';
import '../services/multi_server_manager.dart';

class LiveTvServerInfo {
  final String serverId;
  final String dvrKey;
  final String? lineup;
  final List<dynamic> dvrs;

  LiveTvServerInfo({required this.serverId, required this.dvrKey, this.lineup, this.dvrs = const []});
}

class MultiServerProvider extends ChangeNotifier with DisposableChangeNotifierMixin {
  final MultiServerManager _serverManager;
  final DataAggregationService _aggregationService;

  MultiServerProvider(this._serverManager, this._aggregationService);

  MultiServerManager get serverManager => _serverManager;
  DataAggregationService get aggregationService => _aggregationService;

  bool get hasLiveTv => false;
  List<LiveTvServerInfo> get liveTvServers => const [];
  Set<String> get authErrorServers => const {};
  bool get hasConnectedServers => true;
  Set<String> get authErrorServerIds => const {};
  List<String> get expectedServerIds => const [];
  int get totalServerCount => 0;

  void addOnlineServersListener(void Function(Set<String> onlineServerIds) listener) {}
  void removeOnlineServersListener(void Function(Set<String> onlineServerIds) listener) {}

  int get onlineServersListenerCount => 0;

  bool get hasExplicitVisibleServerFilter => false;

  void setVisibleServerIds(Set<String>? ids) {}

  void setExpectedVisibleServerIds(Set<String>? ids) {}

  bool isServerExpected(String serverId) => false;

  List<String> get serverIds => const [];
  List<String> get onlineServerIds => const [];
  List<String> get offlineServerIds => const [];

  bool isServerOnline(String serverId) => false;
  bool isClientOnline(String serverId, {String? clientScopeId}) => false;

  dynamic getClient(String serverId) => null;
  dynamic getClientForServer(dynamic serverId) => null;

  dynamic resolveDownloadClient(String serverId, {String? clientScopeId}) => null;

  void removeServer(String serverId) {}

  Future<void> reconnectOfflineServers({bool forceRediscovery = false}) async {}

  Future<void> checkServerHealth() async {}

  @override
  void dispose() {
    super.dispose();
  }
}
