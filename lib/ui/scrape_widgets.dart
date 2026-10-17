import 'package:flutter/material.dart';

import '../app_state.dart';
import '../core/models.dart';
import '../core/platforms.dart';
import '../scrape/scraper.dart';
import 'theme.dart';
import 'widgets/game_widgets.dart';

/// Diálogo para lanzar el scraper sobre una o todas las plataformas.
Future<void> showScrapeDialog(BuildContext context) {
  return showDialog(context: context, builder: (_) => const _ScrapeDialog());
}

class _ScrapeDialog extends StatefulWidget {
  const _ScrapeDialog();

  @override
  State<_ScrapeDialog> createState() => _ScrapeDialogState();
}

class _ScrapeDialogState extends State<_ScrapeDialog> {
  String? _platform; // null = todas
  final _options = ScrapeOptions();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final games = _platform == null
        ? app.library.values.expand((g) => g).toList()
        : (app.library[_platform] ?? const <Game>[]);
    final igdb = app.settings.hasIgdb;

    return AlertDialog(
      title: const Row(children: [
        Icon(Icons.auto_awesome_rounded, color: RetroColors.neon),
        SizedBox(width: 10),
        Text('Scraper'),
      ]),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String?>(
              initialValue: _platform,
              decoration: const InputDecoration(labelText: 'Plataforma'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Todas las plataformas')),
                for (final id in app.library.keys)
                  DropdownMenuItem(
                    value: id,
                    child: Row(children: [
                      PlatformIcon(platform: id, size: 18, color: platformInfo(id).color),
                      const SizedBox(width: 10),
                      Text('${platformInfo(id).name} (${app.library[id]!.length})'),
                    ]),
                  ),
              ],
              onChanged: (v) => setState(() => _platform = v),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Imágenes'),
              subtitle: const Text('Carátula, captura y pantalla de título'),
              value: _options.images,
              onChanged: (v) => setState(() => _options.images = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Metadatos'),
              subtitle: const Text('Desarrollador, género, año, jugadores, descripción'),
              value: _options.metadata,
              onChanged: (v) => setState(() => _options.metadata = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Solo lo que falta'),
              subtitle: const Text('No reemplaza imágenes ni datos que ya existen'),
              value: _options.onlyMissing,
              onChanged: (v) => setState(() => _options.onlyMissing = v),
            ),
            const SizedBox(height: 8),
            Text(
              igdb
                  ? 'Fuentes: libretro (base de datos e imágenes) + IGDB (descripciones).'
                  : 'Fuente: libretro (base de datos e imágenes, sin cuenta). '
                      'Para descripciones y consolas modernas (Switch, PS3, PS4…) '
                      'configura IGDB en Ajustes.',
              style: const TextStyle(color: RetroColors.textDim, fontSize: 12),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton.icon(
          onPressed: games.isEmpty || (!_options.images && !_options.metadata)
              ? null
              : () {
                  Navigator.pop(context);
                  app.scrape(games, _options);
                },
          icon: const Icon(Icons.play_arrow_rounded),
          label: Text('Empezar (${games.length} juegos)'),
        ),
      ],
    );
  }
}

/// Barra inferior con el progreso del scraper.
class ScrapeProgressPanel extends StatefulWidget {
  const ScrapeProgressPanel({super.key});

  @override
  State<ScrapeProgressPanel> createState() => _ScrapeProgressPanelState();
}

class _ScrapeProgressPanelState extends State<ScrapeProgressPanel> {
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context).scraper;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        if (s.running) _dismissed = false;
        if (!s.running && (s.summary == null || _dismissed)) {
          return const SizedBox.shrink();
        }
        return Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
          decoration: const BoxDecoration(
            color: RetroColors.surface,
            border: Border(top: BorderSide(color: RetroColors.outline)),
          ),
          child: Row(children: [
            Icon(s.running ? Icons.auto_awesome_rounded : Icons.check_circle_rounded,
                color: s.running ? RetroColors.neon : RetroColors.ok),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    s.running
                        ? 'Scraper: ${s.done} de ${s.total} · ${s.updated} actualizados'
                        : s.summary!,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (s.running) ...[
                    const SizedBox(height: 4),
                    LinearProgressIndicator(value: s.progress),
                    const SizedBox(height: 2),
                    Text(s.current ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: RetroColors.textDim)),
                  ],
                ],
              ),
            ),
            if (s.running)
              TextButton(onPressed: s.cancel, child: const Text('Cancelar'))
            else
              IconButton(
                tooltip: 'Cerrar',
                onPressed: () => setState(() => _dismissed = true),
                icon: const Icon(Icons.close_rounded),
              ),
          ]),
        );
      },
    );
  }
}

/// Bloque con los metadatos de un juego (para la ficha de detalle).
class GameMetaView extends StatelessWidget {
  final GameMeta meta;
  const GameMetaView({super.key, required this.meta});

  @override
  Widget build(BuildContext context) {
    final chips = <(IconData, String)>[
      if (meta.year != null) (Icons.event_rounded, '${meta.year}'),
      if (meta.genre != null) (Icons.category_rounded, meta.genre!),
      if (meta.developer != null) (Icons.code_rounded, meta.developer!),
      if (meta.publisher != null && meta.publisher != meta.developer)
        (Icons.business_rounded, meta.publisher!),
      if (meta.players != null)
        (Icons.people_rounded, meta.players == 1 ? '1 jugador' : 'Hasta ${meta.players} jugadores'),
      if (meta.rating != null) (Icons.star_rounded, '${meta.rating!.round()}/100'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (chips.isNotEmpty)
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final (icon, text) in chips)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: RetroColors.surfaceHigh,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(icon, size: 14, color: RetroColors.accent),
                    const SizedBox(width: 5),
                    Text(text, style: const TextStyle(fontSize: 12)),
                  ]),
                ),
            ],
          ),
        if (meta.description != null) ...[
          const SizedBox(height: 10),
          Text(meta.description!,
              maxLines: 8,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, height: 1.35)),
        ],
        if (meta.source != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Fuente: ${meta.source}',
                style: const TextStyle(fontSize: 11, color: RetroColors.textDim)),
          ),
      ],
    );
  }
}
