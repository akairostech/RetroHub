import 'dart:io';

import 'package:path/path.dart' as p;

import 'file_hash.dart';
import 'models.dart';

/// Lista recursivamente los archivos bajo [root] con rutas relativas "/".
/// Omite archivos/carpetas ocultos (empiezan por ".") como los que
/// otras herramientas usan para su sincronización (.cloud, .hash, .temp...) y el historial.
Future<List<FileEntry>> listTree(
  String root, {
  HashCache? hashes,
  bool skipHidden = true,
}) async {
  final dir = Directory(root);
  final out = <FileEntry>[];
  if (!await dir.exists()) return out;

  await for (final e in dir.list(recursive: true, followLinks: false)) {
    if (e is! File) continue;
    final rel = toPosix(p.relative(e.path, from: root));
    if (skipHidden && rel.split('/').any((s) => s.startsWith('.'))) continue;
    final name = p.basename(rel).toLowerCase();
    if (name == 'desktop.ini' || name.endsWith('.retrohub_tmp')) continue;
    try {
      final st = await e.stat();
      final hash = hashes != null ? await hashes.sha1Of(e) : null;
      out.add(FileEntry(rel, st.size, st.modified.millisecondsSinceEpoch, hash));
    } catch (_) {
      // Archivo bloqueado o borrado durante el escaneo: lo saltamos.
    }
  }
  out.sort((a, b) => a.path.compareTo(b.path));
  return out;
}

/// Copia [file] al historial antes de sobrescribirlo.
Future<void> backupToHistory(File file, String historyRoot, String rel) async {
  if (!await file.exists()) return;
  final stamp = DateTime.now()
      .toIso8601String()
      .replaceAll(':', '-')
      .split('.')
      .first;
  final target = safeJoin(historyRoot, '$rel.$stamp');
  if (target == null) return;
  await Directory(p.dirname(target)).create(recursive: true);
  await file.copy(target);
}

/// Reemplaza [dest] con [tmp] de forma segura (Windows no permite
/// renombrar encima de un archivo existente).
Future<void> replaceFile(File tmp, File dest) async {
  if (await dest.exists()) await dest.delete();
  await tmp.rename(dest.path);
}
