import 'dart:async';
import 'package:flutter/foundation.dart';
import '../mixins/disposable_change_notifier_mixin.dart';

class UserProfileProvider extends ChangeNotifier with DisposableChangeNotifierMixin {
  UserProfileProvider({dynamic storageService});

  dynamic get profileSettings => null;

  void attach({
    required dynamic connections,
    required dynamic activeProfile,
    required dynamic profileConnections,
    dynamic serverManager,
  }) {}

  Future<void> initialize() async {}
  Future<void> refreshProfileSettings() async {}
}
