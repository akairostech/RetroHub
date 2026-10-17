import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/models.dart';
import '../../core/platforms.dart';
import '../theme.dart';

/// URL de respaldo en libretro-thumbnails (si ES-DE no tiene la imagen).
String? libretroCoverUrl(Game g) {
  final sys = platformInfo(g.platform).libretro;
  if (sys == null || g.isFolder) return null;
  final name = p
      .basenameWithoutExtension(g.fileName)
      .replaceAll(RegExp(r'[&*/:`<>?\\|"]'), '_');
  return 'https://thumbnails.libretro.com/${Uri.encodeComponent(sys)}'
      '/Named_Boxarts/${Uri.encodeComponent(name)}.png';
}

List<ImageProvider> coverProviders(Game g, {Map<String, String>? headers}) {
  final list = <ImageProvider>[];
  if (g.coverFile != null) {
    list.add(ResizeImage(FileImage(File(g.coverFile!)), width: 400));
  }
  if (g.coverUrl != null) {
    list.add(ResizeImage(NetworkImage(g.coverUrl!, headers: headers), width: 400));
  }
  final lr = libretroCoverUrl(g);
  if (lr != null) list.add(ResizeImage(NetworkImage(lr), width: 400));
  return list;
}

/// Imagen que prueba varias fuentes en orden y, si todas fallan,
/// dibuja una carátula generada con el color de la plataforma.
class CoverImage extends StatelessWidget {
  final Game game;
  final List<ImageProvider> providers;
  final BoxFit fit;
  const CoverImage(
      {super.key, required this.game, required this.providers, this.fit = BoxFit.cover});

  @override
  Widget build(BuildContext context) {
    if (providers.isEmpty) return GeneratedCover(game: game);
    return Image(
      image: providers.first,
      fit: fit,
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, sync) => AnimatedOpacity(
        opacity: frame == null && !sync ? 0 : 1,
        duration: const Duration(milliseconds: 250),
        child: child,
      ),
      errorBuilder: (context, error, stack) => CoverImage(
          game: game, providers: providers.sublist(1), fit: fit),
    );
  }
}

class GeneratedCover extends StatelessWidget {
  final Game game;
  const GeneratedCover({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    final info = platformInfo(game.platform);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [info.color.withAlpha(200), RetroColors.surfaceHigh],
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(info.shortName.toUpperCase(),
              style: const TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
          const Spacer(),
          Text(
            game.title,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.w800, height: 1.15),
          ),
        ],
      ),
    );
  }
}

class PlatformBadge extends StatelessWidget {
  final String platform;
  const PlatformBadge({super.key, required this.platform});

  @override
  Widget build(BuildContext context) {
    final info = platformInfo(platform);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: info.color.withAlpha(60),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: info.color.withAlpha(140)),
      ),
      child: Text(info.shortName,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
    );
  }
}

/// Tarjeta de juego con carátula, animación al pasar el mouse y
/// una esquina opcional para insignias (descargado, progreso...).
class GameCard extends StatefulWidget {
  final Game game;
  final Map<String, String>? imageHeaders;
  final Widget? badge;
  final VoidCallback? onTap;
  final bool showPlatform;
  const GameCard({
    super.key,
    required this.game,
    this.imageHeaders,
    this.badge,
    this.onTap,
    this.showPlatform = false,
  });

  @override
  State<GameCard> createState() => _GameCardState();
}

