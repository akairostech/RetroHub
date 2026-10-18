import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/widgets.dart';

import 'core/layout.dart';
import 'core/app_log.dart';
import 'core/file_hash.dart';
import 'core/library_scanner.dart';
import 'core/models.dart';
import 'core/settings.dart';
import 'net/client.dart';
import 'net/protocol.dart';
import 'net/server.dart';
import 'launch/launcher.dart';
import 'input/gamepad.dart';
import 'update/updater.dart';
import 'ui/widgets/box_art.dart';
import 'scrape/igdb.dart';
import 'scrape/scraper.dart';
import 'sync/downloader.dart';
import 'sync/save_sync.dart';

/// Estado global de la app.
class AppState extends ChangeNotifier {
  late final AppSettings settings;
  late final HashCache hashes;
  late final RetroServer server;
  late final SaveSync saveSync;
  final downloads = DownloadManager();
  final scraper = Scraper();
  final launcher = GameLauncher();
  final gamepad = GamepadService();
  final updater = Updater();

  Set<String> favorites = {};
  List<String> recents = [];

  bool ready = false;
  LibraryLayout? layout;

  // Biblioteca local
  Map<String, List<Game>> library = {};
  bool scanning = false;
  String? scanError;

  // Conexión a otro dispositivo
  RetroClient? client;
  Map<String, List<Game>> remoteLibrary = {};
  bool connecting = false;

  /// true si el servidor al que nos conectamos es esta misma instalación.
  bool connectedToSelf = false;
  String? connectError;

  // Android: acceso a todos los archivos
  bool storageGranted = true;

  int get localGameCount => library.values.fold(0, (s, g) => s + g.length);

  Future<void> init() async {
    settings = await AppSettings.load();
    hashes = await HashCache.open();
    server = RetroServer(
      layout: () => layout,
      library: () => library,
      pin: () => settings.serverPin,
      deviceName: () => settings.deviceName,
      instanceId: () => settings.instanceId,
      hashes: hashes,
    );
    saveSync = SaveSync(hashes);
    favorites = settings.favorites;
    recents = settings.recents;
    gamepad.start();
    downloads.onRomDownloaded = rescan;

    if (Platform.isAndroid) {
      storageGranted = await _hasAllFilesAccess();
      // Al volver de la pantalla de permisos de Android, revisamos de nuevo.
      _lifecycle = AppLifecycleListener(onResume: () async {
        final granted = await _hasAllFilesAccess();
        if (granted != storageGranted) {
          storageGranted = granted;
          notifyListeners();
          if (granted) await rescan();
        }
      });
    }

    var root = settings.emulationRoot;
    if (root == null || !await Directory(root).exists()) {
      root = await detectEmulationRoot();
      if (root != null) settings.emulationRoot = root;
    }
    if (root != null) layout = LibraryLayout(root);
    _attachLog();
    appLog.info('RetroHub iniciado en ${Platform.operatingSystem} '
        '(carpeta: ${layout?.root ?? 'sin configurar'})');

    ready = true;
    notifyListeners();

    boxArt3dEnabled.value = settings.boxArt3d;
    if (settings.autoCheckUpdates) {
      // En segundo plano; avisa en la barra lateral si hay versión nueva.
      updater.check().then((_) => notifyListeners());
    }

    if (layout != null) await rescan();
    if (isDesktop && settings.autoStartServer) {
      await server.start(settings.serverPort);
    }
    // Reconectar al último servidor usado (en segundo plano).
    final host = settings.lastServerHost;
    if (host != null) {
      connect(ServerAddress(host, host, settings.lastServerPort ?? 8787),
          settings.lastServerPin ?? '',
          silent: true);
    }
  }

  // Canal hacia MainActivity.kt (Android) para el permiso
  // "Acceso a todos los archivos".
  static const _storageChannel = MethodChannel('retro_hub/storage');
  AppLifecycleListener? _lifecycle;

