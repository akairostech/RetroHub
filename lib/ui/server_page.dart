import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../core/settings.dart';
import '../net/discovery.dart';
import 'theme.dart';

/// Control del servidor (solo escritorio).
class ServerPage extends StatefulWidget {
  const ServerPage({super.key});

  @override
  State<ServerPage> createState() => _ServerPageState();
}

class _ServerPageState extends State<ServerPage> {
  List<String> _ips = const [];

  @override
  void initState() {
    super.initState();
    localIPv4Addresses().then((v) {
      if (mounted) setState(() => _ips = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final server = app.server;
    final settings = app.settings;

    return ListenableBuilder(
      listenable: server,
      builder: (context, _) {
        final running = server.running;
        return ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            const PageHeader(
              title: 'Servidor',
              subtitle: 'Comparte tus ROMs, BIOS y partidas con tus otros dispositivos',
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  RetroCard(
                    borderColor: running ? RetroColors.ok.withAlpha(150) : null,
                    child: Row(
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: running ? RetroColors.ok : RetroColors.textDim,
                            boxShadow: running
                                ? [BoxShadow(color: RetroColors.ok.withAlpha(150), blurRadius: 12)]
                                : null,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(running ? 'Servidor activo' : 'Servidor apagado',
                                  style: const TextStyle(
                                      fontSize: 18, fontWeight: FontWeight.w800)),
                              Text(
                                running
                                    ? '${app.localGameCount} juegos disponibles para otros dispositivos'
                                    : 'Enciéndelo para que tu teléfono pueda descargar juegos',
                                style: const TextStyle(color: RetroColors.textDim),
                              ),
                              if (server.error != null)
                                Text(server.error!,
                                    style: const TextStyle(color: RetroColors.danger)),
                            ],
                          ),
                        ),
                        Switch(
                          value: running,
                          onChanged: (v) => v
                              ? server.start(settings.serverPort)
                              : server.stop(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _InfoTile(
                        icon: Icons.lan_rounded,
                        title: 'Dirección (usa la primera en tu teléfono)',
                        lines: _ips.isEmpty
                            ? ['Sin red']
                            : ['${_ips.first}:${settings.serverPort}'],
                        footer: _ips.length > 1
                            ? 'Otras: ${_ips.skip(1).join(', ')}'
                            : null,
                      ),
                      _InfoTile(
                        icon: Icons.pin_rounded,
                        title: 'PIN',
                        lines: [settings.serverPin],
                        big: true,
                        trailing: IconButton(
                          tooltip: 'Generar otro PIN',
                          onPressed: () => setState(
                              () => settings.serverPin = AppSettings.generatePin()),
                          icon: const Icon(Icons.autorenew_rounded),
                        ),
                      ),
                      _InfoTile(
                        icon: Icons.badge_rounded,
                        title: 'Nombre visible',
                        lines: [settings.deviceName],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  RetroCard(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: SwitchListTile(
                      title: const Text('Iniciar el servidor al abrir la app'),
                      value: settings.autoStartServer,
                      onChanged: (v) => setState(() => settings.autoStartServer = v),
                    ),
                  ),
                  const SizedBox(height: 12),
                  RetroCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          const Text('Actividad',
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                          const Spacer(),
                          IconButton(
                            tooltip: 'Copiar',
                            onPressed: () => Clipboard.setData(
                                ClipboardData(text: server.log.join('\n'))),
                            icon: const Icon(Icons.copy_rounded, size: 18),
                          ),
                        ]),
                        const SizedBox(height: 4),
                        if (server.log.isEmpty)
                          const Text('Sin actividad todavía.',
                              style: TextStyle(color: RetroColors.textDim)),
                        for (final line in server.log.take(40))
                          Text(line,
                              style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                  color: RetroColors.textDim)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'La primera vez, Windows preguntará si permites que la app use la red: '
                    'marca "Redes privadas" y acepta.',
                    style: TextStyle(color: RetroColors.textDim, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<String> lines;
  final bool big;
  final Widget? trailing;
  final String? footer;
  const _InfoTile(
      {required this.icon,
      required this.title,
      required this.lines,
      this.big = false,
      this.trailing,
      this.footer});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 300,
      child: RetroCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: RetroColors.accent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(color: RetroColors.textDim, fontSize: 12)),
                  for (final l in lines)
                    SelectableText(l,
                        style: TextStyle(
                            fontSize: big ? 26 : 15,
                            fontWeight: FontWeight.w800,
                            letterSpacing: big ? 4 : 0)),
                  if (footer != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(footer!,
                          style: const TextStyle(
                              fontSize: 11, color: RetroColors.textDim)),
                    ),
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}
