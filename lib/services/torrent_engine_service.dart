import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart' as path_provider;
import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';
import '../utils/app_logger.dart';
import 'settings_service.dart';
import 'torrent_metadata_service.dart';

String formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
  double b = bytes.toDouble();
  int i = 0;
  while (b >= 1024 && i < suffixes.length - 1) {
    b /= 1024;
    i++;
  }
  return '${b.toStringAsFixed(b < 10 && i > 0 ? 2 : 1)} ${suffixes[i]}';
}

String formatSpeed(double bytesPerSec) {
  if (bytesPerSec <= 0) return '0 B/s';
  const suffixes = ['B/s', 'KB/s', 'MB/s', 'GB/s'];
  double s = bytesPerSec;
  int i = 0;
  while (s >= 1024 && i < suffixes.length - 1) {
    s /= 1024;
    i++;
  }
  return '${s.toStringAsFixed(s < 10 && i > 0 ? 2 : 1)} ${suffixes[i]}';
}

/// Represents a snapshot of an active torrent from the Go backend.
class TorrentInfo {
  final String infoHash;
  final String name;
  final int size;
  final int downloaded;
  final double downloadSpeed;
  final double uploadSpeed;
  final int seeders;
  final int leechers;
  final double progress;
  final List<TorrentFile> files;
  final bool paused;

  TorrentInfo({
    required this.infoHash,
    required this.name,
    required this.size,
    required this.downloaded,
    required this.downloadSpeed,
    required this.uploadSpeed,
    required this.seeders,
    required this.leechers,
    required this.progress,
    required this.files,
    required this.paused,
  });

  String get downloadSpeedFormatted => formatSpeed(downloadSpeed);
  String get uploadSpeedFormatted => formatSpeed(uploadSpeed);
  String get downloadedFormatted => formatBytes(downloaded);
  String get sizeFormatted => formatBytes(size);
  String get progressFormatted => '${progress.toStringAsFixed(1)}%';

  String get etaFormatted {
    if (progress >= 100 || (size > 0 && downloaded >= size)) return 'Completado';
    if (downloadSpeed <= 0) return 'Conectando / Infinito';
    final remainingBytes = size - downloaded;
    if (remainingBytes <= 0) return '0s';
    final seconds = (remainingBytes / downloadSpeed).ceil();
    if (seconds > 86400) return '> 1 día';
    final hours = seconds ~/ 3600;
    final mins = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;
    if (hours > 0) {
      return '${hours}h ${mins}m';
    } else if (mins > 0) {
      return '${mins}m ${secs}s';
    } else {
      return '${secs}s';
    }
  }

