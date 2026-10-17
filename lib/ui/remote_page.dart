import 'package:flutter/material.dart';

import '../app_state.dart';
import '../core/models.dart';
import '../net/discovery.dart';
import '../net/protocol.dart';
import '../sync/downloader.dart';
import 'theme.dart';
import 'widgets/game_widgets.dart';

/// Explorar la biblioteca de otro dispositivo (servidor) y descargar.
class RemotePage extends StatelessWidget {
  const RemotePage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final client = app.client;
    if (client == null) return const ConnectPanel();

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          PageHeader(
            title: client.server.name,
            subtitle: 'Conectado a ${client.server.host}:${client.server.port}',
            actions: [
              IconButton(
                tooltip: 'Actualizar',
                onPressed: app.refreshRemote,
                icon: const Icon(Icons.refresh_rounded),
              ),
              TextButton.icon(
                onPressed: app.disconnect,
                icon: const Icon(Icons.link_off_rounded),
                label: const Text('Desconectar'),
              ),
            ],
          ),
          const TabBar(
            tabAlignment: TabAlignment.start,
            isScrollable: true,
            tabs: [
              Tab(icon: Icon(Icons.videogame_asset_rounded), text: 'Juegos'),
              Tab(icon: Icon(Icons.memory_rounded), text: 'BIOS'),
            ],
          ),
          Expanded(
            child: TabBarView(children: [
              _RemoteGames(),
              _RemoteBios(),
            ]),
          ),
          const DownloadsPanel(),
        ],
      ),
    );
  }
}

class _RemoteGames extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final client = app.client!;
    final layout = app.layout;
    if (app.remoteLibrary.isEmpty) {
      return const EmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'El servidor no tiene juegos',
        message: 'O todavía está escaneando su biblioteca. Pulsa actualizar en unos segundos.',
      );
    }
    return ListenableBuilder(
      listenable: app.downloads,
      builder: (context, _) => GameBrowser(
        library: app.remoteLibrary,
        cardBuilder: (context, g) {
          final have = app.hasLocal(g);
          final queued = app.downloads.isQueued('rom:${g.key}');
          return GameCard(
            game: g,
            imageHeaders: client.headers,
            badge: have
                ? const _Badge(icon: Icons.check_rounded, color: RetroColors.ok)
                : queued
                    ? const _Badge(icon: Icons.downloading_rounded, color: RetroColors.neon)
                    : null,
            onTap: () => showGameDetails(context, g,
                imageHeaders: client.headers,
                actions: [
                  if (layout == null)
                    const Text('Configura tu carpeta Emulation en Ajustes para descargar.')
                  else
                    FilledButton.icon(
                      onPressed: have || queued
                          ? null
                          : () {
                              app.downloads.downloadGame(client, layout, g);
                              Navigator.pop(context);
                            },
                      icon: Icon(have ? Icons.check_rounded : Icons.download_rounded),
                      label: Text(have
                          ? 'Ya lo tienes'
                          : 'Descargar (${formatBytes(g.size)})'),
                    ),
                ]),
          );
        },
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final IconData icon;
  final Color color;
  const _Badge({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.black.withAlpha(170),
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 1.5),
        ),
        child: Icon(icon, size: 16, color: color),
      );
}

class _RemoteBios extends StatefulWidget {
  @override
  State<_RemoteBios> createState() => _RemoteBiosState();
}

class _RemoteBiosState extends State<_RemoteBios> {
  Future<List<FileEntry>>? _future;

  /// Agrupa por la primera carpeta ("" = archivos sueltos en bios/).
  Map<String, List<FileEntry>> _groupByFolder(List<FileEntry> files) {
    final groups = <String, List<FileEntry>>{'': []};
    for (final f in files) {
      final i = f.path.indexOf('/');
      groups.putIfAbsent(i < 0 ? '' : f.path.substring(0, i), () => []).add(f);
    }
    if (groups['']!.isEmpty) groups.remove('');
    return groups;
  }

