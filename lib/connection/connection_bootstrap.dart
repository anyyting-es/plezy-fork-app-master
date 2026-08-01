import '../profiles/profile_registry.dart';
import '../services/storage_service.dart';
import 'connection_registry.dart';

class ConnectionBootstrap {
  final StorageService storage;
  final ConnectionRegistry connectionRegistry;
  final ProfileRegistry profileRegistry;

  ConnectionBootstrap({
    required this.storage,
    required this.connectionRegistry,
    required this.profileRegistry,
    dynamic serverRegistry,
  });

  Future<void> run() async {
    // No-op / stubbed migration
  }
}
