import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../app_state.dart';
import '../core/emudeck.dart';
import '../core/models.dart';
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
        cardBuilder: (context, g) => GameCard(
          game: g,
          onTap: () => showGameDetails(context, g, actions: [
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
            else if (app.layout != null)
              IconButton(
                tooltip: 'Volver a escanear',
                onPressed: app.rescan,
                icon: const Icon(Icons.refresh_rounded),
              ),
          ],
        ),
        Expanded(child: body),
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
