import 'dart:async';
import 'package:flutter/foundation.dart';
import '../connection/connection_registry.dart';
import '../providers/multi_server_provider.dart';
import '../services/multi_server_manager.dart';
import 'active_profile_provider.dart';
import 'profile.dart';
import 'profile_connection_registry.dart';

typedef PlexHomePinPrompt = Future<String?> Function(Profile profile, {String? errorMessage});
typedef ShouldDeferInitialBind = FutureOr<bool> Function(Profile profile);

class ActiveProfileBinder {
  ActiveProfileBinder({
    required this.activeProfile,
    required this.connections,
    required this.profileConnections,
    required this.serverManager,
    required this.multiServerProvider,
    required this.pinPrompt,
    this.shouldDeferInitialBind,
    dynamic plexAuth,
  });

  final ActiveProfileProvider activeProfile;
  final ConnectionRegistry connections;
  final ProfileConnectionRegistry profileConnections;
  final MultiServerManager serverManager;
  final MultiServerProvider multiServerProvider;
  final PlexHomePinPrompt pinPrompt;
  final ShouldDeferInitialBind? shouldDeferInitialBind;

  bool get isSwitching => false;

  void markPlexHomePreVerified(String profileId) {}

  void markUserInitiatedActivation(String profileId) {}

  void start() {
    activeProfile.markBindingStarted();
    scheduleMicrotask(() {
      activeProfile.markBindingFinished(success: true);
    });
  }

  Future<void> rebindActive() async {
    activeProfile.markBindingStarted();
    activeProfile.markBindingFinished(success: true);
  }

  Future<void> rebindIfActive(String profileId) async {
    if (activeProfile.activeId == profileId) {
      await rebindActive();
    }
  }

  void dispose() {}
}
