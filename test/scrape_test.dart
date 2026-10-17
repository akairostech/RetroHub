import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:retro_hub/scrape/igdb.dart';
import 'package:retro_hub/scrape/libretro.dart';

const _developerDat = '''
clrmamepro (
	name "Nintendo - Super Nintendo Entertainment System"
)

game (
	comment "Super Mario World (USA)"
	developer "Nintendo EAD"
	rom ( crc B19ED489 )
)

game (
	comment "Super Mario World (Japan)"
	developer "Nintendo EAD"
	rom ( crc 1234ABCD )
)

game (
	comment "Legend of Zelda, The - A Link to the Past (USA)"
	developer "Nintendo EAD"
	rom ( crc 777AAC2F )
)
''';

const _yearDat = '''
game (
	comment "Super Mario World (USA)"
	releaseyear "1990"
	rom ( crc B19ED489 )
)
''';

const _usersDat = '''
game (
	comment "Super Mario World (USA)"
	users 2
	rom ( crc B19ED489 )
)
''';

void main() {
  test('normaliza nombres de distintas convenciones', () {
    expect(normalizeGameName('Legend of Zelda, The - A Link to the Past (U) [!]'),
        normalizeGameName('Legend of Zelda, The - A Link to the Past (USA)'));
    expect(normalizeGameName('1162 - Golden Sun 2 (S)'), 'goldensun2');
    expect(normalizeGameName('Banjo & Kazooie'), 'banjoandkazooie');
  });

  test('lee .dat de libretro y combina campos', () {
    final db = LibretroSystemDb()
      ..addDat(parseDat(_developerDat))
      ..addDat(parseDat(_yearDat))
      ..addDat(parseDat(_usersDat));

    final name = db.findName(fileName: 'Super Mario World (U) [!].smc');
    expect(name, 'Super Mario World (USA)', reason: 'prefiere la versión USA');
    final meta = db.metaFor(name!)!;
    expect(meta.name, 'Super Mario World');
    expect(meta.developer, 'Nintendo EAD');
    expect(meta.year, 1990);
    expect(meta.players, 2);

    // Por CRC aunque el nombre del archivo sea raro.
    expect(db.findName(fileName: 'zelda3.sfc', crc: '777AAC2F'),
        'Legend of Zelda, The - A Link to the Past (USA)');
  });

  test('URL de libretro-thumbnails reemplaza caracteres inválidos', () {
    final url = LibretroSource.thumbnailUrl(
        'Nintendo - Super Nintendo Entertainment System', 'Named_Boxarts', 'Mario & Luigi: Test');
    expect(url, contains('Mario%20_%20Luigi_%20Test.png'));
  });

  test('elige la mejor coincidencia de miniaturas', () {
    final names = {'Super Mario World (Japan)', 'Super Mario World (USA)', 'Super Mario Kart (USA)'};
    expect(LibretroSource.bestThumbnailMatch(names, 'Super Mario World (U) [!].smc'),
        'Super Mario World (USA)');
  });

  test('IGDB: elige el resultado correcto y lo convierte', () {
    final list = [
      {'name': 'Super Mario World 2: Yoshi\'s Island'},
      {
        'name': 'Super Mario World',
        'summary': 'Mario y Yoshi en Dinosaur Land.',
        'first_release_date': 659059200,
        'genres': [
          {'name': 'Platform'}
        ],
        'involved_companies': [
          {'developer': true, 'publisher': false, 'company': {'name': 'Nintendo EAD'}},
          {'developer': false, 'publisher': true, 'company': {'name': 'Nintendo'}},
        ],
        'cover': {'image_id': 'abc123'},
        'total_rating': 91.5,
      },
    ];
    final best = IgdbSource.pickBest(list, 'Super Mario World')!;
    final r = IgdbSource.toResult(best);
    expect(r.meta.description, contains('Yoshi'));
    expect(r.meta.developer, 'Nintendo EAD');
    expect(r.meta.publisher, 'Nintendo');
    expect(r.meta.year, 1990);
    expect(r.coverUrl, contains('abc123'));
    expect(IgdbSource.pickBest(list, 'Chrono Trigger'), isNull);
  });

  test('CRC32', () async {
    final dir = await Directory.systemTemp.createTemp('crc');
    final f = File('${dir.path}/x.bin')..writeAsStringSync('123456789');
    expect(await crc32OfFile(f), 'CBF43926');
    try {
      await dir.delete(recursive: true);
    } on FileSystemException catch (_) {}
  });
}
