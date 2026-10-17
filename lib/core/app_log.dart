import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

enum LogLevel { info, warn, error }

class LogEntry {
  final DateTime time;
  final LogLevel level;
  final String message;
  final String? details;
  LogEntry(this.time, this.level, this.message, [this.details]);

  String format() {
    String two(int n) => n.toString().padLeft(2, '0');
    final t = '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
    final lvl = switch (level) {
      LogLevel.info => 'INFO ',
      LogLevel.warn => 'AVISO',
      LogLevel.error => 'ERROR',
    };
    return details == null ? '$t $lvl $message' : '$t $lvl $message\n$details';
  }
}

/// Registro de la app: se muestra en Ajustes → Registro y se guarda en
/// {Emulation}/storage/retrohub/logs/{dispositivo}.log para poder revisarlo
/// después (también desde el PC).
class AppLog extends ChangeNotifier {
  AppLog._();
  static final instance = AppLog._();

  static const _maxEntries = 500;
  static const _maxFileBytes = 1024 * 1024;

  final List<LogEntry> entries = [];
  File? _file;
  Future<void> _pending = Future.value();

  String? get filePath => _file?.path;
  int get errorCount => entries.where((e) => e.level == LogLevel.error).length;

  /// Define dónde se guarda el archivo de registro.
  void attachDirectory(String dir, String deviceName) {
    final safeName = deviceName.replaceAll(RegExp(r'[^\w\-]+'), '_');
    final file = File(p.join(dir, '$safeName.log'));
    _pending = _pending.then((_) async {
      try {
        await file.parent.create(recursive: true);
        // Rotación simple: si pasa de 1 MB se renombra a .old.log
        if (await file.exists() && await file.length() > _maxFileBytes) {
          final old = File(p.join(dir, '$safeName.old.log'));
          if (await old.exists()) await old.delete();
          await file.rename(old.path);
        }
        _file = file;
        // Volcamos lo que se registró antes de tener archivo.
        final buffered = entries.map((e) => '${e.format()}\n').join();
        if (buffered.isNotEmpty) {
          await file.writeAsString(buffered, mode: FileMode.append);
        }
      } catch (_) {
        _file = null;
      }
    });
  }

  void info(String message) => _add(LogLevel.info, message);
  void warn(String message, [Object? error]) =>
      _add(LogLevel.warn, error == null ? message : '$message: $error');

  void error(String message, [Object? error, StackTrace? stack]) {
    final details = [
      if (error != null) '  $error',
      if (stack != null)
        stack.toString().split('\n').take(12).map((l) => '    $l').join('\n'),
    ].join('\n');
    _add(LogLevel.error, message, details.isEmpty ? null : details);
  }

  void _add(LogLevel level, String message, [String? details]) {
    final entry = LogEntry(DateTime.now(), level, message, details);
    entries.insert(0, entry);
    if (entries.length > _maxEntries) entries.removeLast();
    if (kDebugMode) debugPrint('[RetroHub] ${entry.format()}');
    final file = _file;
    if (file != null) {
      _pending = _pending.then((_) async {
        try {
          await file.writeAsString('${entry.format()}\n', mode: FileMode.append);
        } catch (_) {}
      });
    }
    notifyListeners();
  }

  void clear() {
    entries.clear();
    notifyListeners();
  }

  String exportText() => entries.reversed.map((e) => e.format()).join('\n');
}

AppLog get appLog => AppLog.instance;
