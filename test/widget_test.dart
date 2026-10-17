import 'package:flutter_test/flutter_test.dart';
import 'package:retro_hub/core/models.dart';

void main() {
  test('parseTitle limpia nombres de ROM', () {
    final (title, tags) =
        parseTitle('Legend of Zelda, The - A Link to the Past (U) [!].smc');
    expect(title, 'The Legend of Zelda - A Link to the Past');
    expect(tags, '(U) [!]');

    final (t2, _) = parseTitle('1162 - Golden Sun 2 - La Edad Perdida (S)(FlashAdvance).gba');
    expect(t2, 'Golden Sun 2 - La Edad Perdida');
  });

  test('parseTitle limpia nombres de Switch', () {
    var (t, tags) = parseTitle(
        'Baten Kaitos 1 and 2 HD Remaster [0100F28018CA4000][v0][JP](Dumped).xci',
        isFolder: true);
    expect(t, 'Baten Kaitos 1 and 2 HD Remaster');
    expect(tags, '[JP]');

    (t, tags) = parseTitle(
        'Fire Emblem Three Houses[010055D009F78000]+[v1.2.0][v327680]+[6 DLC](nsw2u.com).xci');
    expect(t, 'Fire Emblem Three Houses');
    expect(tags, isNull);

    (t, _) = parseTitle("Super Mario 3D World + Bowser's Fury [v1.1.0](romsNgames.net).nsp");
    expect(t, "Super Mario 3D World + Bowser's Fury");

    (t, tags) = parseTitle('Mario Strikers Battle League [010019401051C000] [v393216] (1G+1U).xci');
    expect(t, 'Mario Strikers Battle League');
    expect(tags, isNull);
  });

  test('safeJoin rechaza rutas peligrosas', () {
    expect(safeJoin('/root', '../etc/passwd'), isNull);
    expect(safeJoin('/root', 'C:/Windows'), isNull);
    expect(safeJoin('/root', 'retroarch/saves/a.srm'), isNotNull);
  });
}
