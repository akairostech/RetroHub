import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../core/app_log.dart';
import '../core/layout.dart';
import '../core/models.dart';
import '../core/platforms.dart';
import 'igdb.dart';
import 'libretro.dart';

class ScrapeOptions {
  bool images;
  bool metadata;
  bool onlyMissing;
  ScrapeOptions({this.images = true, this.metadata = true, this.onlyMissing = true});
}

/// Descarga carátulas, capturas y metadatos para los juegos de la biblioteca.
/// Las imágenes se guardan en la estructura estándar de media
/// (storage/downloaded_media/{plataforma}/covers|screenshots|titlescreens),
/// así otros frontends también pueden aprovecharlas.
class Scraper extends ChangeNotifier {
  final http.Client _http = http.Client();

  bool running = false;
  bool _cancel = false;
  int total = 0;
  int done = 0;
  int updated = 0;
  int notFound = 0;
  int errors = 0;
  String? current;
  String? summary;

  double? get progress => total == 0 ? null : done / total;

  void cancel() {
    _cancel = true;
    notifyListeners();
  }

  Future<void> run({
    required LibraryLayout layout,
    required List<Game> games,
    required ScrapeOptions options,
    IgdbSource? igdb,
  }) async {
    if (running) return;
    running = true;
    _cancel = false;
    total = games.length;
    done = updated = notFound = errors = 0;
    summary = null;
    notifyListeners();

    final libretro = LibretroSource(_http, p.join(layout.appData, 'cache', 'libretro'));
    final pending = <String, Map<String, GameMeta>>{};
    appLog.info('Scraper: ${games.length} juegos '
        '(fuentes: libretro${igdb != null ? ' + IGDB' : ''})');

    for (final g in games) {
      if (_cancel) break;
      current = '${platformInfo(g.platform).shortName} · ${g.title}';
      notifyListeners();
      try {
        final meta = await _scrapeGame(layout, g, options, libretro, igdb);
        if (meta != null) {
          pending.putIfAbsent(g.platform, () => {})[g.fileName] = meta;
          updated++;
        } else {
          notFound++;
        }
      } catch (e, st) {
        errors++;
        appLog.error('Scraper: falló ${g.platform}/${g.fileName}', e, st);
        // Si IGDB rechaza las credenciales no tiene sentido seguir intentándolo.
        if (e.toString().contains('credenciales rechazadas')) {
          igdb = null;
        }
      }
      done++;
      if (done % 15 == 0) await _saveMeta(layout, pending);
      notifyListeners();
    }
    await _saveMeta(layout, pending);

    summary = _cancel
        ? 'Cancelado: $updated actualizados de $done revisados'
        : 'Listo: $updated actualizados, $notFound sin coincidencias'
            '${errors > 0 ? ', $errors con error (ver Registro)' : ''}';
    appLog.info('Scraper: $summary');
    current = null;
    running = false;
    notifyListeners();
  }

