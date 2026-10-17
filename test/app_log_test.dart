import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_hub/core/app_log.dart';

void main() {
  test('el registro guarda errores en memoria y en archivo', () async {
    final dir = await Directory.systemTemp.createTemp('retrohub_log');
    appLog.clear();
    appLog.info('antes del archivo');
    appLog.attachDirectory(dir.path, 'Mi Teléfono');
    appLog.error('algo falló', StateError('detalle'), StackTrace.current);
    expect(appLog.errorCount, 1);

    // Esperamos a que se escriba en disco.
    await Future.delayed(const Duration(milliseconds: 300));
    final file = File(p.join(dir.path, 'Mi_Tel_fono.log'));
    final text = await file.readAsString();
    expect(text, contains('antes del archivo'));
    expect(text, contains('ERROR algo falló'));
    expect(text, contains('detalle'));
    try {
      await dir.delete(recursive: true);
    } on FileSystemException catch (_) {}
  });
}
