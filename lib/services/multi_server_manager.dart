import 'dart:async';
import '../media/ids.dart';
import '../media/media_server_client.dart';

class MultiServerManager {
  MultiServerManager();

  Map<String, MediaServerClient> get onlineClients => const {};

  dynamic onJellyfinConnectionUpdated;

  List<String> get serverIds => const [];
  List<String> get onlineServerIds => const [];
  List<String> get offlineServerIds => const [];

  MediaServerClient? getClient(ServerId serverId) => null;

  Set<String>? get visibleServerIds => null;
  void setVisibleServerIds(Set<String>? ids) {}

  bool isServerVisible(ServerId serverId) => true;

  MediaServerClient? resolveDownloadClient(ServerId serverId, {String? clientScopeId}) => null;

  dynamic getPlexClient(ServerId serverId) => null;

  dynamic getJellyfinClientByCompoundId(String compoundId) => null;

  bool isOwnerOrAdmin(ServerId serverId) => false;

  bool isServerOnline(ServerId serverId) => false;
  bool isClientOnline(ServerId serverId, {String? clientScopeId}) => false;

  final _statusController = StreamController<Map<String, bool>>.broadcast();
  Stream<Map<String, bool>> get statusStream => _statusController.stream;

  final _connectProgressController = StreamController<({String serverId, bool online})>.broadcast();
  Stream<({String serverId, bool online})> get connectProgressStream => _connectProgressController.stream;

  Set<String> get authErrorServerIds => const {};

  Future<void> checkServerHealth() async {}

  Future<void> reconnectOfflineServers({bool forceRediscovery = false}) async {}

  void removeServer(ServerId serverId) {}

  void removePlexAccount(dynamic connection) {}

  void removeJellyfinConnection(dynamic connection) {}

  void disconnectAll() {}

  Future<void> disconnectAllGracefully({Duration drainTimeout = const Duration(seconds: 5)}) async {}

  void dispose() {
    _statusController.close();
    _connectProgressController.close();
  }
}
