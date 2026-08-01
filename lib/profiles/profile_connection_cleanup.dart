import '../connection/connection.dart';
import '../connection/connection_registry.dart';
import '../services/storage_service.dart';
import '../services/multi_server_manager.dart';
import 'profile.dart';
import 'profile_connection_registry.dart';
import 'profile_registry.dart';

Future<void> removeProfileConnectionAndCleanup({
  required String profileId,
  required Connection connection,
  required ProfileConnectionRegistry profileConnections,
  required ConnectionRegistry connections,
  required StorageService storage,
  MultiServerManager? serverManager,
}) async {
  await profileConnections.remove(profileId, connection.id);
}

Future<void> removeAllProfileConnectionsAndCleanup({
  required String profileId,
  required ProfileConnectionRegistry profileConnections,
  required ConnectionRegistry connections,
  required StorageService storage,
  MultiServerManager? serverManager,
}) async {
  final rows = await profileConnections.listForProfile(profileId);
  for (final row in rows) {
    await profileConnections.remove(profileId, row.connectionId);
  }
}

typedef PlexAccountRemoval = ({
  Set<String> removedVirtualProfileIds,
  Set<String> borrowerProfileIds,
});

Future<PlexAccountRemoval> removePlexAccountConnectionAndCleanup({
  required PlexAccountConnection account,
  required ProfileConnectionRegistry profileConnections,
  required ConnectionRegistry connections,
  required StorageService storage,
  MultiServerManager? serverManager,
}) async {
  await connections.remove(account.id);
  return (removedVirtualProfileIds: const <String>{}, borrowerProfileIds: const <String>{});
}

enum PostRemovalRoute { signedOut, staySignedIn }

Future<({PostRemovalRoute route, List<Profile> profiles})> resolvePostRemovalState({
  required ProfileRegistry profileRegistry,
  required ProfileConnectionRegistry profileConnections,
  required ConnectionRegistry connections,
  required Map<String, List<dynamic>> plexHomeUsers,
  required StorageService storage,
  MultiServerManager? serverManager,
}) async {
  final locals = await profileRegistry.list();
  if (locals.isEmpty) return (route: PostRemovalRoute.signedOut, profiles: const <Profile>[]);
  return (route: PostRemovalRoute.staySignedIn, profiles: locals);
}

Future<int> pruneUnreferencedJellyfinConnections({
  required ProfileConnectionRegistry profileConnections,
  required ConnectionRegistry connections,
  required StorageService storage,
  MultiServerManager? serverManager,
}) async {
  return 0;
}
