import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retro_hub/core/models.dart';
import 'package:retro_hub/ui/theme.dart';
import 'package:retro_hub/ui/widgets/box_art.dart';
import 'package:retro_hub/ui/widgets/game_widgets.dart';

void main() {
  testWidgets('preview', (tester) async {
    tester.view.physicalSize = const Size(1100, 700);
    tester.view.devicePixelRatio = 1;
    const games = [
      Game(platform: 'snes', fileName: 'a.sfc', title: 'Super Juego', size: 1),
      Game(platform: 'psx', fileName: 'b.bin', title: 'Otro Juego', size: 1),
      Game(platform: 'gba', fileName: 'c.gba', title: 'Tercero', size: 1),
    ];
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        backgroundColor: RetroColors.surface,
        body: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(children: [
            Row(children: [
              for (final a in [-1.2, -0.5, -0.16, 0.0, 0.4])
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: SizedBox(
                      width: 170,
                      height: 230,
                      child: GameBox3D(game: games[0], providers: const [], angle: a)),
                ),
            ]),
            Row(children: [
              for (final g in games)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: SizedBox(
                      width: 160,
                      height: 280,
                      child: GameCard(game: g, favorite: g.platform == 'psx')),
                ),
            ]),
          ]),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('box_preview.png'));
  });
}
