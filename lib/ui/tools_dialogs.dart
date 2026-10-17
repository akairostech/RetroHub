import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../app_state.dart';
import '../core/layout.dart';
import '../core/library_tools.dart';
import '../core/models.dart';
import '../core/platforms.dart';
import 'theme.dart';
import 'widgets/game_widgets.dart';

Future<void> _reveal(String path) async {
  try {
    if (Platform.isWindows) {
      await Process.run('explorer.exe', ['/select,$path']);
    } else if (Platform.isMacOS) {
      await Process.run('open', ['-R', path]);
    } else {
      await Process.run('xdg-open', [p.dirname(path)]);
    }
  } catch (_) {}
}

// ---------------------------------------------------------------------------
// Duplicados
// ---------------------------------------------------------------------------

Future<void> showDuplicatesDialog(BuildContext context) {
  final app = AppScope.read(context);
  final groups = findDuplicates(app.library);
  final wasted = groups.fold<int>(0, (s, g) => s + g.wastedBytes);
  return showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Row(children: [
        Icon(Icons.content_copy_rounded, color: RetroColors.neon),
        SizedBox(width: 10),
        Text('Duplicados'),
      ]),
      content: SizedBox(
        width: 640,
        height: 480,
        child: groups.isEmpty
            ? const EmptyState(
                icon: Icons.check_circle_rounded,
                title: 'Sin duplicados',
                message: 'No hay dos versiones del mismo juego en una plataforma.')
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${groups.length} juegos tienen más de una versión. '
                    'Conservando solo la más pequeña de cada uno liberarías hasta ${formatBytes(wasted)}.',
                    style: const TextStyle(color: RetroColors.textDim),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: ListView(
                      children: [
                        for (final g in groups)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: RetroCard(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    PlatformIcon(
                                        platform: g.platform,
                                        size: 18,
                                        color: platformInfo(g.platform).color),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(g.title,
                                          style: const TextStyle(fontWeight: FontWeight.w700)),
                                    ),
                                    if (g.sameSize)
                                      const Tooltip(
                                        message: 'Mismo tamaño: probablemente idénticos',
                                        child: Icon(Icons.warning_amber_rounded,
                                            color: RetroColors.warn, size: 18),
                                      ),
                                  ]),
                                  const SizedBox(height: 6),
                                  for (final game in g.games)
                                    Row(children: [
                                      Expanded(
                                        child: Text(
                                          '${game.fileName}  ·  ${formatBytes(game.size)}',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ),
                                      if (isDesktop && game.localPath != null)
                                        IconButton(
                                          tooltip: 'Mostrar en carpeta',
                                          onPressed: () => _reveal(game.localPath!),
                                          icon: const Icon(Icons.folder_open_rounded, size: 18),
                                        ),
                                    ]),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        FilledButton(
            autofocus: true,
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar')),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// BIOS
// ---------------------------------------------------------------------------

Future<void> showBiosCheckDialog(BuildContext context) {
  return showDialog(context: context, builder: (_) => const _BiosDialog());
}

class _BiosDialog extends StatefulWidget {
  const _BiosDialog();

  @override
  State<_BiosDialog> createState() => _BiosDialogState();
}

class _BiosDialogState extends State<_BiosDialog> {
  List<BiosReport>? _reports;
  String _status = 'Descargando la lista de BIOS de libretro...';
  String? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    final app = AppScope.read(context);
    final lay = app.layout!;
    try {
      final reports = await BiosChecker().check(
        biosDir: lay.bios,
        cacheDir: p.join(lay.appData, 'cache', 'libretro'),
        platforms: app.library.keys,
        onProgress: (s) {
          if (mounted) setState(() => _status = s);
        },
      );
      if (mounted) setState(() => _reports = reports);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final reports = _reports;
    Widget body;
    if (_error != null) {
      body = EmptyState(icon: Icons.cloud_off_rounded, title: 'Error', message: _error!);
    } else if (reports == null) {
      body = Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(_status, style: const TextStyle(color: RetroColors.textDim)),
        ]),
      );
    } else if (reports.isEmpty) {
      body = const EmptyState(
        icon: Icons.memory_rounded,
        title: 'Nada que verificar',
        message: 'Ninguna de tus plataformas está en la lista de BIOS de libretro. '
            '(Switch, PS3, PS4 y Xbox usan firmware propio que no se verifica aquí.)',
      );
    } else {
      final ok = reports.where((r) => r.status == BiosStatus.ok).length;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$ok de ${reports.length} plataformas tienen al menos una BIOS válida. '
            'Solo se revisan las plataformas que tienen juegos.',
            style: const TextStyle(color: RetroColors.textDim),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView(children: [for (final r in reports) _ReportTile(report: r)]),
          ),
        ],
      );
    }
    return AlertDialog(
      title: const Row(children: [
        Icon(Icons.memory_rounded, color: RetroColors.neon),
        SizedBox(width: 10),
        Text('Verificar BIOS'),
      ]),
      content: SizedBox(width: 640, height: 480, child: body),
      actions: [
        FilledButton(
            autofocus: true,
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar')),
      ],
    );
  }
}

class _ReportTile extends StatelessWidget {
  final BiosReport report;
  const _ReportTile({required this.report});

  @override
  Widget build(BuildContext context) {
    final info = platformInfo(report.platform);
    final (icon, color, text) = switch (report.status) {
      BiosStatus.ok => (
          Icons.check_circle_rounded,
          RetroColors.ok,
          '${report.found.length} BIOS correcta${report.found.length == 1 ? '' : 's'}'
        ),
      BiosStatus.wrong => (
          Icons.warning_amber_rounded,
          RetroColors.warn,
          'Hay archivos con el nombre correcto pero contenido distinto'
        ),
      BiosStatus.missing => (
          Icons.cancel_rounded,
          RetroColors.danger,
          'No se encontró ninguna BIOS conocida'
        ),
    };
    return ExpansionTile(
      leading: PlatformIcon(platform: report.platform, size: 22, color: info.color),
      title: Text(info.name),
      subtitle: Row(children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: TextStyle(color: color, fontSize: 12))),
      ]),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (e, path) in report.found)
          Text('✓ ${e.name}  →  bios/$path',
              style: const TextStyle(fontSize: 12, color: RetroColors.ok)),
        for (final (e, path) in report.wrongHash)
          Text('⚠ bios/$path no coincide con ${e.name} (puede ser otra región o estar dañado)',
              style: const TextStyle(fontSize: 12, color: RetroColors.warn)),
        if (report.found.isEmpty) ...[
          const SizedBox(height: 4),
          const Text('Nombres esperados (basta con una):',
              style: TextStyle(fontSize: 12, color: RetroColors.textDim)),
          for (final e in report.expected.take(12))
            Text('• ${e.name}  (${formatBytes(e.size)})', style: const TextStyle(fontSize: 12)),
          if (report.expected.length > 12)
            Text('… y ${report.expected.length - 12} más',
                style: const TextStyle(fontSize: 12, color: RetroColors.textDim)),
        ],
      ],
    );
  }
}
