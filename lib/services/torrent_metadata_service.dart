import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:http/http.dart' as http;
import '../media/media_item.dart';
import '../utils/app_logger.dart';
import 'torrent_engine_service.dart';

class TorrentMetadataService {
  static final instance = TorrentMetadataService._();
  TorrentMetadataService._();

  final Map<String, MediaItem> _cache = {};
  File? _metadataFile;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      // 1. Try to load from backend first
      final baseUrl = TorrentEngineService.instance.baseUrl;
      if (baseUrl.isNotEmpty) {
        try {
          final res = await http.get(
            Uri.parse('$baseUrl/metadata'),
            headers: TorrentEngineService.instance.getHeaders(),
          ).timeout(const Duration(seconds: 4));
          if (res.statusCode == 200) {
            final Map<String, dynamic> decoded = jsonDecode(res.body);
            decoded.forEach((key, value) {
              try {
                _cache[key.toLowerCase()] = MediaItem.fromJson(value as Map<String, dynamic>);
              } catch (e) {
                appLogger.e('Failed to parse torrent metadata for key $key', error: e);
              }
            });
            _initialized = true;
            return;
          }
        } catch (e) {
          appLogger.w('Failed to load torrent metadata from backend: $e. Falling back to local cache.');
        }
      }

      // 2. Local fallback
      final Directory baseDir = Platform.isAndroid || Platform.isIOS
          ? await getApplicationDocumentsDirectory()
          : await getApplicationSupportDirectory();
      _metadataFile = File(path.join(baseDir.path, 'torrent_metadata.json'));

      if (await _metadataFile!.exists()) {
        final content = await _metadataFile!.readAsString();
        if (content.isNotEmpty) {
          final Map<String, dynamic> decoded = jsonDecode(content);
          decoded.forEach((key, value) {
            try {
              _cache[key.toLowerCase()] = MediaItem.fromJson(value as Map<String, dynamic>);
            } catch (e) {
              appLogger.e('Failed to parse torrent metadata for key $key', error: e);
            }
          });
        }
      }
      _initialized = true;
    } catch (e) {
      appLogger.e('Failed to initialize TorrentMetadataService', error: e);
    }
  }

  Future<void> _saveLocal() async {
    try {
      final Directory baseDir = Platform.isAndroid || Platform.isIOS
          ? await getApplicationDocumentsDirectory()
          : await getApplicationSupportDirectory();
      _metadataFile ??= File(path.join(baseDir.path, 'torrent_metadata.json'));

      final Map<String, dynamic> toSerialize = {};
      _cache.forEach((key, value) {
        toSerialize[key] = value.toJson();
      });
      await _metadataFile!.writeAsString(jsonEncode(toSerialize));
    } catch (e) {
      appLogger.e('Failed to save torrent metadata locally', error: e);
    }
  }

  MediaItem? getMetadata(String infoHash) {
    return _cache[infoHash.toLowerCase()];
  }

  Future<void> saveMetadata(String infoHash, MediaItem metadata) async {
    await initialize();
    _cache[infoHash.toLowerCase()] = metadata;
    await _saveLocal();

    // Send to backend
    final baseUrl = TorrentEngineService.instance.baseUrl;
    if (baseUrl.isNotEmpty) {
      try {
        await http.post(
          Uri.parse('$baseUrl/metadata/${infoHash.toLowerCase()}'),
          headers: {
            'Content-Type': 'application/json',
            ...TorrentEngineService.instance.getHeaders(),
          },
          body: jsonEncode(metadata.toJson()),
        ).timeout(const Duration(seconds: 3));
      } catch (e) {
        appLogger.w('Failed to save metadata to backend: $e');
      }
    }
  }

  Future<void> deleteMetadata(String infoHash) async {
    await initialize();
    if (_cache.remove(infoHash.toLowerCase()) != null) {
      await _saveLocal();

      final baseUrl = TorrentEngineService.instance.baseUrl;
      if (baseUrl.isNotEmpty) {
        try {
          await http.delete(
            Uri.parse('$baseUrl/metadata/${infoHash.toLowerCase()}'),
            headers: TorrentEngineService.instance.getHeaders(),
          ).timeout(const Duration(seconds: 3));
        } catch (e) {
          appLogger.w('Failed to delete metadata from backend: $e');
        }
      }
    }
  }

  List<MediaItem> allMetadata() {
    return _cache.values.toList();
  }

  Map<String, MediaItem> get allMetadataMap => Map.unmodifiable(_cache);

  String? getInfoHashForMediaItem(MediaItem item) {
    final targetShowId = item.grandparentId ?? item.id;
    for (final entry in _cache.entries) {
      final meta = entry.value;
      if (meta.id == targetShowId ||
          meta.id == item.id ||
          (meta.grandparentId != null && meta.grandparentId == targetShowId)) {
        return entry.key;
      }
    }
    return null;
  }
}
