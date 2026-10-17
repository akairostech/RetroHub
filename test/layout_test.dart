import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_hub/core/layout.dart';
import 'package:retro_hub/core/platforms.dart';

void main() {
  test('crea la estructura completa sin tocar lo existente', () async {
    final root = await Directory.systemTemp.createTemp('library');
    final layout = LibraryLayout(p.join(root.path, 'Emulation'));
    // Un juego que ya existía no debe perderse.
    final game = File(p.join(layout.roms, 'snes', 'juego.sfc'));
    await game.create(recursive: true);
    await game.writeAsString('rom');

    expect(await layout.isValid(), isTrue);
    final missingBefore = await layout.missingFolders();
    expect(missingBefore, isNotEmpty);

    final created = await layout.createStructure();
    expect(created, missingBefore.length);
    expect(await layout.missingFolders(), isEmpty);
    expect(await Directory(layout.bios).exists(), isTrue);
    expect(await Directory(layout.saves).exists(), isTrue);
    expect(await Directory(layout.media).exists(), isTrue);
    expect(await Directory(p.join(layout.roms, 'psx')).exists(), isTrue);
    expect(await Directory(layout.roms).list().length, greaterThanOrEqualTo(kPlatforms.length));
    expect(await game.readAsString(), 'rom');

    // Segunda vez: no hay nada que crear.
    expect(await layout.createStructure(), 0);
    try {
      await root.delete(recursive: true);
    } on FileSystemException catch (_) {}
  });
}
