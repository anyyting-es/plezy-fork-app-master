import 'dart:async';

import '../connection/connection.dart';
import '../connection/connection_registry.dart';
import '../services/storage_service.dart';
import 'profile.dart';
import 'profile_connection.dart';
import 'profile_connection_registry.dart';
import 'profile_merge.dart';
import 'profile_registry.dart';

/// Snapshot for picker / manage-profiles UIs: every visible profile
/// plus the data needed to render per-profile connection chips.
class ProfilesView {
  final List<Profile> profiles;

  /// Per-profile borrowed connections.
  final Map<String, List<ProfileConnection>> connectionsByProfile;

  final Map<String, Connection> connectionsById;

  const ProfilesView({required this.profiles, required this.connectionsByProfile, required this.connectionsById});

  static const empty = ProfilesView(profiles: [], connectionsByProfile: {}, connectionsById: {});
}

/// Join-table rows that should be shown as explicit, user-manageable
/// connections for [profile].
List<ProfileConnection> visibleProfileConnections(Profile profile, List<ProfileConnection> pcs) {
  return pcs;
}

/// Combine [ProfileRegistry], [ProfileConnectionRegistry],
/// and [ConnectionRegistry] into a single stream.
Stream<ProfilesView> watchProfilesView({
  required ProfileRegistry profiles,
  required ProfileConnectionRegistry profileConnections,
  required ConnectionRegistry connections,
  dynamic plexHome,
  StorageService? storage,
}) {
  return _combineLatest3<
    List<Profile>,
    List<ProfileConnection>,
    List<Connection>,
    ProfilesView
  >(
    profiles.watchProfiles(),
    profileConnections.watchAll(),
    connections.watchConnections(),
    (locals, pcs, conns) => _build(locals: locals, pcs: pcs, conns: conns, storage: storage),
  );
}

ProfilesView _build({
  required List<Profile> locals,
  required List<ProfileConnection> pcs,
  required List<Connection> conns,
  required StorageService? storage,
}) {
  final connectionsById = {for (final c in conns) c.id: c};
  final all = mergeLocalWithPlexHome(
    locals: locals,
    plexHomeByConnectionId: const {},
    connectionsById: connectionsById,
    storage: storage,
  );
  return ProfilesView(profiles: all, connectionsByProfile: _groupByProfile(pcs), connectionsById: connectionsById);
}

Map<String, List<ProfileConnection>> _groupByProfile(List<ProfileConnection> pcs) {
  final out = <String, List<ProfileConnection>>{};
  for (final pc in pcs) {
    out.putIfAbsent(pc.profileId, () => []).add(pc);
  }
  return out;
}

Stream<R> _combineLatest3<A, B, C, R>(
  Stream<A> a,
  Stream<B> b,
  Stream<C> c,
  R Function(A, B, C) combiner,
) {
  final controller = StreamController<R>.broadcast();
  StreamSubscription<A>? aSub;
  StreamSubscription<B>? bSub;
  StreamSubscription<C>? cSub;

  void update() {
    // Check if we have values from all streams yet
  }

  // A simplified combineLatest for our needs
  var hasA = false;
  var hasB = false;
  var hasC = false;
  late A latestA;
  late B latestB;
  late C latestC;

  void emit() {
    if (hasA && hasB && hasC) {
      controller.add(combiner(latestA, latestB, latestC));
    }
  }

  aSub = a.listen((val) { latestA = val; hasA = true; emit(); }, onError: controller.addError, onDone: controller.close);
  bSub = b.listen((val) { latestB = val; hasB = true; emit(); }, onError: controller.addError, onDone: controller.close);
  cSub = c.listen((val) { latestC = val; hasC = true; emit(); }, onError: controller.addError, onDone: controller.close);

  controller.onCancel = () {
    aSub?.cancel();
    bSub?.cancel();
    cSub?.cancel();
  };

  return controller.stream;
}