  factory TorrentInfo.fromJson(Map<String, dynamic> json) {
    final filesJson = (json['files'] as List<dynamic>?) ?? const [];
    return TorrentInfo(
      infoHash: (json['infoHash'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      size: (json['size'] as int?) ?? 0,
      downloaded: (json['downloaded'] as int?) ?? 0,
      downloadSpeed: (json['downloadSpeed'] as num?)?.toDouble() ?? 0.0,
      uploadSpeed: (json['uploadSpeed'] as num?)?.toDouble() ?? 0.0,
      seeders: (json['seeders'] as int?) ?? 0,
      leechers: (json['leechers'] as int?) ?? 0,
      progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
      files: filesJson.map((f) => TorrentFile.fromJson(f as Map<String, dynamic>)).toList(),
      paused: (json['paused'] as bool?) ?? false,
    );
  }
}

class TorrentFile {
  final int index;
  final String path;
  final int size;
  final int downloaded;

  TorrentFile({
    required this.index,
    required this.path,
    required this.size,
    required this.downloaded,
  });

  double get progress => size > 0 ? (downloaded / size * 100).clamp(0.0, 100.0) : 0.0;
  String get downloadedFormatted => formatBytes(downloaded);
  String get sizeFormatted => formatBytes(size);
  String get progressFormatted => '${progress.toStringAsFixed(1)}%';

  factory TorrentFile.fromJson(Map<String, dynamic> json) {
    return TorrentFile(
      index: (json['index'] as int?) ?? 0,
      path: (json['path'] as String?) ?? '',
      size: (json['size'] as int?) ?? 0,
      downloaded: (json['downloaded'] as int?) ?? 0,
    );
  }
}

// FFI Typedefs
typedef StartServerNative = ffi.Int32 Function(ffi.Pointer<Utf8> downloadDir);
typedef StartServerDart = int Function(ffi.Pointer<Utf8> downloadDir);
typedef StopServerNative = ffi.Void Function();
typedef StopServerDart = void Function();

/// Service that spawns, manages, and communicates with the local Go torrent daemon.
class TorrentEngineService {
  TorrentEngineService._();
  static final TorrentEngineService instance = TorrentEngineService._();

  Process? _backendProcess;
  int? _port;
  bool _starting = false;
  Completer<bool>? _startCompleter;

  ffi.DynamicLibrary? _ffiLib;
  StartServerDart? _startServer;
  StopServerDart? _stopServer;
  bool _isFfiLoaded = false;

  bool get isRunning {
    final useRemote = SettingsService.instance.read(SettingsService.useRemoteBackend);
    if (useRemote) return true;
    return Platform.isAndroid ? _port != null : (_backendProcess != null && _port != null);
  }

  String get baseUrl {
    final useRemote = SettingsService.instance.read(SettingsService.useRemoteBackend);
    if (useRemote) {
      var url = SettingsService.instance.read(SettingsService.remoteBackendUrl).trim();
      if (url.endsWith('/')) {
        url = url.substring(0, url.length - 1);
      }
      return url;
    }
    return isRunning ? 'http://127.0.0.1:$_port' : '';
  }

  int? get port => _port;

  Map<String, String> getHeaders() {
    final useRemote = SettingsService.instance.read(SettingsService.useRemoteBackend);
    final pin = useRemote 
        ? SettingsService.instance.read(SettingsService.remoteBackendPin)
        : SettingsService.instance.read(SettingsService.backendPin);
    if (pin.isEmpty) return {};
    return {'X-Aniting-PIN': pin};
  }

  /// Resolves the working directory for backend torrent streaming (where extensions, temp cache etc go)
  Future<String> getDownloadDirectory() async {
    var customDir = SettingsService.instance.read(SettingsService.backendWorkingLocation);
    if (customDir.isNotEmpty) {
      if (customDir.endsWith('torrents') || customDir.endsWith('torrents/')) {
        customDir = customDir.replaceAll(RegExp(r'torrents/?$'), 'aniting');
        await SettingsService.instance.write(SettingsService.backendWorkingLocation, customDir);
      }
      final dir = Directory(customDir);
      if (await dir.exists()) {
        return customDir;
      } else {
        try {
          await dir.create(recursive: true);
          return customDir;
        } catch (e) {
          appLogger.w('[torrent] Failed to create custom backend dir $customDir: $e');
        }
      }
    }

    // Default backend working directory (hidden system config/support folder)
    if (Platform.isAndroid) {
      try {
        final extDir = await path_provider.getExternalStorageDirectory();
        if (extDir != null) return '${extDir.path}/aniting-backend';
      } catch (_) {}
    } else {
      try {
        final appSupportDir = await path_provider.getApplicationSupportDirectory();
        return '${appSupportDir.path}${Platform.pathSeparator}aniting';
      } catch (_) {}
    }

    final userHome = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? Directory.systemTemp.path;
    return '$userHome${Platform.pathSeparator}.aniting';
  }

  /// Resolves the downloads directory for manual downloads (Movies and Shows)
  Future<String> getDownloadsDirectory() async {
    final customDir = SettingsService.instance.read(SettingsService.downloadsLocation);
    if (customDir.isNotEmpty) {
      final dir = Directory(customDir);
      if (await dir.exists()) {
        return customDir;
      } else {
        try {
          await dir.create(recursive: true);
          return customDir;
        } catch (_) {}
      }
    }

    // Default downloads directory: user's Documents/aniting
    if (Platform.isAndroid) {
      try {
        final extDir = await path_provider.getExternalStorageDirectory();
        if (extDir != null) return '${extDir.path}/aniting';
      } catch (_) {}
    } else {
      try {
        final appDocDir = await path_provider.getApplicationDocumentsDirectory();
        return '${appDocDir.path}${Platform.pathSeparator}aniting';
      } catch (_) {}
    }

    final userHome = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? Directory.systemTemp.path;
    return '$userHome${Platform.pathSeparator}aniting';
  }

  /// Locates the Go backend binary based on platform and current environment.
  /// On Android, extracts the binary from assets on first run.
  Future<String?> _findBackendBinary() async {
    // Android: extract the arch-appropriate binary from assets to a writable dir
    if (Platform.isAndroid) {
      return _findOrExtractAndroidBinary();
    }

    final exeName = Platform.isWindows ? 'aniting-backend.exe' : 'aniting-backend';

    // 1. Check next to the Flutter runner executable (production release layout)
    final runnerDir = Directory(Platform.resolvedExecutable).parent.path;
    final prodPath = '$runnerDir${Platform.pathSeparator}$exeName';
    if (await File(prodPath).exists()) {
      return prodPath;
    }

    // 2. Check development path relative to workspace root (Aniting/backend/aniting-backend)
    final projectDir = Directory.current.path;
    final devPath = '$projectDir${Platform.pathSeparator}backend${Platform.pathSeparator}$exeName';
    if (await File(devPath).exists()) {
      return devPath;
    }

    return null;
  }

  /// Extracts the Go backend binary from Flutter assets to the app files dir.
  /// Returns the path to the extracted executable, or null on failure.
  Future<String?> _findOrExtractAndroidBinary() async {
    try {
      // Determine CPU ABI
      final abi = await _getAndroidAbi();
      final assetName = 'backend/aniting-backend-$abi';

      final filesDir = await path_provider.getApplicationSupportDirectory();
      final destFile = File('${filesDir.path}/aniting-backend');

      // Check if asset exists for this ABI
      ByteData? assetData;
      try {
        assetData = await rootBundle.load(assetName);
      } catch (_) {
        appLogger.e('[torrent] No bundled backend found for ABI: $abi (asset: $assetName)');
        return null;
      }

      // Write binary to disk
      final bytes = assetData.buffer.asUint8List();
      await destFile.writeAsBytes(bytes, flush: true);

      // Make executable
      await Process.run('chmod', ['+x', destFile.path]);

      appLogger.d('[torrent] Extracted backend binary to ${destFile.path} (${bytes.length} bytes)');
      return destFile.path;
    } catch (e) {
      appLogger.e('[torrent] Failed to extract Android backend binary: $e');
      return null;
    }
  }

  /// Returns the primary ABI of the current Android device (e.g. "arm64", "x86_64").
  Future<String> _getAndroidAbi() async {
    try {
      final result = await Process.run('getprop', ['ro.product.cpu.abi']);
      final abi = (result.stdout as String).trim();
      // Map Android ABI strings to our asset naming convention
      if (abi.startsWith('arm64')) return 'arm64';
      if (abi.startsWith('armeabi')) return 'arm';
      if (abi.startsWith('x86_64')) return 'x86_64';
      if (abi.startsWith('x86')) return 'x86';
      return 'arm64'; // default fallback
    } catch (_) {
      return 'arm64';
    }
  }

  void _loadFfiLibrary() {
    if (_isFfiLoaded) return;
    try {
      _ffiLib = ffi.DynamicLibrary.open('libtorrent.so');
      _startServer = _ffiLib!.lookupFunction<StartServerNative, StartServerDart>('StartServer');
      _stopServer = _ffiLib!.lookupFunction<StopServerNative, StopServerDart>('StopServer');
      _isFfiLoaded = true;
      appLogger.i('[torrent] FFI library loaded successfully');
    } catch (e) {
      appLogger.e('[torrent] Failed to load FFI library', error: e);
    }
  }

  /// Starts the local Go torrent engine if it isn't already running.
  Future<bool> start() async {
    if (isRunning) return true;
    if (_starting) return _startCompleter!.future;

    _starting = true;
    final completer = Completer<bool>();
    _startCompleter = completer;

    try {
      if (Platform.isAndroid) {
        _loadFfiLibrary();
        if (!_isFfiLoaded || _startServer == null) {
          appLogger.e('[torrent] FFI library not loaded, cannot start on Android');
          _starting = false;
          completer.complete(false);
          return false;
        }

        final downloadDir = await getDownloadDirectory();
        appLogger.d('[torrent] Starting FFI engine with data dir: $downloadDir');
        
        final pointer = downloadDir.toNativeUtf8();
        final portNum = _startServer!(pointer);
        malloc.free(pointer);

        if (portNum <= 0) {
          appLogger.e('[torrent] FFI engine failed to start (returned port: $portNum)');
          _starting = false;
          completer.complete(false);
          return false;
        }

        _port = portNum;
        appLogger.i('[torrent] FFI Engine started successfully on port $_port');
        
        // Wait a small moment to ensure the server is listening
        await Future.delayed(const Duration(milliseconds: 500));
        
        _starting = false;
        completer.complete(true);
        unawaited(_restorePersistedTorrents());
        return true;
      }

      // 1. Clean up potential orphaned backend instances
      if (Platform.isWindows) {
        await Process.run('taskkill', ['/f', '/im', 'aniting-backend.exe']);
      } else {
        await Process.run('pkill', ['-f', 'aniting-backend']);
      }
    } catch (_) {}

    try {
      final binaryPath = await _findBackendBinary();
      if (binaryPath == null) {
        appLogger.e('[torrent] Go backend binary not found. Make sure to build it first.');
        _starting = false;
        completer.complete(false);
        return false;
      }

      final downloadDir = await getDownloadDirectory();
      appLogger.d('[torrent] Starting engine at $binaryPath with data dir: $downloadDir');

      final allowLan = SettingsService.instance.read(SettingsService.allowLanConnections);
      final pin = SettingsService.instance.read(SettingsService.backendPin);
      _backendProcess = await Process.start(
        binaryPath,
        [downloadDir],
        mode: ProcessStartMode.normal,
        environment: {
          'ANITING_HOST': allowLan ? '0.0.0.0' : '127.0.0.1',
          if (pin.isNotEmpty) 'ANITING_PIN': pin,
        },
      );

      final portCompleter = Completer<int>();

      // Read output stream to catch the port printed at start
      _backendProcess!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        appLogger.d('[torrent-backend] $line');
        if (line.contains('ANITING_BACKEND_PORT=')) {
          final portStr = line.split('=').last.trim();
          final portNum = int.tryParse(portStr);
          if (portNum != null && !portCompleter.isCompleted) {
            portCompleter.complete(portNum);
          }
        }
      });

      _backendProcess!.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        appLogger.e('[torrent-backend ERR] $line');
      });

