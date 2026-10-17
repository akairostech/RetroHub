import 'dart:io';

import 'package:path/path.dart' as p;

/// Rutas de la estructura estándar de EmuDeck:
///   {root}/roms/{platform}
///   {root}/bios
///   {root}/saves/{emulador}/saves|states
///   {root}/storage/downloaded_media/{platform}/covers  (carátulas de ES-DE)
class EmuLayout {
  final String root;
  const EmuLayout(this.root);

  String get roms => p.join(root, 'roms');
  String get bios => p.join(root, 'bios');
  String get saves => p.join(root, 'saves');
  String get media => p.join(root, 'storage', 'downloaded_media');

  /// Datos propios de RetroHub (metadatos, cachés, registros).
  String get appData => p.join(root, 'storage', 'retrohub');
  String metadataFile(String platform) =>
      p.join(appData, 'metadata', '$platform.json');

  /// Carpeta donde se guardan copias antes de sobrescribir un save.
  String get history => p.join(saves, '.retrohub_history');

  String area(String name) => switch (name) {
        'roms' => roms,
        'bios' => bios,
        'saves' => saves,
        _ => throw ArgumentError('Área desconocida: $name'),
      };

  Future<bool> isValid() => Directory(roms).exists();
}

bool get isDesktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

/// Intenta encontrar la carpeta Emulation de EmuDeck automáticamente.
Future<String?> detectEmulationRoot() async {
  final candidates = <String>[];
  try {
    final env = Platform.environment;
    if (Platform.isWindows) {
      final appData = env['APPDATA'];
      if (appData != null) {
        final f = File(p.join(appData, 'EmuDeck', 'settings.ps1'));
        if (await f.exists()) {
          final m = RegExp(r'\$emulationPath\s*=\s*"([^"]+)"')
              .firstMatch(await f.readAsString());
          if (m != null) candidates.add(m.group(1)!);
        }
      }
    } else if (Platform.isLinux || Platform.isMacOS) {
      final home = env['HOME'];
      if (home != null) {
        final f = File(p.join(home, 'emudeck', 'settings.sh'));
        if (await f.exists()) {
          final m = RegExp(r'^emulationPath=["]?([^"\n]+)["]?', multiLine: true)
              .firstMatch(await f.readAsString());
          if (m != null) candidates.add(m.group(1)!.trim());
        }
        candidates.add(p.join(home, 'Emulation'));
      }
    } else if (Platform.isAndroid) {
      candidates.add('/storage/emulated/0/Emulation');
    }
  } catch (_) {}

  for (final c in candidates) {
    try {
      if (await Directory(p.join(c, 'roms')).exists()) return c;
    } catch (_) {}
  }
  return null;
}
