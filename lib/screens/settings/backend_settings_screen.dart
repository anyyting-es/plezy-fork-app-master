import 'dart:io';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../services/file_picker_service.dart';
import '../../services/settings_service.dart';
import '../../services/torrent_engine_service.dart';
import '../../widgets/setting_tile.dart';
import '../../widgets/settings_builder.dart';
import '../../widgets/settings_page.dart';
import '../../widgets/settings_section.dart';
import '../../widgets/torrent_realtime_viewer.dart';
import 'settings_utils.dart';

class BackendSettingsScreen extends StatefulWidget {
  const BackendSettingsScreen({super.key});

  @override
  State<BackendSettingsScreen> createState() => _BackendSettingsScreenState();
}

class _BackendSettingsScreenState extends State<BackendSettingsScreen> {
  String _localIp = 'Cargando IP...';
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    _loadLocalIp();
  }

  Future<void> _loadLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
        includeLoopback: false,
      );
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (!addr.isLoopback &&
              (addr.address.startsWith('192.168.') ||
                  addr.address.startsWith('10.') ||
                  addr.address.startsWith('172.'))) {
            if (mounted) {
              setState(() {
                _localIp = addr.address;
              });
            }
            return;
          }
        }
      }
      if (interfaces.isNotEmpty && interfaces.first.addresses.isNotEmpty) {
        if (mounted) {
          setState(() {
            _localIp = interfaces.first.addresses.first.address;
          });
        }
        return;
      }
    } catch (_) {}
    if (mounted) {
      setState(() {
        _localIp = 'No disponible';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsBuilder(
      prefs: const [
        SettingsService.showTorrentSpeedInPlayer,
        SettingsService.keepDownloadedTorrentFiles,
        SettingsService.backendWorkingLocation,
      ],
      builder: (context) {
        final isRunning = TorrentEngineService.instance.isRunning;
        final baseUrl = TorrentEngineService.instance.baseUrl;

        return SettingsPage(
          title: const Text('Ajustes del Backend'),
          children: [
            // ── Section 1: Reproductor de Vídeo ────────────────────────
            SettingsGroup(
              title: 'Reproductor de Vídeo',
              children: [
                SettingSwitchTile(
                  pref: SettingsService.showTorrentSpeedInPlayer,
                  icon: Symbols.speed_rounded,
                  title: 'Mostrar velocidad y progreso en el reproductor',
                  subtitle: 'Muestra un indicador simple (ej: 50.2% • 3.4 MB/s) en la barra del reproductor cuando se reproduce un torrent.',
                ),
              ],
            ),

            // ── Section 2: Gestión de Archivos y Torrents Activos ───────
            SettingsGroup(
              title: 'Gestión de Archivos y Descargas',
              children: [
                SettingSwitchTile(
                  pref: SettingsService.keepDownloadedTorrentFiles,
                  icon: Symbols.folder_zip_rounded,
                  title: 'Mantener archivos descargados (Keep Files)',
                  subtitle: 'Desactivado por defecto (modo 1 torrent a la vez): al iniciar una nueva descarga se elimina el torrent previo y sus archivos del disco. Actívalo para conservar todos los archivos.',
                ),
                ListTile(
                  leading: const Icon(Symbols.delete_sweep_rounded, color: Colors.orangeAccent),
                  title: const Text('Limpiar caché del backend y todos los torrents'),
                  subtitle: const Text('Elimina todos los torrents activos y purga los archivos del sistema.'),
                  onTap: () => _confirmClearAllTorrents(context),
                ),
              ],
            ),

            // ── Section 3: Motor BitTorrent Backend (Go) ─────────────────
            SettingsGroup(
              title: 'Motor BitTorrent Backend (Go)',
              children: [
                SettingSwitchTile(
                  pref: SettingsService.useRemoteBackend,
                  icon: Symbols.settings_remote_rounded,
                  title: 'Usar Servidor Backend Remoto',
                  subtitle: 'Conéctate al motor de torrents de tu PC (PC, Tele, etc.) en lugar de ejecutar uno local.',
                  onAfterWrite: (_) {
                    setState(() {});
                  },
                ),

                if (SettingsService.instance.read(SettingsService.useRemoteBackend)) ...[
                  ListTile(
                    leading: const Icon(Symbols.wifi_find_rounded),
                    title: const Text('Buscar Servidores Remotos'),
                    subtitle: const Text('Escanea tu red local para detectar ordenadores corriendo el motor de torrents.'),
                    trailing: _scanning
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amber),
                          )
                        : const Icon(Symbols.search_rounded),
                    onTap: _scanning ? null : _scanForRemoteServers,
                  ),
                  ValueListenableBuilder<String>(
                    valueListenable: SettingsService.instance.listenable(SettingsService.remoteBackendUrl),
                    builder: (context, remoteUrl, _) {
                      return ListTile(
                        leading: const Icon(Symbols.link_rounded),
                        title: const Text('URL del Backend Remoto'),
                        subtitle: Text(remoteUrl.isEmpty ? 'Ninguno seleccionado' : remoteUrl),
                        trailing: const Icon(Symbols.chevron_right_rounded),
                        onTap: () {
                          showTextInputDialog(
                            context: context,
                            title: 'URL del Backend Remoto',
                            labelText: 'URL (ej: http://192.168.1.50:9876)',
                            currentValue: remoteUrl,
                            onSave: (value) async {
                              await SettingsService.instance.write(SettingsService.remoteBackendUrl, value);
                              setState(() {});
                            },
                          );
                        },
                      );
                    },
                  ),
                  ValueListenableBuilder<String>(
                    valueListenable: SettingsService.instance.listenable(SettingsService.remoteBackendPin),
                    builder: (context, remotePin, _) {
                      return ListTile(
                        leading: const Icon(Symbols.vpn_key_rounded),
                        title: const Text('PIN del Backend Remoto'),
                        subtitle: Text(remotePin.isEmpty ? 'Sin PIN' : '•••• (PIN Configurado)'),
                        trailing: const Icon(Symbols.chevron_right_rounded),
                        onTap: () {
                          showTextInputDialog(
                            context: context,
                            title: 'PIN del Backend Remoto',
                            labelText: 'PIN / Contraseña del servidor',
                            currentValue: remotePin,
                            onSave: (value) async {
                              await SettingsService.instance.write(SettingsService.remoteBackendPin, value);
                              setState(() {});
                            },
                          );
                        },
                      );
                    },
                  ),
                ] else ...[
                  SettingSwitchTile(
                    pref: SettingsService.allowLanConnections,
                    icon: Symbols.wifi_tethering_rounded,
                    title: 'Compartir motor en red local (LAN)',
                    subtitle: 'Permite que otros dispositivos de tu red (móvil, TV) se conecten a las descargas de este ordenador.',
                    onAfterWrite: (_) {
                      if (TorrentEngineService.instance.isRunning) {
                        TorrentEngineService.instance.stop().then((_) {
                          TorrentEngineService.instance.start().then((_) {
                            if (mounted) setState(() {});
                          });
                        });
                      }
                    },
                  ),
                  if (SettingsService.instance.read(SettingsService.allowLanConnections)) ...[
                    ValueListenableBuilder<String>(
                      valueListenable: SettingsService.instance.listenable(SettingsService.backendPin),
                      builder: (context, pin, _) {
                        return ListTile(
                          leading: const Icon(Symbols.lock_rounded),
                          title: const Text('PIN de Seguridad del Motor Local'),
                          subtitle: Text(pin.isEmpty ? 'Sin PIN (No recomendado)' : 'PIN configurado: $pin'),
                          trailing: const Icon(Symbols.chevron_right_rounded),
                          onTap: () {
                            showTextInputDialog(
                              context: context,
                              title: 'PIN de Seguridad del Motor Local',
                              labelText: 'PIN / Contraseña (ej: 1234)',
                              currentValue: pin,
                              onSave: (value) async {
                                await SettingsService.instance.write(SettingsService.backendPin, value);
                                if (TorrentEngineService.instance.isRunning) {
                                  await TorrentEngineService.instance.stop();
                                  await TorrentEngineService.instance.start();
                                }
                                setState(() {});
                              },
                            );
                          },
                        );
                      },
                    ),
                  ],
                  ListTile(
                    leading: Icon(
                      isRunning ? Symbols.check_circle_rounded : Symbols.cancel_rounded,
                      color: isRunning ? Colors.greenAccent : Colors.redAccent,
                    ),
                    title: const Text('Estado del Servidor Backend'),
                    subtitle: Text(
                      isRunning
                          ? (SettingsService.instance.read(SettingsService.allowLanConnections)
                              ? 'Servidor Go ejecutándose en LAN\nLocal: $baseUrl\nRed LAN: http://$_localIp:${TorrentEngineService.instance.port ?? 9876}'
                              : 'Servidor Go ejecutándose en local ($baseUrl)')
                          : 'El servidor local en Go está detenido',
                    ),
                    trailing: ElevatedButton(
                      onPressed: () async {
                        if (isRunning) {
                          await TorrentEngineService.instance.stop();
                        } else {
                          await TorrentEngineService.instance.start();
                        }
                        if (mounted) setState(() {});
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isRunning ? Colors.redAccent.withValues(alpha: 0.2) : Colors.green.withValues(alpha: 0.2),
                        foregroundColor: isRunning ? Colors.redAccent : Colors.greenAccent,
                      ),
                      child: Text(isRunning ? 'Detener Motor' : 'Iniciar Motor'),
                    ),
                  ),
                ],

                ListTile(
                  leading: const Icon(Symbols.downloading_rounded),
                  title: const Text('Visor de Torrents en Tiempo Real'),
                  subtitle: const Text('Ver métricas completas, semillas, pares conectados y detalle de archivos.'),
                  trailing: const Icon(Symbols.chevron_right_rounded),
                  onTap: () => TorrentRealtimeViewer.show(context),
                ),

                FutureBuilder<String>(
                  future: TorrentEngineService.instance.getDownloadDirectory(),
                  builder: (context, snapshot) {
                    final path = snapshot.data ?? 'Cargando...';
                    final customLocation = SettingsService.instance.read(SettingsService.backendWorkingLocation);
                    final isCustom = customLocation.isNotEmpty;

                    return ListTile(
                      leading: const Icon(Symbols.folder_open_rounded),
                      title: Text(
                        isCustom
                            ? 'Directorio de Trabajo del Backend (Personalizado)'
                            : 'Directorio de Trabajo del Backend (Por defecto)',
                      ),
                      subtitle: Text(path, maxLines: 2, overflow: TextOverflow.ellipsis),
                      trailing: const Icon(Symbols.chevron_right_rounded),
                      onTap: () => _pickBackendDirectory(context),
                    );
                  },
                ),

                FutureBuilder<String>(
                  future: TorrentEngineService.instance.getDownloadsDirectory(),
                  builder: (context, snapshot) {
                    final path = snapshot.data ?? 'Cargando...';
                    final customLocation = SettingsService.instance.read(SettingsService.downloadsLocation);
                    final isCustom = customLocation.isNotEmpty;

                    return ListTile(
                      leading: const Icon(Symbols.download_done_rounded),
                      title: Text(
                        isCustom
                            ? 'Carpeta de Descargas de Películas/Series (Personalizada)'
                            : 'Carpeta de Descargas de Películas/Series (Por defecto)',
                      ),
                      subtitle: Text(path, maxLines: 2, overflow: TextOverflow.ellipsis),
                      trailing: const Icon(Symbols.chevron_right_rounded),
                      onTap: () => _pickDownloadsDirectory(context),
                    );
                  },
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Future<void> _pickBackendDirectory(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final newPath = await FilePickerService.instance.getDirectoryPath(
      dialogTitle: 'Seleccionar carpeta de trabajo para el motor de torrents',
    );

    if (newPath != null && newPath.isNotEmpty) {
      await SettingsService.instance.write(SettingsService.backendWorkingLocation, newPath);
      if (TorrentEngineService.instance.isRunning) {
        await TorrentEngineService.instance.stop();
        await TorrentEngineService.instance.start();
      }
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Carpeta del backend actualizada: $newPath')),
        );
        setState(() {});
      }
    }
  }

  Future<void> _pickDownloadsDirectory(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final newPath = await FilePickerService.instance.getDirectoryPath(
      dialogTitle: 'Seleccionar carpeta para descargas de películas/series',
    );

    if (newPath != null && newPath.isNotEmpty) {
      await SettingsService.instance.write(SettingsService.downloadsLocation, newPath);
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Carpeta de descargas actualizada: $newPath')),
        );
        setState(() {});
      }
    }
  }

  Future<void> _confirmClearAllTorrents(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Limpiar todos los torrents'),
        content: const Text('¿Seguro que deseas eliminar todos los torrents activos y borrar sus archivos descargados del sistema?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('Eliminar Todo'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final list = await TorrentEngineService.instance.listTorrents();
      for (final t in list) {
        await TorrentEngineService.instance.removeTorrent(t.infoHash, deleteFiles: true);
      }
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Se eliminaron todos los torrents y archivos del backend.')),
        );
        setState(() {});
      }
    }
  }

  Future<void> _scanForRemoteServers() async {
    setState(() {
      _scanning = true;
    });
    final messenger = ScaffoldMessenger.of(context);
    final results = await TorrentEngineService.discoverBackends(timeout: const Duration(seconds: 2));
    setState(() {
      _scanning = false;
    });

    if (!mounted) return;

    if (results.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('No se encontraron motores de torrents activos en la red local.'),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    final selected = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Seleccionar Servidor Encontrado'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: results.map((url) {
            return ListTile(
              leading: const Icon(Symbols.dns_rounded, color: Colors.amber),
              title: Text(url),
              onTap: () => Navigator.of(dialogCtx).pop(url),
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );

    if (selected != null && selected.isNotEmpty) {
      await SettingsService.instance.write(SettingsService.remoteBackendUrl, selected);
      setState(() {});
      messenger.showSnackBar(
        SnackBar(content: Text('Conectado al servidor: $selected')),
      );
    }
  }
}
