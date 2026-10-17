import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../core/models.dart';

/// Normaliza un nombre de juego para compararlo:
/// "Legend of Zelda, The - A Link to the Past (USA) [!]" -> "legendofzeldaalinktothepast"
String normalizeGameName(String name) {
  var s = name.toLowerCase();
  s = s.replaceAll(RegExp(r'[\(\[][^\)\]]*[\)\]]'), ' ');
  s = s.replaceFirst(RegExp(r'^\d{3,5}\s*-\s*'), '');
  s = s.replaceAll('&', 'and');
  // Artículos al principio o al final ("Zelda, The").
  s = s.replaceAll(RegExp(r',\s*(the|a|an)\b'), ' ');
  s = s.replaceAll(RegExp(r'^(the|a|an)\s+'), '');
  s = s.replaceAll(RegExp(r'[^a-z0-9]'), '');
  return s;
}

/// Entrada de un archivo .dat de libretro-database (metadat/*).
class DatEntry {
  final String name;
  final String? crc;
  final Map<String, String> fields;
  DatEntry(this.name, this.crc, this.fields);
}

/// Lee un .dat estilo clrmamepro:
///   game ( comment "Nombre (USA)" developer "X" rom ( crc 1234ABCD ) )
List<DatEntry> parseDat(String text) {
  final out = <DatEntry>[];
  final block = RegExp(r'game \((.*?)\n\)', dotAll: true);
  final field = RegExp(r'^\s*(\w+)\s+(?:"([^"]*)"|(\S+))\s*$', multiLine: true);
  final crcRe = RegExp(r'crc\s+([0-9A-Fa-f]{8})');
  for (final m in block.allMatches(text)) {
    final body = m.group(1)!;
    String? name;
    final fields = <String, String>{};
    for (final f in field.allMatches(body)) {
      final key = f.group(1)!;
      final value = f.group(2) ?? f.group(3)!;
      if (key == 'comment' || key == 'name') {
        name ??= value;
      } else if (key != 'rom') {
        fields[key] = value;
      }
    }
    if (name == null) continue;
    out.add(DatEntry(name, crcRe.firstMatch(body)?.group(1)?.toUpperCase(), fields));
  }
  return out;
}

/// Prioridad de región cuando hay varias versiones del mismo juego.
int regionRank(String name) {
  final n = name.toLowerCase();
  if (n.contains('(usa') || n.contains('(world')) return 0;
  if (n.contains('(europe') || n.contains('(spain')) return 1;
  if (n.contains('(japan')) return 3;
  return 2;
}

/// Base de datos de un sistema: une developer/publisher/genre/year/users.
class LibretroSystemDb {
  final Map<String, Map<String, String>> _byName = {}; // nombre exacto -> campos
  final Map<String, String> _bestByNorm = {}; // normalizado -> nombre exacto
  final Map<String, String> _byCrc = {}; // crc -> nombre exacto

  void addDat(List<DatEntry> entries) {
    for (final e in entries) {
      _byName.putIfAbsent(e.name, () => {}).addAll(e.fields);
      if (e.crc != null) _byCrc[e.crc!] = e.name;
      final norm = normalizeGameName(e.name);
      final current = _bestByNorm[norm];
      if (current == null || regionRank(e.name) < regionRank(current)) {
        _bestByNorm[norm] = e.name;
      }
    }
  }

  bool get isEmpty => _byName.isEmpty;

  /// Busca primero por CRC (exacto) y luego por nombre normalizado.
  String? findName({required String fileName, String? crc}) {
    if (crc != null && _byCrc.containsKey(crc)) return _byCrc[crc];
    return _bestByNorm[normalizeGameName(p.basenameWithoutExtension(fileName))] ??
        _bestByNorm[normalizeGameName(fileName)];
  }

  GameMeta? metaFor(String exactName) {
    final f = _byName[exactName];
    if (f == null) return null;
    return GameMeta(
      name: exactName.replaceAll(RegExp(r'\s*[\(\[].*$'), ''),
      developer: f['developer'],
      publisher: f['publisher'],
      genre: f['genre'],
      year: int.tryParse(f['releaseyear'] ?? ''),
      players: int.tryParse(f['users'] ?? ''),
      source: 'libretro',
    );
  }
}

