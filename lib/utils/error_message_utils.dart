import '../i18n/strings.g.dart';
import 'app_logger.dart';

/// Shared helpers for translating network errors into user-friendly messages.
String mapHttpErrorToMessage(dynamic error, {required String context}) {
  final errStr = error.toString().toLowerCase();
  if (errStr.contains('timeout')) {
    return t.errors.connectionTimeout(context: context);
  } else if (errStr.contains('socket') || errStr.contains('failed to connect')) {
    return t.errors.connectionFailed;
  } else {
    appLogger.e('Error loading $context', error: error);
    final msg = error.toString();
    return t.errors.failedToLoad(context: context, error: msg);
  }
}

/// Generic fallback for unexpected errors.
String mapUnexpectedErrorToMessage(dynamic error, {required String context}) {
  appLogger.e('Unexpected error in $context', error: error);
  return t.errors.failedToLoad(context: context, error: error.toString());
}