  Widget _fileTile(FileEntry f, String label) => ListTile(
        dense: true,
        leading: const Icon(Icons.description_outlined, size: 20),
        title: Text(label),
        trailing: Text(formatBytes(f.size),
            style: const TextStyle(color: RetroColors.textDim)),
      );

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final client = app.client!;
    _future ??= client.tree('bios');
    return FutureBuilder<List<FileEntry>>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) {
          return EmptyState(
              icon: Icons.error_outline_rounded,
              title: 'Error',
              message: '${snap.error}');
        }
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final files = snap.data!;
        final total = files.fold<int>(0, (s, f) => s + f.size);
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            RetroCard(
              child: Row(
                children: [
                  const Icon(Icons.memory_rounded, size: 32, color: RetroColors.neon),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                        '${files.length} archivos de BIOS en el servidor (${formatBytes(total)}).\n'
                        'Se descargan solo los que te falten.',
                        style: const TextStyle(color: RetroColors.textDim)),
                  ),
                  FilledButton.icon(
                    onPressed: app.layout == null
                        ? null
                        : () => app.downloads.downloadBios(client, app.layout!),
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('Descargar BIOS'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            for (final group in _groupByFolder(files).entries)
              group.key.isEmpty
                  ? Column(children: [
                      for (final f in group.value) _fileTile(f, f.path),
                    ])
                  : ExpansionTile(
                      leading: const Icon(Icons.folder_rounded, color: RetroColors.accent),
                      title: Text(group.key),
                      subtitle: Text(
                          '${group.value.length} archivos · '
                          '${formatBytes(group.value.fold<int>(0, (s, f) => s + f.size))}',
                          style: const TextStyle(color: RetroColors.textDim, fontSize: 12)),
                      children: [
                        for (final f in group.value)
                          _fileTile(f, f.path.substring(group.key.length + 1)),
                      ],
                    ),
          ],
        );
      },
    );
  }
}

/// Panel inferior con las descargas en curso.
class DownloadsPanel extends StatelessWidget {
  const DownloadsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final dm = AppScope.of(context).downloads;
    return ListenableBuilder(
      listenable: dm,
      builder: (context, _) {
        if (dm.tasks.isEmpty) return const SizedBox.shrink();
        return Container(
          constraints: const BoxConstraints(maxHeight: 200),
          decoration: const BoxDecoration(
            color: RetroColors.surface,
            border: Border(top: BorderSide(color: RetroColors.outline)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
                child: Row(children: [
                  const Text('Descargas', style: TextStyle(fontWeight: FontWeight.w700)),
                  const Spacer(),
                  TextButton(onPressed: dm.clearFinished, child: const Text('Limpiar')),
                ]),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
                  children: [for (final t in dm.tasks) _taskRow(dm, t)],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _taskRow(DownloadManager dm, DownloadTask t) {
    final (icon, color, text) = switch (t.status) {
      DownloadStatus.queued => (Icons.schedule_rounded, RetroColors.textDim, 'En cola'),
      DownloadStatus.running => (
          Icons.downloading_rounded,
          RetroColors.neon,
          '${formatBytes(t.received)} / ${formatBytes(t.total)}'
        ),
      DownloadStatus.done => (Icons.check_circle_rounded, RetroColors.ok, 'Completado'),
      DownloadStatus.failed => (Icons.error_rounded, RetroColors.danger, t.error ?? 'Error'),
      DownloadStatus.cancelled => (Icons.cancel_rounded, RetroColors.textDim, 'Cancelado'),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${t.label}  ·  ${t.subtitle}',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                if (t.status == DownloadStatus.running)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: LinearProgressIndicator(value: t.progress),
                  ),
                Text(text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: RetroColors.textDim)),
              ],
            ),
          ),
          if (t.active)
            IconButton(
              tooltip: 'Cancelar',
              onPressed: () => dm.cancel(t),
              icon: const Icon(Icons.close_rounded, size: 18),
            ),
        ],
      ),
    );
  }
}