class _GameCardState extends State<GameCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final g = widget.game;
    final color = platformInfo(g.platform).color;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _hover ? 1.04 : 1,
          duration: const Duration(milliseconds: 160),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: _hover ? color : RetroColors.outline, width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: (_hover ? color : Colors.black).withAlpha(_hover ? 90 : 60),
                        blurRadius: _hover ? 18 : 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Container(color: RetroColors.surfaceHigh),
                        CoverImage(
                            game: g,
                            providers: coverProviders(g, headers: widget.imageHeaders)),
                        if (widget.badge != null)
                          Positioned(top: 6, right: 6, child: widget.badge!),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(g.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600, height: 1.2)),
              const SizedBox(height: 2),
              Row(
                children: [
                  if (widget.showPlatform) ...[
                    PlatformBadge(platform: g.platform),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(
                      g.tags ?? formatBytes(g.size),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: RetroColors.textDim),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Navegador de biblioteca: lista de plataformas + búsqueda + cuadrícula.
/// Se usa tanto para la biblioteca local como para la del servidor.
class GameBrowser extends StatefulWidget {
  final Map<String, List<Game>> library;
  final Widget Function(BuildContext context, Game game) cardBuilder;
  final Widget? headerTrailing;
  const GameBrowser({
    super.key,
    required this.library,
    required this.cardBuilder,
    this.headerTrailing,
  });

  @override
  State<GameBrowser> createState() => _GameBrowserState();
}

class _GameBrowserState extends State<GameBrowser> {
  String? _platform; // null = todas
  String _query = '';

  List<Game> get _visible {
    final source = _platform == null
        ? widget.library.values.expand((g) => g)
        : (widget.library[_platform] ?? const <Game>[]);
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return source.toList();
    return source
        .where((g) =>
            g.title.toLowerCase().contains(q) || g.fileName.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_platform != null && !widget.library.containsKey(_platform)) _platform = null;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final games = _visible;

    final search = TextField(
      onChanged: (v) => setState(() => _query = v),
      decoration: InputDecoration(
        hintText: 'Buscar juego...',
        prefixIcon: const Icon(Icons.search_rounded),
        filled: true,
        fillColor: RetroColors.surface,
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );

    final grid = games.isEmpty
        ? const EmptyState(
            icon: Icons.search_off_rounded,
            title: 'Sin resultados',
            message: 'No hay juegos que coincidan con la búsqueda.')
        : GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: wide ? 190 : 150,
              mainAxisSpacing: 18,
              crossAxisSpacing: 16,
              childAspectRatio: 0.62,
            ),
            itemCount: games.length,
            itemBuilder: (context, i) => widget.cardBuilder(context, games[i]),
          );

    final searchRow = Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(children: [
        Expanded(child: search),
        if (widget.headerTrailing != null) ...[
          const SizedBox(width: 8),
          widget.headerTrailing!,
        ],
      ]),
    );

    if (wide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 240,
            child: _PlatformList(
              library: widget.library,
              selected: _platform,
              onSelect: (p) => setState(() => _platform = p),
            ),
          ),
          Expanded(
            child: Column(children: [searchRow, Expanded(child: grid)]),
          ),
        ],
      );
    }

    return Column(
      children: [
        searchRow,
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              _chip('Todas', null, widget.library.values.fold(0, (s, g) => s + g.length)),
              for (final e in widget.library.entries)
                _chip(platformInfo(e.key).shortName, e.key, e.value.length),
            ],
          ),
        ),
        Expanded(child: grid),
      ],
    );
  }

  Widget _chip(String label, String? id, int count) {
    final selected = _platform == id;
    final color = id == null ? RetroColors.accent : platformInfo(id).color;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: ChoiceChip(
        selected: selected,
        label: Text('$label · $count'),
        selectedColor: color.withAlpha(90),
        onSelected: (_) => setState(() => _platform = id),
      ),
    );
  }
}

class _PlatformList extends StatelessWidget {
  final Map<String, List<Game>> library;
  final String? selected;
  final ValueChanged<String?> onSelect;
  const _PlatformList(
      {required this.library, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final total = library.values.fold<int>(0, (s, g) => s + g.length);
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 24),
      children: [
        _tile('Todas las plataformas', 'Biblioteca completa', null, total,
            RetroColors.accent),
        const Padding(
          padding: EdgeInsets.fromLTRB(12, 16, 12, 6),
          child: Text('PLATAFORMAS',
              style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 1.4,
                  color: RetroColors.textDim,
                  fontWeight: FontWeight.w700)),
        ),
        for (final e in library.entries)
          _tile(platformInfo(e.key).name, platformInfo(e.key).maker, e.key,
              e.value.length, platformInfo(e.key).color),
      ],
    );
  }

  Widget _tile(String name, String sub, String? id, int count, Color color) {
    final sel = selected == id;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: sel ? color.withAlpha(45) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => onSelect(id),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 30,
                  decoration: BoxDecoration(
                      color: color, borderRadius: BorderRadius.circular(2)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontWeight: sel ? FontWeight.w800 : FontWeight.w600)),
                      Text(sub,
                          style: const TextStyle(
                              fontSize: 11, color: RetroColors.textDim)),
                    ],
                  ),
                ),
                Text('$count',
                    style: TextStyle(
                        color: sel ? Colors.white : RetroColors.textDim,
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Hoja de detalle de un juego.
Future<void> showGameDetails(
  BuildContext context,
  Game game, {
  Map<String, String>? imageHeaders,
  List<Widget> actions = const [],
}) {
  final info = platformInfo(game.platform);
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: RetroColors.surface,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 720),
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: MediaQuery.sizeOf(context).width < 500 ? 100 : 150,
                height: MediaQuery.sizeOf(context).width < 500 ? 140 : 210,
                child: CoverImage(
                    game: game,
                    providers: coverProviders(game, headers: imageHeaders),
                    fit: BoxFit.cover),
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  PlatformBadge(platform: game.platform),
                  const SizedBox(height: 8),
                  Text(game.title,
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w800)),
                  if (game.tags != null)
                    Text(game.tags!, style: const TextStyle(color: RetroColors.textDim)),
                  const SizedBox(height: 12),
                  _kv('Plataforma', '${info.name} (${info.maker})'),
                  _kv('Archivo', game.fileName),
                  _kv('Tamaño', formatBytes(game.size)),
                  if (game.localPath != null) _kv('Ruta', game.localPath!),
                  const SizedBox(height: 16),
                  Wrap(spacing: 8, runSpacing: 8, children: actions),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _kv(String k, String v) => Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text.rich(TextSpan(children: [
        TextSpan(
            text: '$k: ',
            style: const TextStyle(color: RetroColors.textDim, fontSize: 13)),
        TextSpan(text: v, style: const TextStyle(fontSize: 13)),
      ])),
    );
