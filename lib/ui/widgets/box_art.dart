import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/platforms.dart';
import '../theme.dart';
import 'game_widgets.dart';

/// Preferencia "Carátulas 3D" (la carga AppState al iniciar).
final boxArt3dEnabled = ValueNotifier<bool>(true);

/// Caja de videojuego en 3D: la carátula como cara frontal y un lomo lateral
/// con el color de la consola, el título y su ícono.
///
/// [angle] es el giro sobre el eje vertical en radianes. Valores negativos
/// muestran el lomo izquierdo.
class GameBox3D extends StatelessWidget {
  final Game game;
  final List<ImageProvider> providers;
  final double angle;
  final bool highlight;

  /// Capas extra sobre la carátula (insignias, favorito, ayuda del mando).
  final List<Widget> overlays;

  const GameBox3D({
    super.key,
    required this.game,
    required this.providers,
    this.angle = -0.6,
    this.highlight = false,
    this.overlays = const [],
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final maxW = c.maxWidth.isFinite ? c.maxWidth : 160.0;
      final maxH = c.maxHeight.isFinite ? c.maxHeight : maxW * 1.4;
      // Cara frontal un poco más chica que el espacio para dejar sitio al lomo
      // y a la perspectiva.
      final w = maxW * 0.82;
      final h = maxH * 0.92;
      final d = w * 0.17; // grosor de la caja
      final top = (maxH - h) / 2;
      final left = (maxW - w) / 2 + d * 0.35;

      final pivot = Offset(left + w / 2, top + h / 2);
      Matrix4 face(Matrix4 local) => Matrix4.translationValues(pivot.dx, pivot.dy, 0)
        ..multiply(Matrix4.identity()..setEntry(3, 2, 0.3 / maxW))
        ..multiply(Matrix4.rotationY(angle))
        ..multiply(Matrix4.translationValues(-pivot.dx, -pivot.dy, 0))
        ..multiply(local);

      // El lomo sale del borde izquierdo de la carátula hacia atrás:
      // (x, y) del lomo -> (left, top + y, d - x).
      // (valores por columnas)
      final spineLocal = Matrix4(
        0, 0, -1, 0, //
        0, 1, 0, 0, //
        1, 0, 0, 0, //
        left, top, d, 1,
      );
      final frontLocal = Matrix4.translationValues(left, top, 0);

      // Luz: el lomo se oscurece cuanto menos de frente está.
      final spineLight = (0.55 + 0.45 * math.sin(-angle).clamp(0.0, 1.0)).toDouble();
      final color = platformInfo(game.platform).color;

      return Stack(clipBehavior: Clip.none, children: [
        // Sombra en el suelo.
        Positioned(
          left: left + 6,
          width: w - 6,
          top: top + h - 10,
          height: 18,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(40),
              boxShadow: [
                BoxShadow(
                  color: (highlight ? color : Colors.black).withAlpha(highlight ? 120 : 140),
                  blurRadius: highlight ? 24 : 16,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
        ),
        if (angle < 0.02)
          Positioned(
            left: 0,
            top: 0,
            child: Transform(
              transform: face(spineLocal),
              child: SizedBox(
                width: d,
                height: h,
                child: _Spine(game: game, light: spineLight),
              ),
            ),
          ),
        Positioned(
          left: 0,
          top: 0,
          child: Transform(
            transform: face(frontLocal),
            child: SizedBox(
              width: w,
              height: h,
              child: _Front(
                game: game,
                providers: providers,
                highlight: highlight,
                overlays: overlays,
              ),
            ),
          ),
        ),
      ]);
    });
  }
}

class _Front extends StatelessWidget {
  final Game game;
  final List<ImageProvider> providers;
  final bool highlight;
  final List<Widget> overlays;
  const _Front(
      {required this.game,
      required this.providers,
      required this.highlight,
      required this.overlays});

  @override
  Widget build(BuildContext context) {
    final color = platformInfo(game.platform).color;
    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
            color: highlight ? color : Colors.white.withAlpha(30), width: highlight ? 2 : 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Stack(fit: StackFit.expand, children: [
          Container(color: RetroColors.surfaceHigh),
          CoverImage(game: game, providers: providers),
          // Bisagra junto al lomo.
          const Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 7,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [Color(0x99000000), Color(0x00000000)]),
              ),
            ),
          ),
          // Brillo del plástico.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                stops: [0, 0.35, 0.36, 1],
                colors: [
                  Color(0x40FFFFFF),
                  Color(0x0AFFFFFF),
                  Color(0x00FFFFFF),
                  Color(0x22000000),
                ],
              ),
            ),
          ),
          ...overlays,
        ]),
      ),
    );
  }
}

class _Spine extends StatelessWidget {
  final Game game;
  final double light;
  const _Spine({required this.game, required this.light});

  @override
  Widget build(BuildContext context) {
    final info = platformInfo(game.platform);
    Color shade(Color c, double f) =>
        Color.lerp(Colors.black, c, f.clamp(0.0, 1.0)) ?? c;
    return LayoutBuilder(builder: (context, c) {
      final d = c.maxWidth;
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(2),
          gradient: LinearGradient(
            colors: [
              shade(info.color, light * 0.55),
              shade(info.color, light * 0.85),
              shade(info.color, light * 0.6),
            ],
          ),
        ),
        padding: EdgeInsets.symmetric(vertical: d * 0.35),
        child: Column(children: [
          PlatformIcon(platform: game.platform, size: d * 0.62),
          SizedBox(height: d * 0.3),
          Expanded(
            child: RotatedBox(
              quarterTurns: 1,
              child: Text(
                game.title.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: d * 0.42,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.6,
                  color: Colors.white.withAlpha((255 * light).round()),
                ),
              ),
            ),
          ),
        ]),
      );
    });
  }
}

/// Caja 3D grande que se gira arrastrando (hoja de detalles).
class RotatableGameBox extends StatefulWidget {
  final Game game;
  final List<ImageProvider> providers;
  const RotatableGameBox({super.key, required this.game, required this.providers});

  @override
  State<RotatableGameBox> createState() => _RotatableGameBoxState();
}

class _RotatableGameBoxState extends State<RotatableGameBox>
    with SingleTickerProviderStateMixin {
  double _angle = -0.65;
  late final AnimationController _settle =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
  Animation<double>? _back;

  @override
  void initState() {
    super.initState();
    _settle.addListener(() {
      if (_back != null) setState(() => _angle = _back!.value);
    });
  }

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.grab,
      child: GestureDetector(
        onHorizontalDragStart: (_) => _settle.stop(),
        onHorizontalDragUpdate: (e) =>
            setState(() => _angle = (_angle + e.delta.dx * 0.012).clamp(-1.3, 0.4)),
        onHorizontalDragEnd: (_) {
          _back = Tween(begin: _angle, end: -0.65)
              .animate(CurvedAnimation(parent: _settle, curve: Curves.easeOutBack));
          _settle.forward(from: 0);
        },
        child: GameBox3D(game: widget.game, providers: widget.providers, angle: _angle),
      ),
    );
  }
}
