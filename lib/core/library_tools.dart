import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../scrape/libretro.dart';
import 'models.dart';

// ---------------------------------------------------------------------------
// Duplicados
// ---------------------------------------------------------------------------

class DuplicateGroup {
  final String platform;
  final String title;
  final List<Game> games;

  /// true si además tienen exactamente el mismo tamaño (casi seguro idénticos).
  final bool sameSize;
  DuplicateGroup(this.platform, this.title, this.games, this.sameSize);

  int get wastedBytes {
    final sizes = games.map((g) => g.size).toList()..sort();
    return sizes.take(sizes.length - 1).fold(0, (s, x) => s + x);
  }
}

/// Agrupa juegos de la misma plataforma con el mismo nombre normalizado
/// (ignorando región, versión y etiquetas).
List<DuplicateGroup> findDuplicates(Map<String, List<Game>> library) {
  final groups = <DuplicateGroup>[];
  for (final entry in library.entries) {
    final byName = <String, List<Game>>{};
    for (final g in entry.value) {
      final key = normalizeGameName(g.title);
      if (key.isEmpty) continue;
      byName.putIfAbsent(key, () => []).add(g);
    }
    for (final list in byName.values) {
      if (list.length < 2) continue;
      final sameSize = list.map((g) => g.size).toSet().length == 1;
      groups.add(DuplicateGroup(entry.key, list.first.title, list, sameSize));
    }
  }
  groups.sort((a, b) => b.wastedBytes.compareTo(a.wastedBytes));
  return groups;
}

// ---------------------------------------------------------------------------
// Verificación de BIOS (System.dat de libretro)
// ---------------------------------------------------------------------------

class BiosEntry {
  final String name; // puede incluir subcarpeta, ej. "pcsx2/bios/x.bin"
  final int size;
  final String md5;
  const BiosEntry(this.name, this.size, this.md5);
  String get baseName => p.basename(name).toLowerCase();
}

/// Lee System.dat: líneas `comment "Sistema"` seguidas de `rom ( name ... md5 ... )`.
Map<String, List<BiosEntry>> parseSystemDat(String text) {
  final out = <String, List<BiosEntry>>{};
  String? current;
  final commentRe = RegExp(r'^\s*comment\s+"([^"]+)"\s*$');
  final romRe = RegExp(
      r'rom\s*\(\s*name\s+(?:"([^"]+)"|(\S+))\s+size\s+(\d+).*?md5\s+([0-9a-fA-F]{32})');
  for (final line in text.split('\n')) {
    final c = commentRe.firstMatch(line);
    if (c != null) {
      current = c.group(1);
      continue;
    }
    final r = romRe.firstMatch(line);
    if (r != null && current != null) {
      out.putIfAbsent(current, () => []).add(BiosEntry(
            r.group(1) ?? r.group(2)!,
            int.parse(r.group(3)!),
            r.group(4)!.toLowerCase(),
          ));
    }
  }
  return out;
}

/// Sistemas de System.dat que corresponden a cada carpeta de plataforma.
const Map<String, List<String>> kBiosSystems = {
  'psx': ['Sony - PlayStation'],
  'ps2': ['Sony - PlayStation 2'],
  'psp': ['Sony - PlayStation Portable'],
  'nds': ['Nintendo - Nintendo DS'],
  'gba': ['Nintendo - Game Boy Advance'],
  'gb': ['Nintendo - Gameboy'],
  'gbc': ['Nintendo - Gameboy Color'],
  'gc': ['Nintendo - GameCube'],
  'nes': ['Nintendo - Famicom Disk System'],
  'famicom': ['Nintendo - Famicom Disk System'],
  'segacd': ['Sega - Mega CD - Sega CD'],
  'saturn': ['Sega - Saturn'],
  'dreamcast': ['Sega - Dreamcast'],
  'naomi': ['Sega - Dreamcast-based Arcade'],
  'atomiswave': ['Sega - Dreamcast-based Arcade'],
  'mastersystem': ['Sega - Master System - Mark III'],
  'genesis': ['Sega - Mega Drive - Genesis'],
  'megadrive': ['Sega - Mega Drive - Genesis'],
  'gamegear': ['Sega - Game Gear'],
  'pcengine': ['NEC - PC Engine - TurboGrafx 16 - SuperGrafx'],
  'tg16': ['NEC - PC Engine - TurboGrafx 16 - SuperGrafx'],
  '3do': ['3DO Company, The - 3DO'],
  'neogeo': ['Arcade'],
  'arcade': ['Arcade'],
  'fbneo': ['Arcade'],
  'mame': ['Arcade'],
  'atarilynx': ['Atari - Lynx'],
  'dos': ['DOS'],
  'scummvm': ['ScummVM'],
};

