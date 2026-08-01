import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../connection/connection.dart';
import '../connection/connection_registry.dart';
import '../i18n/strings.g.dart';
import '../screens/profile/pin_entry_dialog.dart';
import '../utils/snackbar_helper.dart';
import 'active_profile_binder.dart';
import 'active_profile_provider.dart';
import 'profile.dart';
import 'profile_connection_registry.dart';

/// How a UI-driven activation attempt ended. `cancelled` (user backed out
/// of a PIN dialog) is not an error and must not surface a failure message.
enum ProfileActivationOutcome { activated, cancelled, failed }

/// Activate [profile] from a UI surface, prompting for the PIN when the
/// profile is protected. Loops on wrong-PIN entries until the user submits
/// the right PIN or backs out.
Future<ProfileActivationOutcome> activateProfileWithPin(BuildContext context, Profile profile) async {
  final active = context.read<ActiveProfileProvider>();
  final binder = context.read<ActiveProfileBinder>();

  if (!profile.isPinProtected) {
    binder.markUserInitiatedActivation(profile.id);
    return await active.activate(profile) ? ProfileActivationOutcome.activated : ProfileActivationOutcome.failed;
  }

  String? errorMessage;
  while (true) {
    if (!context.mounted) return ProfileActivationOutcome.cancelled;
    final pin = await showPinEntryDialog(context, profile.displayName, errorMessage: errorMessage);
    if (pin == null) return ProfileActivationOutcome.cancelled; // user backed out
    final hash = profile.pinHash;
    if (hash != null && verifyPin(pin, hash)) {
      binder.markUserInitiatedActivation(profile.id);
      return await active.activate(profile, pin: pin)
          ? ProfileActivationOutcome.activated
          : ProfileActivationOutcome.failed;
    }
    errorMessage = t.profiles.incorrectPinTryAgain;
  }
}

/// Activate [profile] from a UI surface, then wait until the active profile's
/// server/token binding has settled. Shows the standard switch failure message
/// for activation and binding failures — but not for a PIN-dialog cancel,
/// which is the user changing their mind, not an error.
Future<bool> switchProfileFromUi(BuildContext context, Profile profile) async {
  final activeProvider = context.read<ActiveProfileProvider>();
  final outcome = await activateProfileWithPin(context, profile);
  if (!context.mounted) return false;
  switch (outcome) {
    case ProfileActivationOutcome.cancelled:
      return false;
    case ProfileActivationOutcome.failed:
      showErrorSnackBar(context, t.errors.failedToSwitchProfile(displayName: profile.displayName));
      return false;
    case ProfileActivationOutcome.activated:
      break;
  }

  final bound = await activeProvider.awaitBindingSettle();
  if (!context.mounted) return false;
  if (!bound) {
    showErrorSnackBar(context, t.errors.failedToSwitchProfile(displayName: profile.displayName));
    return false;
  }
  return true;
}

/// Verify [pin] against [profile]'s stored PIN hash *without* activating it.
/// Used by the borrow flow: we need to confirm the user knows the source
/// profile's PIN before letting them copy a connection out of it.
bool verifyProfilePin(Profile profile, String pin) {
  if (!profile.isLocal) return false;
  final hash = profile.pinHash;
  if (hash == null || hash.isEmpty) return true;
  return verifyPin(pin, hash);
}
