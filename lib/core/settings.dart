import 'dart:io';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  final SharedPreferences _prefs;
  AppSettings._(this._prefs);

  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final s = AppSettings._(prefs);
    if (prefs.getString('serverPin') == null) {
      await prefs.setString('serverPin', generatePin());
    }
    if (prefs.getString('instanceId') == null) {
      final r = Random.secure();
      final id = List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
      await prefs.setString('instanceId', id);
    }
    return s;
  }

  static String generatePin() =>
      (Random.secure().nextInt(9000) + 1000).toString();

  /// Identificador único de esta instalación (para detectar que un
  /// cliente se conectó a su propio servidor).
  String get instanceId => _prefs.getString('instanceId') ?? '';

  String? get emulationRoot => _prefs.getString('emulationRoot');
  set emulationRoot(String? v) => v == null
      ? _prefs.remove('emulationRoot')
      : _prefs.setString('emulationRoot', v);

  String get deviceName {
    final v = _prefs.getString('deviceName');
    if (v != null && v.isNotEmpty) return v;
    try {
      return Platform.localHostname;
    } catch (_) {
      return Platform.operatingSystem;
    }
  }

  set deviceName(String v) => _prefs.setString('deviceName', v);

  int get serverPort => _prefs.getInt('serverPort') ?? 8787;
  set serverPort(int v) => _prefs.setInt('serverPort', v);

  String get serverPin => _prefs.getString('serverPin') ?? '';
  set serverPin(String v) => _prefs.setString('serverPin', v);

  bool get autoStartServer => _prefs.getBool('autoStartServer') ?? true;
  set autoStartServer(bool v) => _prefs.setBool('autoStartServer', v);

  String? get lastServerHost => _prefs.getString('lastServerHost');
  int? get lastServerPort => _prefs.getInt('lastServerPort');
  String? get lastServerPin => _prefs.getString('lastServerPin');

  void rememberServer(String host, int port, String pin) {
    _prefs.setString('lastServerHost', host);
    _prefs.setInt('lastServerPort', port);
    _prefs.setString('lastServerPin', pin);
  }

  // Credenciales de IGDB (app de Twitch) para el scraper.
  String get igdbClientId => _prefs.getString('igdbClientId') ?? '';
  set igdbClientId(String v) => _prefs.setString('igdbClientId', v);
  String get igdbClientSecret => _prefs.getString('igdbClientSecret') ?? '';
  set igdbClientSecret(String v) => _prefs.setString('igdbClientSecret', v);
  bool get hasIgdb => igdbClientId.isNotEmpty && igdbClientSecret.isNotEmpty;

  /// Comando personalizado para lanzar juegos de una plataforma ({rom}).
  String launchCommand(String platform) => _prefs.getString('launch.$platform') ?? '';
  void setLaunchCommand(String platform, String cmd) => cmd.trim().isEmpty
      ? _prefs.remove('launch.$platform')
      : _prefs.setString('launch.$platform', cmd.trim());

  // Favoritos y recientes ("plataforma/archivo").
  Set<String> get favorites => (_prefs.getStringList('favorites') ?? const []).toSet();
  set favorites(Set<String> v) => _prefs.setStringList('favorites', v.toList());
  List<String> get recents => _prefs.getStringList('recents') ?? const [];
  set recents(List<String> v) => _prefs.setStringList('recents', v);

  int? get lastSaveSync => _prefs.getInt('lastSaveSync');
  set lastSaveSync(int? v) =>
      v == null ? _prefs.remove('lastSaveSync') : _prefs.setInt('lastSaveSync', v);
}
