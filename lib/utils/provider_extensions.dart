import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../media/media_item.dart';
import '../media/media_library.dart';
import '../providers/hidden_libraries_provider.dart';
import '../providers/user_profile_provider.dart';

extension ProviderExtensions on BuildContext {
  UserProfileProvider get userProfile => Provider.of<UserProfileProvider>(this, listen: false);

  HiddenLibrariesProvider get hiddenLibraries => Provider.of<HiddenLibrariesProvider>(this, listen: false);

  dynamic get profileSettings => null;

  dynamic getPlexClientForServer(dynamic serverId) => null;

  dynamic tryGetPlexClientForServer(dynamic serverId) => null;

  dynamic getPlexClientForLibrary(MediaLibrary library) => null;

  dynamic getPlexClientWithFallback(dynamic serverId) => null;

  dynamic tryGetMediaClientForServer(dynamic serverId) => null;

  dynamic getMediaClientForServer(dynamic serverId) => null;

  dynamic getMediaClientForLibrary(MediaLibrary library) => null;

  dynamic getMediaClientForItemOrNull(MediaItem item, {bool isOffline = false}) => null;

  dynamic getMediaClientWithFallback(dynamic serverId) => null;

  dynamic tryGetMediaClientWithFallback(dynamic serverId) => null;
}
