import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Calcula SHA-1 de archivos y recuerda el resultado mientras el
/// tamaño y la fecha de modificación no cambien.
class HashCache {
  final File _file;
  final Map<String, Map<String, dynamic>> _entries;
  Timer? _saveTimer;

  HashCache._(this._file, this._entries);

  /// Caché sin persistencia previa (útil en pruebas).
  HashCache.at(File file) : this._(file, {});

  static Future<HashCache> open() async {
    final dir = await getApplicationSupportDirectory();
    final file = File(p.join(dir.path, 'hash_cache.json'));
    var entries = <String, Map<String, dynamic>>{};
    try {
      if (await file.exists()) {
        final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        entries = raw.map((k, v) => MapEntry(k, Map<String, dynamic>.from(v as Map)));
      }
    } catch (_) {}
    return HashCache._(file, entries);
  }

  Future<String> sha1Of(File file) async {
    final stat = await file.stat();
    final key = file.absolute.path;
    final cached = _entries[key];
    final mtime = stat.modified.millisecondsSinceEpoch;
    if (cached != null && cached['size'] == stat.size && cached['mtime'] == mtime) {
      return cached['sha1'] as String;
    }
    final digest = await sha1.bind(file.openRead()).first;
    final hex = digest.toString();
    _entries[key] = {'size': stat.size, 'mtime': mtime, 'sha1': hex};
    _scheduleSave();
    return hex;
  }

  void invalidate(String path) {
    _entries.remove(File(path).absolute.path);
    _scheduleSave();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), () async {
      try {
        await _file.parent.create(recursive: true);
        await _file.writeAsString(jsonEncode(_entries));
      } catch (_) {}
    });
  }
}