/// Pantalla para buscar y conectarse a un servidor.
class ConnectPanel extends StatefulWidget {
  const ConnectPanel({super.key});

  @override
  State<ConnectPanel> createState() => _ConnectPanelState();
}

class _ConnectPanelState extends State<ConnectPanel> {
  final _host = TextEditingController();
  final _port = TextEditingController(text: '8787');
  final _pin = TextEditingController();
  List<ServerAddress>? _found;
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    final s = AppScope.read(context).settings;
    _host.text = s.lastServerHost ?? '';
    _port.text = '${s.lastServerPort ?? 8787}';
    _pin.text = s.lastServerPin ?? '';
    _search();
  }

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() => _searching = true);
    List<ServerAddress> found;
    try {
      found = await discoverServers();
    } catch (_) {
      found = [];
    }
    if (!mounted) return;
    setState(() {
      _found = found;
      _searching = false;
    });
  }

  void _connect(ServerAddress a) {
    AppScope.read(context).connect(a, _pin.text.trim());
  }

  /// Pide el PIN antes de conectar a un servidor encontrado en la red.
  Future<void> _connectDiscovered(ServerAddress a) async {
    final ctrl = TextEditingController(text: _pin.text);
    final pin = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Conectar a ${a.name}'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'PIN',
            helperText: 'Lo ves en la pestaña "Servidor" de ese equipo',
          ),
          onSubmitted: (v) => Navigator.pop(context, v.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, ctrl.text.trim()),
              child: const Text('Conectar')),
        ],
      ),
    );
    ctrl.dispose();
    if (pin == null || !mounted) return;
    _pin.text = pin;
    _connect(a);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        const PageHeader(
          title: 'Descargar',
          subtitle: 'Conéctate a otro dispositivo con RetroHub en modo servidor',
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              RetroCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.wifi_find_rounded, color: RetroColors.neon),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text('Servidores en tu red',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      ),
                      if (_searching)
                        const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                      else
                        TextButton.icon(
                          onPressed: _search,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Buscar'),
                        ),
                    ]),
                    const SizedBox(height: 8),
                    if (_found != null && _found!.isEmpty && !_searching)
                      const Text(
                          'No se encontró ningún servidor. Verifica que el PC tenga el servidor encendido '
                          'y que ambos estén en la misma red Wi-Fi, o escribe la IP abajo.',
                          style: TextStyle(color: RetroColors.textDim)),
                    for (final s in _found ?? const <ServerAddress>[])
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const CircleAvatar(
                            backgroundColor: RetroColors.surfaceHigh,
                            child: Icon(Icons.dns_rounded, color: RetroColors.accent)),
                        title: Text(s.name),
                        subtitle: Text('${s.host}:${s.port}'),
                        trailing: FilledButton(
                          onPressed: app.connecting ? null : () => _connectDiscovered(s),
                          child: const Text('Conectar'),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              RetroCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Conexión manual',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        SizedBox(
                          width: 220,
                          child: TextField(
                            controller: _host,
                            decoration: const InputDecoration(
                                labelText: 'IP del servidor', hintText: '192.168.1.10'),
                          ),
                        ),
                        SizedBox(
                          width: 100,
                          child: TextField(
                            controller: _port,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Puerto'),
                          ),
                        ),
                        SizedBox(
                          width: 120,
                          child: TextField(
                            controller: _pin,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'PIN'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.icon(
                        onPressed: app.connecting
                            ? null
                            : () {
                                final host = _host.text.trim();
                                if (host.isEmpty) return;
                                _connect(ServerAddress(host, host,
                                    int.tryParse(_port.text.trim()) ?? 8787));
                              },
                        icon: app.connecting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.link_rounded),
                        label: const Text('Conectar'),
                      ),
                    ),
                    if (app.connectError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(app.connectError!,
                            style: const TextStyle(color: RetroColors.danger)),
                      ),
                    const SizedBox(height: 8),
                    const Text(
                      'El PIN aparece en la pestaña "Servidor" del PC.',
                      style: TextStyle(color: RetroColors.textDim, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
