// Compatibilidad con instalaciones de terceros.
//
// RetroHub usa su propia estructura de carpetas (ver core/layout.dart), que es
// la misma convención que usan otras herramientas de emulación populares. Este
// archivo es el ÚNICO lugar del código que conoce rutas y nombres de archivos
// de esas herramientas, para que RetroHub pueda detectar una biblioteca ya
// existente y reutilizar la configuración de emuladores que el usuario tenga.
// Si nada de esto existe, RetroHub funciona igual con su propia estructura.

import 'dart:io';

import 'package:path/path.dart' as p;

class ExternalInstalls {
  ExternalInstalls._();

  static Map<String, String> get _env => Platform.environment;

  /// Carpetas raíz declaradas por un instalador de emuladores existente.
  static Future<List<String>> declaredLibraryRoots() async {
    final out = <String>[];
    try {
      if (Platform.isWindows) {
        final appData = _env['APPDATA'];
        if (appData != null) {
          final f = File(p.join(appData, 'EmuDeck', 'settings.ps1'));
          if (await f.exists()) {
            final m = RegExp(r'\$emulationPath\s*=\s*"([^"]+)"')
                .firstMatch(await f.readAsString());
            if (m != null) out.add(m.group(1)!);
          }
        }
      } else {
        final home = _env['HOME'];
        if (home != null) {
          final f = File(p.join(home, 'emudeck', 'settings.sh'));
          if (await f.exists()) {
            final m = RegExp(r'^emulationPath=["]?([^"\n]+)["]?', multiLine: true)
                .firstMatch(await f.readAsString());
            if (m != null) out.add(m.group(1)!.trim());
          }
        }
      }
    } catch (_) {}
    return out;
  }

  /// Ubicaciones donde puede haber un perfil de lanzamiento instalado
  /// (sistemas + reglas para encontrar emuladores).
  static List<LaunchProfileLocation> launchProfileLocations() {
    final out = <LaunchProfileLocation>[];
    final osName = Platform.isWindows ? 'windows' : 'linux';
    final dirs = <String>[];
    if (Platform.isWindows) {
      final appData = _env['APPDATA'];
      if (appData != null) dirs.add(p.join(appData, 'EmuDeck', 'EmulationStation-DE'));
      final local = _env['LOCALAPPDATA'];
      if (local != null) dirs.add(p.join(local, 'Programs', 'ES-DE'));
    } else {
      final home = _env['HOME'];
      if (home != null) dirs.add(p.join(home, 'Applications', 'ES-DE'));
    }
    for (final dir in dirs) {
      final userDir = Directory(p.join(dir, 'ES-DE')).existsSync()
          ? p.join(dir, 'ES-DE')
          : p.join(_env['HOME'] ?? _env['USERPROFILE'] ?? dir, 'ES-DE');
      out.add(LaunchProfileLocation(
        installDir: dir,
        userDir: userDir,
        systemsFiles: [
          p.join(dir, 'resources', 'systems', osName, 'es_systems.xml'),
          p.join(userDir, 'custom_systems', 'es_systems.xml'),
        ],
        rulesFiles: [
          p.join(userDir, 'custom_systems', 'es_find_rules.xml'),
          p.join(dir, 'resources', 'systems', osName, 'es_find_rules.xml'),
        ],
      ));
    }
    return out;
  }

  /// Variable que en los perfiles instalados apunta a su carpeta de instalación.
  static const installDirVariable = '%ESPATH%';

  /// Archivo donde se guarda el emulador elegido para un sistema.
  static String chosenEmulatorFile(String userDir, String system) =>
      p.join(userDir, 'gamelists', system, 'gamelist.xml');

  /// RetroArch instalado por el instalador de emuladores en Windows.
  static String windowsRetroArchDir() =>
      p.join(_env['APPDATA'] ?? '', 'EmuDeck', 'Emulators', 'RetroArch');
}

class LaunchProfileLocation {
  final String installDir;
  final String userDir;
  final List<String> systemsFiles; // el último tiene prioridad
  final List<String> rulesFiles; // el primero tiene prioridad
  const LaunchProfileLocation({
    required this.installDir,
    required this.userDir,
    required this.systemsFiles,
    required this.rulesFiles,
  });
}