  Future<bool> _hasAllFilesAccess() async {
    try {
      return await _storageChannel.invokeMethod<bool>('hasAllFilesAccess') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Abre la pantalla de Android para conceder el permiso. El resultado se
  /// detecta al volver a la app (ver AppLifecycleListener en init).
  Future<void> requestStoragePermission() async {
    if (!Platform.isAndroid) return;
    try {
      await _storageChannel.invokeMethod('requestAllFilesAccess');
    } catch (_) {}
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    super.dispose();
  }

  void _attachLog() {
    final lay = layout;
    if (lay != null) {
      appLog.attachDirectory(
          '${lay.root}${Platform.pathSeparator}storage${Platform.pathSeparator}'
          'retrohub${Platform.pathSeparator}logs',
          settings.deviceName);
    }
  }

  Future<void> setEmulationRoot(String root) async {
    settings.emulationRoot = root;
    layout = LibraryLayout(root);
    _attachLog();
    notifyListeners();
    await rescan();
  }

  Future<void> rescan() async {
    final lay = layout;
    if (lay == null || scanning) return;
    scanning = true;
    scanError = null;
    notifyListeners();
    try {
      if (!await lay.isValid()) {
        scanError = 'No se encontró la carpeta "roms" dentro de ${lay.root}';
        library = {};
      } else {
        library = await scanLibrary(lay);
      }
    } catch (e, st) {
      scanError = '$e';
      appLog.error('Fallo al escanear ${lay.roms}', e, st);
    }
    scanning = false;
    notifyListeners();
  }

  /// Fuente IGDB si el usuario configuró sus credenciales.
  IgdbSource? igdbSource() => settings.hasIgdb
      ? IgdbSource(http.Client(), settings.igdbClientId, settings.igdbClientSecret)
      : null;

  Future<void> scrape(List<Game> games, ScrapeOptions options) async {
    final lay = layout;
    if (lay == null || games.isEmpty) return;
    await scraper.run(layout: lay, games: games, options: options, igdb: igdbSource());
    await rescan();
  }

  /// Fuerza a redibujar las pantallas que dependen del estado.
  void refresh() => notifyListeners();

  bool isFavorite(Game g) => favorites.contains(g.key);

  void toggleFavorite(Game g) {
    favorites = {...favorites};
    if (!favorites.remove(g.key)) favorites.add(g.key);
    settings.favorites = favorites;
    notifyListeners();
  }

  /// Abre el juego en su emulador. Devuelve un mensaje de error o null.
  Future<String?> play(Game g) async {
    final lay = layout;
    if (lay == null) return 'Configura tu carpeta Emulation en Ajustes.';
    final err = await launcher.launch(g, lay, settings);
    if (err == null) {
      recents = [g.key, ...recents.where((k) => k != g.key)].take(30).toList();
      settings.recents = recents;
      notifyListeners();
    }
    return err;
  }

  bool hasLocal(Game g) =>
      library[g.platform]?.any((l) => l.fileName == g.fileName) ?? false;

  Future<void> connect(ServerAddress address, String pin, {bool silent = false}) async {
    connecting = true;
    if (!silent) connectError = null;
    notifyListeners();
    final c = RetroClient(address, pin);
    try {
      final info = await c.info().timeout(const Duration(seconds: 5));
      final named = ServerAddress(
          info['name'] as String? ?? address.name, address.host, address.port);
      client?.close();
      client = RetroClient(named, pin);
      connectedToSelf = info['id'] == settings.instanceId;
      c.close();
      settings.rememberServer(address.host, address.port, pin);
      remoteLibrary = await client!.library();
    } catch (e) {
      c.close();
      if (!silent) connectError = '$e';
      appLog.warn('No se pudo conectar a ${address.host}:${address.port}', e);
    }
    connecting = false;
    notifyListeners();
  }

  Future<void> refreshRemote() async {
    final c = client;
    if (c == null) return;
    try {
      remoteLibrary = await c.library();
    } catch (e) {
      connectError = '$e';
    }
    notifyListeners();
  }

  void disconnect() {
    client?.close();
    client = null;
    connectedToSelf = false;
    remoteLibrary = {};
    notifyListeners();
  }
}

/// Da acceso al [AppState] desde cualquier widget.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
      : super(notifier: state);

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  static AppState read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
