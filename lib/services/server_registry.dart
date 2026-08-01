import 'storage_service.dart';

class ServerRegistry {
  final StorageService _storage;

  ServerRegistry(this._storage);

  Future<List<dynamic>> getServers() async {
    return const [];
  }
}
