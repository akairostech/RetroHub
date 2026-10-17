import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../app_state.dart';
import '../core/emudeck.dart';
import '../core/models.dart';
import '../scrape/scraper.dart';
import 'scrape_widgets.dart';
import 'tools_dialogs.dart';
import 'theme.dart';
import 'widgets/game_widgets.dart';

class LibraryPage extends StatelessWidget {
  final VoidCallback onOpenSettings;
  const LibraryPage({super.key, required this.onOpenSettings});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);

    Widget body;
    if (app.layout == null) {
      body = EmptyState(
        icon: Icons.folder_open_rounded,
        title: 'Elige tu carpeta Emulation',
        message: 'Selecciona la carpeta de EmuDeck que contiene roms, bios y saves.',
        action: FilledButton.icon(
          onPressed: onOpenSettings,
          icon: const Icon(Icons.settings_rounded),
          label: const Text('Ir a Ajustes'),
        ),
      );
    } else if (!app.storageGranted) {
      body = EmptyState(
        icon: Icons.lock_open_rounded,
        title: 'Permiso de almacenamiento',
        message: 'Android necesita el permiso "Acceso a todos los archivos" para leer tu carpeta Emulation.',
        action: FilledButton(
          onPressed: app.requestStoragePermission,
          child: const Text('Conceder permiso'),
        ),
      );
    } else if (app.scanning && app.library.isEmpty) {
      body = const Center(child: CircularProgressIndicator());
    } else if (app.scanError != null) {
      body = EmptyState(
        icon: Icons.error_outline_rounded,
        title: 'No se pudo leer la biblioteca',
        message: app.scanError!,
        action: OutlinedButton(onPressed: onOpenSettings, child: const Text('Revisar carpeta')),
      );
    } else if (app.library.isEmpty) {
      body = const EmptyState(
        icon: Icons.videogame_asset_off_rounded,
        title: 'No hay juegos todavía',
        message: 'Copia ROMs en roms/{plataforma} o descárgalas desde otro dispositivo.',
      );
    } else {
      body = GameBrowser(
        library: app.library,
        favorites: app.favorites,
        recents: app.recents,
        cardBuilder: (context, g) => GameCard(
          game: g,
          favorite: app.isFavorite(g),
          onPlay: () => playGame(context, g),
          onFavorite: () => app.toggleFavorite(g),
          onTap: () => showGameDetails(context, g, actions: [
            FilledButton.icon(
              autofocus: true,
              onPressed: () {
                Navigator.pop(context);
                playGame(context, g);
              },
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Jugar'),
            ),
            OutlinedButton.icon(
              onPressed: () {
                app.toggleFavorite(g);
                Navigator.pop(context);
              },
              icon: Icon(app.isFavorite(g) ? Icons.star_rounded : Icons.star_border_rounded),
              label: Text(app.isFavorite(g) ? 'Quitar de favoritos' : 'Favorito'),
            ),
            OutlinedButton.icon(
              onPressed: app.scraper.running
                  ? null
                  : () {
                      Navigator.pop(context);
                      app.scrape([g], ScrapeOptions(onlyMissing: false));
                    },
              icon: const Icon(Icons.auto_awesome_rounded),
              label: const Text('Buscar metadatos'),
            ),
            if (isDesktop && g.localPath != null)
              OutlinedButton.icon(
                onPressed: () => _reveal(g),
                icon: const Icon(Icons.folder_rounded),
                label: const Text('Mostrar en carpeta'),
              ),
          ]),
        ),
      );
    }

    return Column(
      children: [
        PageHeader(
          title: 'Biblioteca',
          subtitle: app.layout == null
              ? null
              : '${app.localGameCount} juegos · ${app.library.length} plataformas · ${app.layout!.root}',
          actions: [
            if (app.scanning)
              const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                    width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (app.layout != null) ...[
              IconButton(
                tooltip: 'Scraper: carátulas y metadatos',
                onPressed: app.library.isEmpty ? null : () => showScrapeDialog(context),
                icon: const Icon(Icons.auto_awesome_rounded),
              ),
              PopupMenuButton<String>(
                tooltip: 'Herramientas',
                icon: const Icon(Icons.handyman_rounded),
                onSelected: (v) => switch (v) {
                  'dup' => showDuplicatesDialog(context),
                  'bios' => showBiosCheckDialog(context),
                  _ => null,
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                      value: 'dup',
                      child: ListTile(
                          leading: Icon(Icons.content_copy_rounded),
                          title: Text('Buscar duplicados'))),
                  PopupMenuItem(
                      value: 'bios',
                      child: ListTile(
                          leading: Icon(Icons.memory_rounded), title: Text('Verificar BIOS'))),
                ],
              ),
              IconButton(
                tooltip: 'Volver a escanear',
                onPressed: app.rescan,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ],
        ),
        Expanded(child: body),
        const ScrapeProgressPanel(),
      ],
    );
  }

  static Future<void> _reveal(Game g) async {
    final path = g.localPath!;
    try {
      if (Platform.isWindows) {
        await Process.run('explorer.exe', ['/select,$path']);
      } else if (Platform.isMacOS) {
        await Process.run('open', ['-R', path]);
      } else {
        await Process.run('xdg-open', [g.isFolder ? path : p.dirname(path)]);
      }
    } catch (_) {}
  }
}

/// Abre el juego y muestra un aviso si algo falla.
Future<void> playGame(BuildContext context, Game g) async {
  final app = AppScope.read(context);
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(SnackBar(
      content: Text('Abriendo ${g.title}...'), duration: const Duration(seconds: 2)));
  final err = await app.play(g);
  if (err != null) {
    messenger.showSnackBar(SnackBar(
      content: Text(err),
      backgroundColor: RetroColors.danger.withAlpha(230),
      duration: const Duration(seconds: 6),
    ));
  }
}
