import 'dart:io';

import 'package:path/path.dart' as p;

import '../compat/external_installs.dart';
import 'platforms.dart';

/// Estructura de carpetas de una biblioteca de RetroHub:
///   {raíz}/roms/{plataforma}
///   {raíz}/bios
///   {raíz}/saves/{emulador}/saves|states
///   {raíz}/storage/downloaded_media/{plataforma}/covers|screenshots|titlescreens
///   {raíz}/storage/retrohub   (metadatos, cachés y registros de RetroHub)
class LibraryLayout {
  final String root;
  const LibraryLayout(this.root);

  String get roms => p.join(root, 'roms');
  String get bios => p.join(root, 'bios');
  String get saves => p.join(root, 'saves');
  String get media => p.join(root, 'storage', 'downloaded_media');
  String get launchers => p.join(root, 'tools', 'launchers');

  /// Datos propios de RetroHub (metadatos, cachés, registros).
  String get appData => p.join(root, 'storage', 'retrohub');
  String metadataFile(String platform) => p.join(appData, 'metadata', '$platform.json');

  /// Carpeta donde se guardan copias antes de sobrescribir un save.
  String get history => p.join(saves, '.retrohub_history');

  String area(String name) => switch (name) {
        'roms' => roms,
        'bios' => bios,
        'saves' => saves,
        _ => throw ArgumentError('Área desconocida: $name'),
      };

  Future<bool> isValid() => Directory(roms).exists();

  /// Carpetas que faltan para tener la estructura completa.
  Future<List<String>> missingFolders({bool allPlatforms = true}) async {
    final missing = <String>[];
    for (final dir in plannedFolders(allPlatforms: allPlatforms)) {
      if (!await Directory(dir).exists()) missing.add(dir);
    }
    return missing;
  }

  List<String> plannedFolders({bool allPlatforms = true}) => [
        roms,
        bios,
        saves,
        media,
        appData,
        if (allPlatforms)
          for (final id in kPlatforms.keys) p.join(roms, id),
      ];

  /// Crea la estructura (no toca nada que ya exista). Devuelve cuántas
  /// carpetas se crearon.
  Future<int> createStructure({bool allPlatforms = true}) async {
    var created = 0;
    for (final dir in await missingFolders(allPlatforms: allPlatforms)) {
      await Directory(dir).create(recursive: true);
      created++;
    }
    final readme = File(p.join(roms, 'LEEME.txt'));
    if (!await readme.exists()) {
      await readme.writeAsString(
          'Coloca cada juego en la carpeta de su plataforma, por ejemplo:\n'
          '  roms/snes/Super Mario World.sfc\n'
          '  roms/psx/Final Fantasy VII.chd\n'
          'Las BIOS van en la carpeta bios/ y las partidas en saves/.\n'
          'Creado por RetroHub.\n');
    }
    return created;
  }
}

bool get isDesktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

/// Ubicación sugerida para crear una biblioteca nueva.
String defaultLibraryRoot() {
  final env = Platform.environment;
  if (Platform.isAndroid) return '/storage/emulated/0/Emulation';
  if (Platform.isWindows) {
    return p.join(env['USERPROFILE'] ?? 'C:\\', 'Emulation');
  }
  return p.join(env['HOME'] ?? '/', 'Emulation');
}

/// Intenta encontrar una biblioteca existente automáticamente.
Future<String?> detectEmulationRoot() async {
  final candidates = <String>[
    ...await ExternalInstalls.declaredLibraryRoots(),
    defaultLibraryRoot(),
  ];
  for (final c in candidates) {
    try {
      if (await Directory(p.join(c, 'roms')).exists()) return c;
    } catch (_) {}
  }
  return null;
}
