import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_hub/core/layout.dart';
import 'package:retro_hub/core/file_hash.dart';
import 'package:retro_hub/net/client.dart';
import 'package:retro_hub/net/protocol.dart';
import 'package:retro_hub/net/server.dart';

/// Levanta un servidor real en un puerto libre y prueba el cliente contra él.
void main() {
  late Directory root;
  late RetroServer server;
  late RetroClient client;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('retrohub_test');
    await Directory(p.join(root.path, 'roms', 'snes')).create(recursive: true);
    await Directory(p.join(root.path, 'saves', 'retroarch')).create(recursive: true);
    final bytes = List<int>.generate(300000, (i) => i % 251);
    await File(p.join(root.path, 'roms', 'snes', 'game.sfc')).writeAsBytes(bytes);

    server = RetroServer(
      layout: () => LibraryLayout(root.path),
      library: () => {},
      pin: () => '1234',
      deviceName: () => 'test',
      instanceId: () => 'abc',
      hashes: HashCache.at(File(p.join(root.path, 'hash.json'))),
    );
    // Puerto aleatorio para no chocar con una app abierta.
    await server.start(18000 + DateTime.now().millisecond);
    client = RetroClient(ServerAddress('test', '127.0.0.1', server.port!), '1234');
  });

  tearDown(() async {
    client.close();
    await server.stop();
    // En Windows un archivo puede seguir abierto un instante; no es un fallo.
    try {
      await root.delete(recursive: true);
    } on FileSystemException catch (_) {}
  });

  test('info devuelve el id de la instalación', () async {
    final info = await client.info();
    expect(info['id'], 'abc');
  });

  test('PIN incorrecto es rechazado', () async {
    final bad = RetroClient(client.server, '0000');
    await expectLater(bad.info(), throwsA(isA<ApiException>()));
    bad.close();
  });

  test('la descarga se reanuda desde un archivo parcial', () async {
    final dest = File(p.join(root.path, 'out', 'game.sfc'));
    await dest.parent.create(recursive: true);
    // Simulamos un intento anterior que se cortó a los 100000 bytes.
    final original = await File(p.join(root.path, 'roms', 'snes', 'game.sfc')).readAsBytes();
    await File('${dest.path}.retrohub_tmp').writeAsBytes(original.sublist(0, 100000));

    int? firstReported;
    await client.download('roms', 'snes/game.sfc', dest, onProgress: (r, total) {
      firstReported ??= r;
      expect(total, original.length);
    });

    expect(firstReported, 100000, reason: 'debe continuar, no empezar de cero');
    expect(await dest.readAsBytes(), original);
    expect(await File('${dest.path}.retrohub_tmp').exists(), isFalse);
  });

  test('subir un save guarda la versión anterior en el historial', () async {
    final save = File(p.join(root.path, 'saves', 'retroarch', 'a.srm'));
    await save.writeAsString('viejo');
    final local = File(p.join(root.path, 'local.srm'));
    await local.writeAsString('nuevo');

    await client.uploadSave('retroarch/a.srm', local);

    expect(await save.readAsString(), 'nuevo');
    final history = Directory(p.join(root.path, 'saves', '.retrohub_history', 'retroarch'));
    final backups = await history.list().toList();
    expect(backups, hasLength(1));
    expect(await File(backups.single.path).readAsString(), 'viejo');
  });

  test('no se puede escribir fuera de saves ni con rutas ..', () async {
    final local = File(p.join(root.path, 'x.bin'))..writeAsStringSync('x');
    await expectLater(client.uploadSave('../roms/snes/game.sfc', local),
        throwsA(isA<ApiException>()));
  });
}
