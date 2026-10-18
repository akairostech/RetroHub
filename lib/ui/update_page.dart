import 'dart:io';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../core/models.dart';
import '../update/updater.dart';
import 'theme.dart';

/// Sección "Actualizar": compara con el último Release de GitHub y se
/// actualiza sola.
class UpdatePage extends StatelessWidget {
  const UpdatePage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final u = app.updater;
    return ListenableBuilder(
      listenable: u,
      builder: (context, _) {
        final latest = u.latest;
        final busy = u.stage == UpdateStage.checking ||
            u.stage == UpdateStage.downloading ||
            u.stage == UpdateStage.installing;
        return ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            PageHeader(
              title: 'Actualizar',
              subtitle: 'Versión instalada: ${u.currentVersion}',
              actions: [
                TextButton.icon(
                  onPressed: busy ? null : u.check,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Buscar ahora'),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  RetroCard(
                    borderColor: u.updateAvailable ? RetroColors.neon : null,
                    child: Row(children: [
                      Icon(
                        u.updateAvailable
                            ? Icons.system_update_rounded
                            : latest == null
                                ? Icons.cloud_sync_rounded
                                : Icons.verified_rounded,
                        size: 40,
                        color: u.updateAvailable ? RetroColors.neon : RetroColors.ok,
                      ),
                      const SizedBox(width: 16),
                      Expanded(child: _status(u)),
                    ]),
                  ),
                  if (u.stage == UpdateStage.downloading) ...[
                    const SizedBox(height: 12),
                    LinearProgressIndicator(value: u.progress),
                    const SizedBox(height: 4),
                    Text('${formatBytes(u.received)} de ${formatBytes(u.total)}',
                        style: const TextStyle(color: RetroColors.textDim, fontSize: 12)),
                  ],
                  if (u.message != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(u.message!,
                          style: TextStyle(
                              color: u.stage == UpdateStage.error
                                  ? RetroColors.danger
                                  : RetroColors.textDim)),
                    ),
                  if (u.updateAvailable) ...[
                    const SizedBox(height: 12),
                    if (u.isDevelopmentBuild)
                      const RetroCard(
                        borderColor: RetroColors.warn,
                        child: Text(
                          'Estás usando una versión de desarrollo (compilada en VS Code). '
                          'Para actualizarla usa .\\dev.ps1, que trae los cambios con git.',
                        ),
                      )
                    else
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FilledButton.icon(
                          autofocus: true,
                          onPressed: busy || u.asset == null ? null : u.downloadAndInstall,
                          icon: const Icon(Icons.download_rounded),
                          label: Text(u.asset == null
                              ? 'Sin archivo para este sistema'
                              : 'Descargar e instalar (${formatBytes(u.asset!.size)})'),
                        ),
                      ),
                    if (!Platform.isAndroid && !u.isDevelopmentBuild)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          'RetroHub se cerrará, se actualizará y se volverá a abrir solo.',
                          style: TextStyle(color: RetroColors.textDim, fontSize: 12),
                        ),
                      ),
                  ],
                  if (latest != null) ...[
                    const SizedBox(height: 16),
                    RetroCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Novedades de ${latest.name}',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                          if (latest.publishedAt != null)
                            Text(
                              'Publicada el ${latest.publishedAt!.toLocal().toString().split(' ').first}',
                              style: const TextStyle(color: RetroColors.textDim, fontSize: 12),
                            ),
                          const SizedBox(height: 10),
                          ...releaseNotesWidgets(latest.notes),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  RetroCard(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: SwitchListTile(
                      title: const Text('Buscar actualizaciones al abrir RetroHub'),
                      value: app.settings.autoCheckUpdates,
                      onChanged: (v) {
                        app.settings.autoCheckUpdates = v;
                        app.refresh();
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _status(Updater u) {
    final latest = u.latest;
    String title;
    String sub;
    switch (u.stage) {
      case UpdateStage.checking:
        title = 'Buscando actualizaciones...';
        sub = 'Consultando GitHub';
      case UpdateStage.downloading:
        title = 'Descargando ${latest?.tag}...';
        sub = 'No cierres RetroHub';
      case UpdateStage.installing:
        title = 'Instalando ${latest?.tag}...';
        sub = Platform.isAndroid ? 'Confirma en el instalador de Android' : 'RetroHub se reiniciará';
      default:
        if (latest == null) {
          title = 'Sin comprobar';
          sub = 'Pulsa "Buscar ahora" para ver si hay una versión nueva.';
        } else if (u.updateAvailable) {
          title = 'Hay una versión nueva: ${latest.tag}';
          sub = 'Tienes la ${u.currentVersion}.';
        } else {
          title = 'RetroHub está al día';
          sub = 'La última versión publicada es ${latest.tag}.';
        }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      Text(sub, style: const TextStyle(color: RetroColors.textDim)),
    ]);
  }
}

/// Muestra las notas del Release (Markdown sencillo) como texto con formato.
List<Widget> releaseNotesWidgets(String markdown) {
  final out = <Widget>[];
  for (var line in markdown.split('\n')) {
    line = line.trimRight();
    if (line.isEmpty || line.startsWith('|')) continue;
    final clean = line.replaceAll('**', '').replaceAll('`', '');
    if (clean.startsWith('#')) {
      out.add(Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Text(clean.replaceFirst(RegExp(r'^#+\s*'), ''),
            style: const TextStyle(fontWeight: FontWeight.w700, color: RetroColors.accent)),
      ));
    } else if (clean.startsWith('- ') || clean.startsWith('* ')) {
      out.add(Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('•  ', style: TextStyle(color: RetroColors.neon)),
          Expanded(child: Text(clean.substring(2), style: const TextStyle(height: 1.35))),
        ]),
      ));
    } else {
      out.add(Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(clean, style: const TextStyle(height: 1.35)),
      ));
    }
  }
  return out;
}