  Future<GameMeta?> _scrapeGame(LibraryLayout layout, Game g, ScrapeOptions o,
      LibretroSource libretro, IgdbSource? igdb) async {
    final mediaDir = p.join(layout.media, g.platform);
    final coverExists = _existing(mediaDir, 'covers', g.mediaName) != null;
    final hasMeta = g.meta != null && !g.meta!.isEmpty;
    if (o.onlyMissing &&
        (!o.images || coverExists) &&
        (!o.metadata || (hasMeta && (igdb == null || g.meta!.description != null)))) {
      return null; // Ya tiene todo lo pedido.
    }

    // 1) libretro-database: identificar el juego y sus datos básicos.
    final system = platformInfo(g.platform).libretro;
    String? lrName;
    GameMeta? lrMeta;
    if (system != null) {
      final db = await libretro.systemDb(system);
      String? crc;
      final path = g.localPath;
      final ext = p.extension(g.fileName).toLowerCase();
      if (path != null && !g.isFolder && g.size <= 64 * 1024 * 1024 &&
          !const {'.zip', '.7z', '.rar', '.chd', '.cso', '.rvz'}.contains(ext)) {
        crc = await crc32OfFile(File(path));
      }
      lrName = db.findName(fileName: g.fileName, crc: crc);
      if (lrName != null) lrMeta = db.metaFor(lrName);
    }

    // 2) IGDB (opcional): descripción, valoración y portada si falta.
    IgdbResult? ig;
    if (igdb != null && (o.metadata || o.images)) {
      final wantsDesc = !(o.onlyMissing && g.meta?.description != null);
      if (wantsDesc || (o.images && !coverExists && system == null)) {
        ig = await igdb.search(g.platform, lrMeta?.name ?? g.title);
      }
    }

    // 3) Imágenes.
    var gotImage = false;
    if (o.images && system != null) {
      lrName ??= LibretroSource.bestThumbnailMatch(
          await libretro.thumbnailIndex(system, 'Named_Boxarts'), g.fileName);
    }
    if (o.images) {
      final targets = {
        'covers': (
          lrName == null ? null : LibretroSource.thumbnailUrl(system!, 'Named_Boxarts', lrName),
          ig?.coverUrl
        ),
        'screenshots': (
          lrName == null ? null : LibretroSource.thumbnailUrl(system!, 'Named_Snaps', lrName),
          ig?.screenshotUrl
        ),
        'titlescreens': (
          lrName == null ? null : LibretroSource.thumbnailUrl(system!, 'Named_Titles', lrName),
          null
        ),
      };
      for (final MapEntry(key: type, value: (primary, fallback)) in targets.entries) {
        if (o.onlyMissing && _existing(mediaDir, type, g.mediaName) != null) continue;
        for (final url in [primary, fallback]) {
          if (url == null) continue;
          if (await _download(url, p.join(mediaDir, type), g.mediaName)) {
            gotImage = true;
            break;
          }
        }
      }
    }

    // 4) Combinar metadatos (IGDB aporta descripción; libretro, datos exactos).
    GameMeta? meta;
    if (o.metadata) {
      final fresh = (lrMeta ?? const GameMeta()).mergedWith(ig?.meta);
      meta = o.onlyMissing && g.meta != null ? g.meta!.mergedWith(fresh) : fresh;
      if (meta.isEmpty && meta.name == null) meta = null;
    }
    if (meta == null && gotImage) return g.meta ?? const GameMeta(source: 'imágenes');
    return meta;
  }

  /// Busca una imagen existente con cualquier extensión.
  String? _existing(String mediaDir, String type, String name) {
    for (final ext in const ['.png', '.jpg', '.jpeg', '.webp']) {
      final f = File(p.join(mediaDir, type, '$name$ext'));
      if (f.existsSync()) return f.path;
    }
    return null;
  }

  Future<bool> _download(String url, String dir, String name) async {
    try {
      final res = await _http.get(Uri.parse(url)).timeout(const Duration(seconds: 40));
      final type = res.headers['content-type'] ?? '';
      if (res.statusCode != 200 || !type.startsWith('image/') || res.bodyBytes.length < 200) {
        return false;
      }
      final ext = type.contains('png') ? '.png' : '.jpg';
      await Directory(dir).create(recursive: true);
      // Reemplazar versiones anteriores con otra extensión.
      for (final old in const ['.png', '.jpg', '.jpeg', '.webp']) {
        final f = File(p.join(dir, '$name$old'));
        if (await f.exists()) await f.delete();
      }
      await File(p.join(dir, '$name$ext')).writeAsBytes(res.bodyBytes);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _saveMeta(LibraryLayout layout, Map<String, Map<String, GameMeta>> pending) async {
    for (final entry in pending.entries) {
      if (entry.value.isEmpty) continue;
      final file = File(layout.metadataFile(entry.key));
      var data = <String, dynamic>{};
      try {
        if (await file.exists()) {
          data = Map<String, dynamic>.from(jsonDecode(await file.readAsString()) as Map);
        }
      } catch (_) {}
      for (final g in entry.value.entries) {
        data[g.key] = g.value.toJson();
      }
      await file.parent.create(recursive: true);
      await file.writeAsString(const JsonEncoder.withIndent(' ').convert(data));
    }
    for (final m in pending.values) {
      m.clear();
    }
  }

  @override
  void dispose() {
    _http.close();
    super.dispose();
  }
}