enum BiosStatus { ok, wrong, missing }

class BiosReport {
  final String platform;
  final List<(BiosEntry, String)> found; // (esperado, ruta encontrada)
  final List<(BiosEntry, String)> wrongHash; // mismo nombre, otro contenido
  final List<BiosEntry> expected;
  BiosReport(this.platform, this.found, this.wrongHash, this.expected);

  BiosStatus get status => found.isNotEmpty
      ? BiosStatus.ok
      : wrongHash.isNotEmpty
          ? BiosStatus.wrong
          : BiosStatus.missing;
}

/// Calcula el MD5 de los archivos de bios/ y los compara con System.dat.
class BiosChecker {
  static const _url =
      'https://raw.githubusercontent.com/libretro/libretro-database/master/dat/System.dat';

  Future<String> loadSystemDat(String cacheDir) async {
    final file = File(p.join(cacheDir, 'System.dat'));
    try {
      final fresh = await file.exists() &&
          DateTime.now().difference(await file.lastModified()).inDays < 30;
      if (!fresh) {
        final res = await http.get(Uri.parse(_url)).timeout(const Duration(seconds: 30));
        if (res.statusCode == 200) {
          await file.parent.create(recursive: true);
          await file.writeAsString(res.body);
          return res.body;
        }
      }
    } catch (_) {}
    if (await file.exists()) return file.readAsString();
    throw Exception('No se pudo descargar la lista de BIOS de libretro (sin conexión).');
  }

  Future<List<BiosReport>> check({
    required String biosDir,
    required String cacheDir,
    required Iterable<String> platforms,
    void Function(String status)? onProgress,
  }) async {
    final dat = parseSystemDat(await loadSystemDat(cacheDir));
    onProgress?.call('Calculando huellas de tus BIOS...');

    final byMd5 = <String, String>{};
    final byName = <String, List<String>>{};
    final dir = Directory(biosDir);
    if (await dir.exists()) {
      await for (final e in dir.list(recursive: true, followLinks: false)) {
        if (e is! File) continue;
        final rel = p.relative(e.path, from: biosDir).replaceAll('\\', '/');
        byName.putIfAbsent(p.basename(e.path).toLowerCase(), () => []).add(rel);
        try {
          if (await e.length() > 64 * 1024 * 1024) continue;
          final digest = await md5.bind(e.openRead()).first;
          byMd5[digest.toString()] = rel;
        } catch (_) {}
      }
    }

    final reports = <BiosReport>[];
    for (final platform in platforms) {
      final systems = kBiosSystems[platform];
      if (systems == null) continue;
      final expected = [for (final s in systems) ...?dat[s]];
      if (expected.isEmpty) continue;
      final found = <(BiosEntry, String)>[];
      final wrong = <(BiosEntry, String)>[];
      for (final e in expected) {
        final hit = byMd5[e.md5];
        if (hit != null) {
          found.add((e, hit));
        } else if (byName[e.baseName] != null) {
          wrong.add((e, byName[e.baseName]!.first));
        }
      }
      reports.add(BiosReport(platform, found, wrong, expected));
    }
    return reports;
  }
}
