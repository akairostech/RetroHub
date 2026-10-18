import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_hub/core/models.dart';
import 'package:retro_hub/ui/widgets/box_art.dart';
import 'package:retro_hub/update/updater.dart';
import 'package:retro_hub/version.dart';

void main() {
  test('kAppVersion coincide con pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final m = RegExp(r'^version:\s*([0-9.]+)', multiLine: true).firstMatch(pubspec)!;
    expect(kAppVersion, m.group(1));
  });

  test('compareVersions', () {
    expect(compareVersions('v0.5.1', '0.5.0'), greaterThan(0));
    expect(compareVersions('0.5.1', 'v0.5.1'), 0);
    expect(compareVersions('0.10.0', '0.9.9'), greaterThan(0));
    expect(compareVersions('1.0', '1.0.1'), lessThan(0));
    expect(compareVersions('0.5.1+6', '0.5.1'), 0);
  });

  test('lee un Release de GitHub', () {
    final r = ReleaseInfo.fromJson({
      'tag_name': 'v9.0.0',
      'name': 'RetroHub 9',
      'body': '## Novedades',
      'html_url': 'https://github.com/x',
      'published_at': '2026-10-17T10:00:00Z',
      'assets': [
        {'name': 'RetroHub-android.apk', 'browser_download_url': 'https://x/a.apk', 'size': 10},
      ],
    });
    expect(r.tag, 'v9.0.0');
    expect(r.assets.single.size, 10);
    expect(compareVersions(r.tag, kAppVersion), greaterThan(0));
  });

  testWidgets('la caja 3D se dibuja en cualquier ángulo', (tester) async {
    const game = Game(platform: 'snes', fileName: 'Juego (USA).sfc', title: 'Juego', size: 1);
    for (final a in [-1.2, -0.5, 0.0, 0.4]) {
      await tester.pumpWidget(MaterialApp(
        home: Center(
          child: SizedBox(
            width: 160,
            height: 220,
            child: GameBox3D(game: game, providers: const [], angle: a),
          ),
        ),
      ));
      expect(find.text('JUEGO'), a < 0.02 ? findsOneWidget : findsNothing);
      expect(tester.takeException(), isNull);
    }
  });
}
