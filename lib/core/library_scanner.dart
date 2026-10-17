import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import 'layout.dart';
import 'models.dart';
import 'platforms.dart';

/// Extensiones que NO son juegos (saves, states, textos, imágenes...).
const _ignoredExt = {
  '.txt', '.srm', '.sav', '.state', '.frz', '.auto', '.png', '.jpg', '.jpeg',
  '.xml', '.cfg', '.ini', '.db', '.dat', '.nfo', '.md', '.lnk', '.url',
  '.bak', '.tmp', '.retrohub_tmp', '.mcr', '.mcd', '.dsv', '.ss0', '.ss1',
};
final _stateRe = RegExp(r'\.(state|ss)\d*$', caseSensitive: false);

/// Subcarpetas que no son juegos.
const _ignoredDirs = {
  'media', 'images', 'videos', 'manuals', 'downloaded_media', 'shortcuts',
};

/// Prioridad de tipos de imagen.
const _mediaTypes = ['covers', '3dboxes', 'miximages', 'screenshots', 'titlescreens'];

/// Escanea roms/ en un isolate aparte para no congelar la interfaz.
Future<Map<String, List<Game>>> scanLibrary(LibraryLayout layout) {
  final root = layout.root;
  return Isolate.run(() => _scan(LibraryLayout(root)));
}

Future<Map<String, List<Game>>> _scan(LibraryLayout layout) async {
  final result = <String, List<Game>>{};
  final romsDir = Directory(layout.roms);
  if (!await romsDir.exists()) return result;

  final seenRealPaths = <String>{};
  await for (final entity in romsDir.list(followLinks: false)) {
    if (entity is File) continue;
    final platform = p.basename(entity.path);
    if (platform.startsWith('.')) continue;

    // Puede haber alias (enlaces) entre carpetas; evitamos duplicados.
    String real;
    try {
      real = await Directory(entity.path).resolveSymbolicLinks();
    } catch (_) {
      continue;
    }
    if (!seenRealPaths.add(real.toLowerCase())) continue;

    final games = await _scanPlatform(layout, platform, Directory(real));
    if (games.isNotEmpty) result[platform] = games;
  }

  final sortedKeys = result.keys.toList()..sort(comparePlatforms);
  return {for (final k in sortedKeys) k: result[k]!};
}

Future<List<Game>> _scanPlatform(
    LibraryLayout layout, String platform, Directory dir) async {
  final entries = <FileSystemEntity>[];
  try {
    await for (final e in dir.list(followLinks: true)) {
      entries.add(e);
    }
  } catch (_) {
    return const [];
  }

  final names = entries.map((e) => p.basename(e.path).toLowerCase()).toSet();
  final hasCue = names.any((n) => n.endsWith('.cue'));
  final hasM3u = names.any((n) => n.endsWith('.m3u'));
  final media = _MediaIndex.load(layout, platform);
  final metas = _loadMeta(layout, platform);

  final games = <Game>[];
  for (final e in entries) {
    final name = p.basename(e.path);
    final lower = name.toLowerCase();
    if (name.startsWith('.')) continue;

    if (e is Directory) {
      if (_ignoredDirs.contains(lower)) continue;
      final (title, tags) = parseTitle(name, isFolder: true);
      games.add(Game(
        platform: platform,
        fileName: name,
        title: title,
        tags: tags,
        size: await _dirSize(e),
        isFolder: true,
        localPath: e.path,
        coverFile: media.find(name),
        meta: metas[name],
      ));
      continue;
    }
    if (e is! File) continue;

    final ext = p.extension(lower);
    if (_ignoredExt.contains(ext) || _stateRe.hasMatch(lower)) continue;
    if (lower == 'systeminfo.txt' || lower == 'metadata.txt') continue;
    // Juegos en .cue/.bin: mostramos solo el .cue.
    if (hasCue && ext == '.bin') continue;
    // Si hay .m3u (multidisco), ocultamos los discos sueltos.
    if (hasM3u && (ext == '.cue' || ext == '.chd') &&
        RegExp(r'\((disc|disk|cd)\s*\d', caseSensitive: false).hasMatch(name)) {
      continue;
    }

    int size = 0;
    try {
      size = await e.length();
    } catch (_) {}
    final (title, tags) = parseTitle(name);
    games.add(Game(
      platform: platform,
      fileName: name,
      title: title,
      tags: tags,
      size: size,
      localPath: e.path,
      coverFile: media.find(p.basenameWithoutExtension(name)),
      meta: metas[name],
    ));
  }

  games.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  return games;
}

/// Metadatos guardados por el scraper (storage/retrohub/metadata/{platform}.json).
Map<String, GameMeta> _loadMeta(LibraryLayout layout, String platform) {
  try {
    final f = File(layout.metadataFile(platform));
    if (!f.existsSync()) return const {};
    final raw = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    return raw.map((k, v) =>
        MapEntry(k, GameMeta.fromJson(Map<String, dynamic>.from(v as Map))));
  } catch (_) {
    return const {};
  }
}

Future<int> _dirSize(Directory dir) async {
  var total = 0;
  try {
    await for (final f in dir.list(recursive: true, followLinks: false)) {
      if (f is File) total += await f.length();
    }
  } catch (_) {}
  return total;
}

/// Índice de imágenes descargadas para una plataforma.
class _MediaIndex {
  final Map<String, String> _byName;
  _MediaIndex(this._byName);

  static _MediaIndex load(LibraryLayout layout, String platform) {
    final map = <String, String>{};
    // Recorremos de menor a mayor prioridad para que "covers" sobrescriba.
    for (final type in _mediaTypes.reversed) {
      final dir = Directory(p.join(layout.media, platform, type));
      try {
        if (!dir.existsSync()) continue;
        for (final f in dir.listSync()) {
          if (f is File) {
            map[p.basenameWithoutExtension(f.path).toLowerCase()] = f.path;
          }
        }
      } catch (_) {}
    }
    return _MediaIndex(map);
  }

  String? find(String baseName) => _byName[baseName.toLowerCase()];
}
