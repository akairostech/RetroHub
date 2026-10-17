import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/emudeck.dart';
import '../core/models.dart';
import '../net/client.dart';

enum DownloadStatus { queued, running, done, failed, cancelled }

class DownloadTask {
  final String id;
  final String label;
  final String subtitle;
  DownloadStatus status = DownloadStatus.queued;
  int received = 0;
  int total = 0;
  String? error;
  String? retryInfo;
  bool cancelRequested = false;

  DownloadTask(this.id, this.label, this.subtitle);

  double? get progress => total > 0 ? (received / total).clamp(0, 1) : null;
  bool get active =>
      status == DownloadStatus.queued || status == DownloadStatus.running;
}

/// Cola de descargas (una a la vez para no saturar la red).
class DownloadManager extends ChangeNotifier {
  final List<DownloadTask> tasks = [];
  final List<Future<void> Function()> _queue = [];
  bool _busy = false;

  /// Se llama cuando termina una descarga de ROM (para refrescar la biblioteca).
  VoidCallback? onRomDownloaded;

  bool isQueued(String id) => tasks.any((t) => t.id == id && t.active);

  void clearFinished() {
    tasks.removeWhere((t) => !t.active);
    notifyListeners();
  }

  void cancel(DownloadTask t) {
    t.cancelRequested = true;
    if (t.status == DownloadStatus.queued) t.status = DownloadStatus.cancelled;
    notifyListeners();
  }

  void downloadGame(RetroClient client, EmuLayout layout, Game game) {
    final id = 'rom:${game.key}';
    if (isQueued(id)) return;
    final task = DownloadTask(id, game.title, game.platform.toUpperCase());
    tasks.insert(0, task);
    _enqueue(() async {
      // Un juego puede ser un archivo o una carpeta (PS3, ScummVM...).
      final files = game.isFolder
          ? await client.tree('roms', path: '${game.platform}/${game.fileName}')
          : null;
      final items = files?.map((f) => (f.path, f.size)).toList() ??
          [('${game.platform}/${game.fileName}', game.size)];
      await _downloadFiles(client, 'roms', layout.roms, items, task);
      onRomDownloaded?.call();
    }, task);
  }

  /// Descarga las BIOS que falten (o tengan otro tamaño).
  void downloadBios(RetroClient client, EmuLayout layout) {
    const id = 'bios';
    if (isQueued(id)) return;
    final task = DownloadTask(id, 'BIOS', 'Archivos faltantes');
    tasks.insert(0, task);
    _enqueue(() async {
      final remote = await client.tree('bios');
      final missing = <(String, int)>[];
      for (final f in remote) {
        final local = File(safeJoin(layout.bios, f.path)!);
        if (!await local.exists() || await local.length() != f.size) {
          missing.add((f.path, f.size));
        }
      }
      await _downloadFiles(client, 'bios', layout.bios, missing, task);
    }, task);
  }

  Future<void> _downloadFiles(RetroClient client, String area, String localRoot,
      List<(String, int)> items, DownloadTask task) async {
    task.total = items.fold(0, (s, i) => s + i.$2);
    var base = 0;
    for (final (rel, size) in items) {
      final destPath = safeJoin(localRoot, rel);
      if (destPath == null) continue;
      final dest = File(destPath);
      if (await dest.exists() && await dest.length() == size) {
        base += size;
        task.received = base;
        notifyListeners();
        continue;
      }
      // Hasta 4 intentos; cada uno continúa desde el archivo parcial.
      for (var attempt = 1;; attempt++) {
        try {
          await client.download(area, rel, dest,
              isCancelled: () => task.cancelRequested, onProgress: (r, _) {
            task.received = base + r;
            _throttledNotify();
          });
          break;
        } on DownloadCancelled {
          rethrow;
        } on ApiException catch (e) {
          if (e.isFatal || attempt >= 4) rethrow;
          await _waitBeforeRetry(task, attempt);
        } catch (_) {
          // Wi-Fi caído, servidor reiniciado, etc.
          if (attempt >= 4) rethrow;
          await _waitBeforeRetry(task, attempt);
        }
      }
      task.retryInfo = null;
      base += size;
    }
    task.received = task.total;
  }

  Future<void> _waitBeforeRetry(DownloadTask task, int attempt) async {
    final seconds = [3, 8, 20][attempt - 1];
    task.retryInfo = 'Conexión perdida, reintentando en $seconds s (intento ${attempt + 1} de 4)';
    notifyListeners();
    await Future.delayed(Duration(seconds: seconds));
  }

  DateTime _lastNotify = DateTime.fromMillisecondsSinceEpoch(0);
  void _throttledNotify() {
    final now = DateTime.now();
    if (now.difference(_lastNotify).inMilliseconds > 150) {
      _lastNotify = now;
      notifyListeners();
    }
  }

  void _enqueue(Future<void> Function() job, DownloadTask task) {
    _queue.add(() async {
      if (task.status == DownloadStatus.cancelled) return;
      task.status = DownloadStatus.running;
      notifyListeners();
      try {
        await job();
        task.status = DownloadStatus.done;
      } on DownloadCancelled {
        task.status = DownloadStatus.cancelled;
      } catch (e) {
        task.status = DownloadStatus.failed;
        task.error = '$e';
      }
      notifyListeners();
    });
    notifyListeners();
    _pump();
  }

  Future<void> _pump() async {
    if (_busy) return;
    _busy = true;
    while (_queue.isNotEmpty) {
      final job = _queue.removeAt(0);
      await job();
    }
    _busy = false;
  }

  /// Ruta local donde quedaría un juego remoto.
  static String localPathFor(EmuLayout layout, Game g) =>
      p.join(layout.roms, g.platform, g.fileName);
}
