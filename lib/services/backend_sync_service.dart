import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../utils/app_logger.dart';
import 'settings_service.dart';
import 'torrent_engine_service.dart';

class BackendSyncService {
  static bool _isSyncingSettings = false;

  /// Returns true if settings changes should be automatically pushed to the backend.
  static bool get shouldAutoPushSettings {
    final baseUrl = TorrentEngineService.instance.baseUrl;
    return baseUrl.isNotEmpty && !_isSyncingSettings;
  }

  /// Initialize listeners for settings to pull on startup or connection change
  static void initialize() {
    // Perform startup pull
    unawaited(pullSettings());

    // Listen to remote settings changes to pull/refresh if settings modified
    SettingsService.instance.listenable(SettingsService.useRemoteBackend).addListener(() {
      unawaited(pullSettings());
    });
    SettingsService.instance.listenable(SettingsService.remoteBackendUrl).addListener(() {
      unawaited(pullSettings());
    });
    SettingsService.instance.listenable(SettingsService.remoteBackendPin).addListener(() {
      unawaited(pullSettings());
    });
  }

  /// Push all user settings and tracker credentials to the backend
  static Future<void> pushSettings() async {
    final baseUrl = TorrentEngineService.instance.baseUrl;
    if (baseUrl.isEmpty) return;

    final settings = SettingsService.instance;
    final prefs = settings.prefs;
    final keys = prefs.keys;

    final Map<String, dynamic> data = {};
    for (final key in keys) {
      // Exclude machine-specific and connection-specific settings to prevent sync loops/overwrite
      if (key == 'use_remote_backend' ||
          key == 'remote_backend_url' ||
          key == 'remote_backend_pin' ||
          key == 'backend_pin' ||
          key == 'backend_working_location' ||
          key == 'allow_lan_connections' ||
          key == 'aniting_port') {
        continue;
      }
      final val = prefs.get(key);
      if (val != null) {
        data[key] = val;
      }
    }

    try {
      await http.post(
        Uri.parse('$baseUrl/userdata/settings'),
        headers: {
          'Content-Type': 'application/json',
          ...TorrentEngineService.instance.getHeaders(),
        },
        body: jsonEncode(data),
      ).timeout(const Duration(seconds: 3));
      appLogger.d('BackendSync: successfully pushed settings to backend');
    } catch (e) {
      appLogger.w('BackendSync: failed to push settings to backend: $e');
    }
  }

  /// Pull user settings and tracker credentials from the backend and apply them locally
  static Future<void> pullSettings() async {
    final baseUrl = TorrentEngineService.instance.baseUrl;
    if (baseUrl.isEmpty) return;

    try {
      final res = await http.get(
        Uri.parse('$baseUrl/userdata/settings'),
        headers: TorrentEngineService.instance.getHeaders(),
      ).timeout(const Duration(seconds: 3));

      if (res.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(res.body);
        final settings = SettingsService.instance;
        final prefs = settings.prefs;

        _isSyncingSettings = true;
        try {
          for (final entry in data.entries) {
            final key = entry.key;
            final val = entry.value;
            if (val is bool) {
              await prefs.setBool(key, val);
            } else if (val is int) {
              await prefs.setInt(key, val);
            } else if (val is double) {
              await prefs.setDouble(key, val);
            } else if (val is String) {
              await prefs.setString(key, val);
            } else if (val is List) {
              await prefs.setStringList(key, val.cast<String>());
            }
          }
          settings.refreshActiveListenables();
          appLogger.i('BackendSync: successfully pulled and applied settings from backend');
        } finally {
          _isSyncingSettings = false;
        }
      }
    } catch (e) {
      appLogger.w('BackendSync: failed to pull settings from backend: $e');
    }
  }

  /// Save playback position for a media item
  static Future<void> saveProgress(String syncKey, int positionMs, int durationMs, {double threshold = 0.9}) async {
    final baseUrl = TorrentEngineService.instance.baseUrl;
    if (baseUrl.isEmpty) return;

    final isCompleted = positionMs / durationMs >= threshold;

    try {
      if (isCompleted) {
        await http.delete(
          Uri.parse('$baseUrl/userdata/progress_$syncKey'),
          headers: TorrentEngineService.instance.getHeaders(),
        ).timeout(const Duration(seconds: 2));
        appLogger.d('BackendSync: deleted progress for completed item $syncKey');
      } else {
        await http.post(
          Uri.parse('$baseUrl/userdata/progress_$syncKey'),
          headers: {
            'Content-Type': 'application/json',
            ...TorrentEngineService.instance.getHeaders(),
          },
          body: jsonEncode({
            'viewOffsetMs': positionMs,
            'durationMs': durationMs,
            'updatedAt': DateTime.now().millisecondsSinceEpoch,
          }),
        ).timeout(const Duration(seconds: 2));
      }
    } catch (e) {
      appLogger.w('BackendSync: failed to save playback progress: $e');
    }
  }

  /// Get playback position for a media item
  static Future<Duration?> getProgress(String syncKey) async {
    final baseUrl = TorrentEngineService.instance.baseUrl;
    if (baseUrl.isEmpty) return null;

    try {
      final res = await http.get(
        Uri.parse('$baseUrl/userdata/progress_$syncKey'),
        headers: TorrentEngineService.instance.getHeaders(),
      ).timeout(const Duration(seconds: 2));

      if (res.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(res.body);
        final offset = data['viewOffsetMs'] as int?;
        if (offset != null && offset > 0) {
          return Duration(milliseconds: offset);
        }
      }
    } catch (_) {
      // Fail silently
    }
    return null;
  }
}
