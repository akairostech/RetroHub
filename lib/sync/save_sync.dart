import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/layout.dart';
import '../core/app_log.dart';
import '../core/file_hash.dart';
import '../core/file_tree.dart';
import '../core/models.dart';
import '../net/client.dart';

enum SyncAction { upload, download, conflict }

enum SyncItemState { pending, done, failed }

class SyncItem {
  final String path;
  final FileEntry? local;
  final FileEntry? remote;

  /// Acción elegida. En conflictos empieza como [SyncAction.conflict]
  /// y el usuario decide (o se usa la versión más reciente).
  SyncAction action;
  final bool isConflict;
  SyncItemState state = SyncItemState.pending;
  String? error;

  SyncItem(this.path, this.action, {this.local, this.remote})
      : isConflict = action == SyncAction.conflict;

  /// En un conflicto, ¿cuál es más reciente?
  SyncAction get newer =>
      (local?.mtime ?? 0) >= (remote?.mtime ?? 0) ? SyncAction.upload : SyncAction.download;

  String get emulator => path.split('/').first;
}

class SyncPlan {
  final List<SyncItem> items;
  final int unchanged;
  SyncPlan(this.items, this.unchanged);

  Iterable<SyncItem> get uploads => items.where((i) => i.action == SyncAction.upload);
  Iterable<SyncItem> get downloads => items.where((i) => i.action == SyncAction.download);
  Iterable<SyncItem> get conflicts => items.where((i) => i.isConflict);
  bool get hasUnresolved => items.any((i) => i.action == SyncAction.conflict);
}

/// Sincronización de partidas guardadas en dos sentidos con el servidor.
///
/// Para cada archivo se compara el hash local (L), el remoto (R) y el de la
/// última sincronización (B):
///   L == R              -> nada que hacer
///   solo cambió local   -> subir
///   solo cambió remoto  -> bajar
///   cambiaron ambos     -> conflicto (decide el usuario)
/// Nunca se borran archivos, y antes de sobrescribir se guarda una copia
/// en saves/.retrohub_history en ambos lados.
class SaveSync extends ChangeNotifier {
  final HashCache hashes;
  SaveSync(this.hashes);

  SyncPlan? plan;
  bool busy = false;
  String? status;
  String? error;

  Future<File> _baseFile(String serverKey) async {
    final dir = await getApplicationSupportDirectory();
    final id = sha1.convert(utf8.encode(serverKey)).toString().substring(0, 12);
    return File(p.join(dir.path, 'sync_base_$id.json'));
  }

  Future<Map<String, String>> _loadBase(String serverKey) async {
    try {
      final f = await _baseFile(serverKey);
      if (await f.exists()) {
        return Map<String, String>.from(jsonDecode(await f.readAsString()) as Map);
      }
    } catch (_) {}
    return {};
  }

  Future<void> _saveBase(String serverKey, Map<String, String> base) async {
    final f = await _baseFile(serverKey);
    await f.parent.create(recursive: true);
    await f.writeAsString(jsonEncode(base));
  }

  String _serverKey(RetroClient c) => '${c.server.name}@${c.server.host}';

  Future<void> analyze(RetroClient client, LibraryLayout layout) async {
    busy = true;
    error = null;
    plan = null;
    status = 'Calculando huellas de tus partidas...';
    notifyListeners();
    try {
      final local = {
        for (final f in await listTree(layout.saves, hashes: hashes)) f.path: f
      };
      status = 'Consultando el servidor...';
      notifyListeners();
      final remote = {
        for (final f in await client.tree('saves', hash: true)) f.path: f
      };
      final base = await _loadBase(_serverKey(client));

      final items = <SyncItem>[];
      var unchanged = 0;
      final paths = {...local.keys, ...remote.keys}.toList()..sort();
      for (final path in paths) {
        final l = local[path], r = remote[path];
        final b = base[path];
        if (l != null && r != null && l.sha1 == r.sha1) {
          base[path] = l.sha1!;
          unchanged++;
        } else if (l != null && r == null) {
          items.add(SyncItem(path, SyncAction.upload, local: l));
        } else if (l == null && r != null) {
          items.add(SyncItem(path, SyncAction.download, remote: r));
        } else if (l != null && r != null) {
          final SyncAction action;
          if (b == l.sha1) {
            action = SyncAction.download;
          } else if (b == r.sha1) {
            action = SyncAction.upload;
          } else {
            action = SyncAction.conflict;
          }
          items.add(SyncItem(path, action, local: l, remote: r));
        }
      }
      await _saveBase(_serverKey(client), base);
      plan = SyncPlan(items, unchanged);
      status = null;
      appLog.info('Partidas analizadas con ${client.server.name}: '
          '${plan!.uploads.length} subir, ${plan!.downloads.length} bajar, '
          '${plan!.conflicts.length} conflictos, $unchanged iguales '
          '(${local.length} locales, ${remote.length} en el servidor)');
    } catch (e, st) {
      error = 'No se pudo analizar: $e';
      status = null;
      appLog.error('Fallo al analizar partidas en ${layout.saves}', e, st);
    }
    busy = false;
    notifyListeners();
  }

  void resolve(SyncItem item, SyncAction action) {
    item.action = action;
    notifyListeners();
  }

  void resolveAllByNewest() {
    for (final i in plan?.conflicts ?? const <SyncItem>[]) {
      i.action = i.newer;
    }
    notifyListeners();
  }

  /// Aplica el plan (los conflictos sin resolver se saltan).
  Future<void> apply(RetroClient client, LibraryLayout layout) async {
    final current = plan;
    if (current == null) return;
    busy = true;
    error = null;
    notifyListeners();
    final base = await _loadBase(_serverKey(client));
    var n = 0;
    final todo = current.items
        .where((i) => i.action != SyncAction.conflict && i.state != SyncItemState.done)
        .toList();
    for (final item in todo) {
      n++;
      status = '${item.action == SyncAction.upload ? 'Subiendo' : 'Bajando'} '
          '$n de ${todo.length}: ${p.basename(item.path)}';
      notifyListeners();
      try {
        final localPath = safeJoin(layout.saves, item.path);
        if (localPath == null) throw 'Ruta inválida';
        final file = File(localPath);
        if (item.action == SyncAction.upload) {
          await client.uploadSave(item.path, file);
          base[item.path] = await hashes.sha1Of(file);
        } else {
          await backupToHistory(file, layout.history, item.path);
          await client.download('saves', item.path, file);
          hashes.invalidate(file.path);
          base[item.path] = await hashes.sha1Of(file);
        }
        item.state = SyncItemState.done;
      } catch (e, st) {
        item.state = SyncItemState.failed;
        item.error = '$e';
        appLog.error(
            'No se pudo ${item.action == SyncAction.upload ? 'subir' : 'bajar'} ${item.path}',
            e,
            st);
      }
      // Guardamos la base tras cada archivo por si se corta la conexión.
      await _saveBase(_serverKey(client), base);
    }
    final failed = todo.where((i) => i.state == SyncItemState.failed).length;
    status = failed == 0
        ? 'Listo: ${todo.length} archivos sincronizados'
        : 'Terminado con $failed errores (detalles en Ajustes → Registro)';
    appLog.info('Sincronización terminada: ${todo.length - failed} correctos, $failed con error');
    busy = false;
    notifyListeners();
  }
}
