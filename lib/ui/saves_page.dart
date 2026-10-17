import 'package:flutter/material.dart';

import '../app_state.dart';
import '../core/models.dart';
import '../sync/save_sync.dart';
import 'theme.dart';

class SavesPage extends StatelessWidget {
  final VoidCallback onOpenRemote;
  const SavesPage({super.key, required this.onOpenRemote});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final client = app.client;
    final layout = app.layout;

    if (layout == null) {
      return const EmptyState(
        icon: Icons.folder_off_rounded,
        title: 'Sin carpeta Emulation',
        message: 'Configura tu carpeta en Ajustes primero.',
      );
    }
    if (client == null) {
      return EmptyState(
        icon: Icons.sync_disabled_rounded,
        title: 'Conéctate a un servidor',
        message: 'Las partidas se sincronizan con el dispositivo que actúa como servidor '
            '(normalmente tu PC). Conéctate desde la pestaña Descargar.',
        action: FilledButton(onPressed: onOpenRemote, child: const Text('Ir a Descargar')),
      );
    }

    final sync = app.saveSync;
    return ListenableBuilder(
      listenable: sync,
      builder: (context, _) {
        final plan = sync.plan;
        final last = app.settings.lastSaveSync;
        return Column(
          children: [
            PageHeader(
              title: 'Partidas guardadas',
              subtitle: 'Sincronizando con ${client.server.name}'
                  '${last == null ? '' : ' · última vez ${_ago(last)}'}',
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: double.infinity,
                child: RetroCard(
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Icon(Icons.sync_rounded, size: 32, color: RetroColors.neon),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: Text(
                        sync.status ??
                            sync.error ??
                            (plan == null
                                ? 'Compara tus partidas (saves y states) con las del servidor. '
                                    'Antes de sobrescribir algo se guarda una copia en saves/.retrohub_history.'
                                : '${plan.uploads.length} para subir · ${plan.downloads.length} para bajar · '
                                    '${plan.conflicts.length} conflictos · ${plan.unchanged} iguales'),
                        style: TextStyle(
                            color: sync.error != null ? RetroColors.danger : RetroColors.textDim),
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (sync.busy)
                      const SizedBox(
                          width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                    else ...[
                      OutlinedButton.icon(
                        onPressed: () => sync.analyze(client, layout),
                        icon: const Icon(Icons.search_rounded),
                        label: const Text('Analizar'),
                      ),
                      if (plan != null && plan.items.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: () async {
                            await sync.apply(client, layout);
                            app.settings.lastSaveSync = DateTime.now().millisecondsSinceEpoch;
                          },
                          icon: const Icon(Icons.sync_rounded),
                          label: const Text('Sincronizar'),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
              ),
            ),
            if (plan != null && plan.conflicts.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: RetroCard(
                  borderColor: RetroColors.warn,
                  child: Row(children: [
                    const Icon(Icons.warning_amber_rounded, color: RetroColors.warn),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                          '${plan.conflicts.length} archivos cambiaron en ambos dispositivos. '
                          'Elige cuál conservar en cada uno; la otra versión quedará en el historial.'),
                    ),
                    TextButton(
                      onPressed: sync.resolveAllByNewest,
                      child: const Text('Usar la más reciente'),
                    ),
                  ]),
                ),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: plan == null
                  ? const SizedBox.shrink()
                  : plan.items.isEmpty
                      ? const EmptyState(
                          icon: Icons.check_circle_rounded,
                          title: 'Todo sincronizado',
                          message: 'Tus partidas son iguales en ambos dispositivos.')
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          itemCount: plan.items.length,
                          itemBuilder: (context, i) => _SyncRow(item: plan.items[i], sync: sync),
                        ),
            ),
          ],
        );
      },
    );
  }

  static String _ago(int ms) {
    final d = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms));
    if (d.inMinutes < 1) return 'hace un momento';
    if (d.inHours < 1) return 'hace ${d.inMinutes} min';
    if (d.inDays < 1) return 'hace ${d.inHours} h';
    return 'hace ${d.inDays} días';
  }
}

class _SyncRow extends StatelessWidget {
  final SyncItem item;
  final SaveSync sync;
  const _SyncRow({required this.item, required this.sync});

  @override
  Widget build(BuildContext context) {
    final (icon, color, label) = switch (item.action) {
      SyncAction.upload => (Icons.upload_rounded, RetroColors.accent, 'Subir'),
      SyncAction.download => (Icons.download_rounded, RetroColors.neon, 'Bajar'),
      SyncAction.conflict => (Icons.help_rounded, RetroColors.warn, 'Conflicto'),
    };
    final stateIcon = switch (item.state) {
      SyncItemState.done => const Icon(Icons.check_circle_rounded, color: RetroColors.ok, size: 20),
      SyncItemState.failed => Tooltip(
          message: item.error ?? '',
          child: const Icon(Icons.error_rounded, color: RetroColors.danger, size: 20)),
      SyncItemState.pending => null,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: RetroColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: item.isConflict ? RetroColors.warn.withAlpha(120) : RetroColors.outline),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.path, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(
                  [
                    label,
                    if (item.local != null)
                      'local ${formatBytes(item.local!.size)} · ${_date(item.local!.mtime)}',
                    if (item.remote != null)
                      'servidor ${formatBytes(item.remote!.size)} · ${_date(item.remote!.mtime)}',
                  ].join('   '),
                  style: const TextStyle(fontSize: 11, color: RetroColors.textDim),
                ),
              ],
            ),
          ),
          if (item.isConflict && item.state == SyncItemState.pending)
            SegmentedButton<SyncAction>(
              showSelectedIcon: false,
              emptySelectionAllowed: true,
              segments: const [
                ButtonSegment(value: SyncAction.upload, label: Text('La mía')),
                ButtonSegment(value: SyncAction.download, label: Text('Servidor')),
              ],
              selected: item.action == SyncAction.conflict ? <SyncAction>{} : {item.action},
              onSelectionChanged: (s) {
                if (s.isNotEmpty) sync.resolve(item, s.first);
              },
            ),
          if (stateIcon != null) ...[const SizedBox(width: 8), stateIcon],
        ],
      ),
    );
  }

  static String _date(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
  }
}
