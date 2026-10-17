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
    return s;
  }

  static String generatePin() =>
      (Random.secure().nextInt(9000) + 1000).toString();

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

  int? get lastSaveSync => _prefs.getInt('lastSaveSync');
  set lastSaveSync(int? v) =>
      v == null ? _prefs.remove('lastSaveSync') : _prefs.setInt('lastSaveSync', v);
}