      // Wait for port resolution with a 15-second timeout
      final resolvedPort = await portCompleter.future.timeout(const Duration(seconds: 15));
      _port = resolvedPort;

      appLogger.i('[torrent] Engine started successfully on port $_port');
      _starting = false;
      completer.complete(true);
      unawaited(_restorePersistedTorrents());
      return true;

    } catch (e, stack) {
      appLogger.e('[torrent] Failed to start engine', error: e, stackTrace: stack);
      _backendProcess?.kill();
      _backendProcess = null;
      _port = null;
      _starting = false;
      if (!completer.isCompleted) completer.complete(false);
      return false;
    }
  }

  /// Stops the Go daemon.
  Future<void> stop() async {
    if (Platform.isAndroid) {
      if (_isFfiLoaded && _stopServer != null) {
        appLogger.i('[torrent] Stopping FFI torrent engine...');
        try {
          _stopServer!();
        } catch (e) {
          appLogger.e('[torrent] Error calling stopServer on FFI', error: e);
        }
      }
      _port = null;
      return;
    }

    if (_backendProcess != null) {
      appLogger.i('[torrent] Stopping torrent engine...');
      _backendProcess!.kill();
      await _backendProcess!.exitCode.timeout(const Duration(seconds: 3), onTimeout: () => -1);
      _backendProcess = null;
      _port = null;
    }
  }

  // ─── API Client Endpoints ──────────────────────────────────────────────────

  /// Scans the local network using UDP broadcast on port 9877.
  /// Sends a broadcast ping and listens for responses for the specified duration.
  /// Returns a list of discovered backend URLs.
  static Future<List<String>> discoverBackends({Duration timeout = const Duration(seconds: 3)}) async {
    final List<String> servers = [];
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;

      socket.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = socket!.receive();
          if (datagram != null) {
            try {
              final msg = utf8.decode(datagram.data).trim();
              if (msg.startsWith('ANITING_PONG:')) {
                final url = msg.substring('ANITING_PONG:'.length).trim();
                if (!servers.contains(url)) {
                  servers.add(url);
                }
              }
            } catch (_) {}
          }
        }
      });

      // Send discovery ping to broadcast address
      final data = utf8.encode('ANITING_PING');
      socket.send(data, InternetAddress('255.255.255.255'), 9877);

      // Wait for responses
      await Future.delayed(timeout);
    } catch (e) {
      appLogger.w('[torrent] Error discovering backends: $e');
    } finally {
      socket?.close();
    }
    return servers;
  }

  Future<bool> checkHealth() async {
    if (!isRunning) return false;
    try {
      final res = await http.get(Uri.parse('$baseUrl/health'), headers: getHeaders()).timeout(const Duration(seconds: 2));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Adds a magnet link or hash to the daemon. Returns the [TorrentInfo] metadata.
  Future<TorrentInfo?> addTorrent(String magnetOrHash) async {
    if (!isRunning && !await start()) return null;

    try {
      final res = await http.post(
        Uri.parse('$baseUrl/add'),
        headers: {
          'Content-Type': 'application/json',
          ...getHeaders(),
        },
        body: jsonEncode({'magnetLink': magnetOrHash}),
      ).timeout(const Duration(seconds: 60));

      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body) as Map<String, dynamic>;
        return TorrentInfo.fromJson(decoded);
      } else {
        appLogger.w('[torrent] Failed to add torrent: ${res.body}');
      }
    } catch (e) {
      appLogger.e('[torrent] Error adding torrent', error: e);
    }
    return null;
  }

  /// Gets the statistics of a specific active torrent.
  Future<TorrentInfo?> getTorrentInfo(String infoHash) async {
    if (!isRunning) return null;
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/torrent/${infoHash.toLowerCase()}'),
        headers: getHeaders(),
      ).timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body) as Map<String, dynamic>;
        return TorrentInfo.fromJson(decoded);
      }
    } catch (e) {
      appLogger.e('[torrent] Error getting torrent info for $infoHash', error: e);
    }
    return null;
  }

  /// Removes a torrent from the active list.
  Future<bool> removeTorrent(String infoHash, {bool deleteFiles = true}) async {
    if (!isRunning) return false;
    try {
      final res = await http.delete(
        Uri.parse('$baseUrl/torrent/${infoHash.toLowerCase()}'),
        headers: {
          'Content-Type': 'application/json',
          ...getHeaders(),
        },
        body: jsonEncode({'deleteFiles': deleteFiles}),
      ).timeout(const Duration(seconds: 5));
      return res.statusCode == 204 || res.statusCode == 200;
    } catch (e) {
      appLogger.e('[torrent] Error removing torrent $infoHash', error: e);
      return false;
    }
  }

  /// Pauses downloading and uploading for a torrent.
  Future<bool> pauseTorrent(String infoHash) async {
    if (!isRunning) return false;
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/torrent/${infoHash.toLowerCase()}/pause'),
        headers: getHeaders(),
      ).timeout(const Duration(seconds: 5));
      return res.statusCode == 204 || res.statusCode == 200;
    } catch (e) {
      appLogger.e('[torrent] Error pausing torrent $infoHash', error: e);
      return false;
    }
  }

  /// Resumes downloading and uploading for a torrent.
  Future<bool> resumeTorrent(String infoHash) async {
    if (!isRunning) return false;
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/torrent/${infoHash.toLowerCase()}/resume'),
        headers: getHeaders(),
      ).timeout(const Duration(seconds: 5));
      return res.statusCode == 204 || res.statusCode == 200;
    } catch (e) {
      appLogger.e('[torrent] Error resuming torrent $infoHash', error: e);
      return false;
    }
  }

  /// Lists all active torrents currently managed by the Go backend.
  Future<List<TorrentInfo>> listTorrents() async {
    if (!isRunning) return const [];
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/list'),
        headers: getHeaders(),
      ).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body) as List<dynamic>;
        return decoded.map((item) => TorrentInfo.fromJson(item as Map<String, dynamic>)).toList();
      }
    } catch (e) {
      appLogger.e('[torrent] Error listing active torrents', error: e);
    }
    return const [];
  }

  /// Returns the stream URL that should be fed into the media player.
  /// Format: `http://127.0.0.1:<port>/stream/<infoHash>/<fileIndex>`
  Future<String?> getStreamUrl(String infoHash, int fileIndex) async {
    if (!isRunning && !await start()) return null;
    return '$baseUrl/stream/${infoHash.toLowerCase()}/$fileIndex';
  }

  /// Real-time stream of active torrents. Updates every second via SSE or polling.
  Stream<List<TorrentInfo>> watchTorrents({Duration interval = const Duration(seconds: 1)}) {
    late StreamController<List<TorrentInfo>> controller;
    Timer? timer;
    http.Client? sseClient;
    StreamSubscription? sseSubscription;

    void startPolling() {
      timer?.cancel();
      timer = Timer.periodic(interval, (_) async {
        if (isRunning && !controller.isClosed) {
          final list = await listTorrents();
          if (!controller.isClosed) controller.add(list);
        }
      });
    }

    controller = StreamController<List<TorrentInfo>>.broadcast(
      onListen: () {
        // Immediate fetch
        listTorrents().then((list) {
          if (!controller.isClosed) controller.add(list);
        });

        if (isRunning) {
          try {
            sseClient = http.Client();
            final request = http.Request('GET', Uri.parse('$baseUrl/events'));
            request.headers.addAll(getHeaders());
            sseClient!.send(request).then((response) {
              if (response.statusCode == 200) {
                sseSubscription = response.stream
                    .transform(utf8.decoder)
                    .transform(const LineSplitter())
                    .listen(
                  (line) {
                    if (line.startsWith('data: ')) {
                      final jsonStr = line.substring(6).trim();
                      if (jsonStr.isNotEmpty && !controller.isClosed) {
                        try {
                          final decoded = jsonDecode(jsonStr) as List<dynamic>;
                          final list = decoded
                              .map((item) => TorrentInfo.fromJson(item as Map<String, dynamic>))
                              .toList();
                          controller.add(list);
                        } catch (e) {
                          appLogger.w('[torrent] Error parsing SSE payload: $e');
                        }
                      }
                    }
                  },
                  onError: (err) {
                    appLogger.w('[torrent] SSE error, falling back to polling: $err');
                    startPolling();
                  },
                  onDone: () {
                    startPolling();
                  },
                );
              } else {
                startPolling();
              }
            }).catchError((err) {
              startPolling();
            });
          } catch (_) {
            startPolling();
          }
        } else {
          startPolling();
        }
      },
      onCancel: () {
        sseSubscription?.cancel();
        sseClient?.close();
        timer?.cancel();
        controller.close();
      },
    );

    return controller.stream;
  }

  Future<void> _restorePersistedTorrents() async {
    try {
      await TorrentMetadataService.instance.initialize();
      final map = TorrentMetadataService.instance.allMetadataMap;
      if (map.isEmpty) return;

      appLogger.d('[torrent] Restoring ${map.length} persisted torrents to engine...');
      for (final infoHash in map.keys) {
        unawaited(() async {
          try {
            await addTorrent('magnet:?xt=urn:btih:$infoHash');
          } catch (e) {
            appLogger.w('[torrent] Failed to restore torrent $infoHash: $e');
          }
        }());
      }
    } catch (e) {
      appLogger.e('[torrent] Error restoring persisted torrents', error: e);
    }
  }
}