/// Fuente sin cuenta: libretro-database (metadatos) + libretro-thumbnails (imágenes).
class LibretroSource {
  static const _kinds = ['developer', 'publisher', 'genre', 'releaseyear', 'maxusers'];
  static const _dbBase =
      'https://raw.githubusercontent.com/libretro/libretro-database/master/metadat';
  static const _thumbBase = 'https://thumbnails.libretro.com';

  final http.Client client;
  final String cacheDir;
  final Map<String, LibretroSystemDb> _dbs = {};
  final Map<String, Set<String>> _thumbIndex = {};

  LibretroSource(this.client, this.cacheDir);

  /// Descarga (o lee del caché, 30 días) los .dat de un sistema.
  Future<LibretroSystemDb> systemDb(String system) async {
    final cached = _dbs[system];
    if (cached != null) return cached;
    final db = LibretroSystemDb();
    for (final kind in _kinds) {
      final file = File(p.join(cacheDir, kind, '$system.dat'));
      String? text;
      try {
        final fresh = await file.exists() &&
            DateTime.now().difference(await file.lastModified()).inDays < 30;
        if (fresh) {
          text = await file.readAsString();
        } else {
          final url = '$_dbBase/$kind/${Uri.encodeComponent(system)}.dat';
          final res = await client.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
          if (res.statusCode == 200) {
            text = res.body;
            await file.parent.create(recursive: true);
            await file.writeAsString(text);
          } else if (await file.exists()) {
            text = await file.readAsString();
          }
        }
      } catch (_) {
        if (await file.exists()) text = await file.readAsString();
      }
      if (text != null) db.addDat(parseDat(text));
    }
    _dbs[system] = db;
    return db;
  }

  /// URL de una imagen de libretro-thumbnails.
  /// [type]: Named_Boxarts, Named_Snaps o Named_Titles.
  static String thumbnailUrl(String system, String type, String gameName) {
    final safe = gameName.replaceAll(RegExp(r'[&*/:`<>?\\|"]'), '_');
    return '$_thumbBase/${Uri.encodeComponent(system)}/$type/${Uri.encodeComponent(safe)}.png';
  }

  /// Lista de nombres disponibles en libretro-thumbnails para un sistema y tipo
  /// (se usa cuando el juego no aparece en la base de datos).
  Future<Set<String>> thumbnailIndex(String system, String type) async {
    final key = '$system/$type';
    final cached = _thumbIndex[key];
    if (cached != null) return cached;
    final names = <String>{};
    try {
      final url = '$_thumbBase/${Uri.encodeComponent(system)}/$type/';
      final res = await client.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
      if (res.statusCode == 200) {
        for (final m in RegExp(r'href="([^"]+\.png)"').allMatches(res.body)) {
          names.add(Uri.decodeComponent(m.group(1)!).replaceAll(RegExp(r'\.png$'), ''));
        }
      }
    } catch (_) {}
    _thumbIndex[key] = names;
    return names;
  }

  /// Busca en el índice de imágenes el nombre que mejor coincide.
  static String? bestThumbnailMatch(Set<String> names, String fileName) {
    final target = normalizeGameName(p.basenameWithoutExtension(fileName));
    String? best;
    for (final n in names) {
      if (normalizeGameName(n) == target) {
        if (best == null || regionRank(n) < regionRank(best)) best = n;
      }
    }
    return best;
  }
}

/// CRC32 (para identificar ROMs pequeñas exactamente).
final Uint32List _crcTable = () {
  final t = Uint32List(256);
  for (var i = 0; i < 256; i++) {
    var c = i;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
    t[i] = c;
  }
  return t;
}();

Future<String> crc32OfFile(File file) async {
  var crc = 0xFFFFFFFF;
  await for (final chunk in file.openRead()) {
    for (final b in chunk) {
      crc = _crcTable[(crc ^ b) & 0xFF] ^ (crc >> 8);
    }
  }
  return ((crc ^ 0xFFFFFFFF) & 0xFFFFFFFF).toRadixString(16).toUpperCase().padLeft(8, '0');
}
