import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../app_state.dart';
import '../core/app_log.dart';
import '../core/emudeck.dart';
import '../scrape/igdb.dart';
import 'theme.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _root;
  late final TextEditingController _name;
  late final TextEditingController _port;
  String? _msg;

  @override
  void initState() {
    super.initState();
    final s = AppScope.read(context).settings;
    _root = TextEditingController(text: s.emulationRoot ?? '');
    _name = TextEditingController(text: s.deviceName);
    _port = TextEditingController(text: '${s.serverPort}');
  }

  @override
  void dispose() {
    _root.dispose();
    _name.dispose();
    _port.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final dir = await FilePicker.getDirectoryPath(
        dialogTitle: 'Elige tu carpeta Emulation');
    if (dir != null) {
      _root.text = dir;
      await _applyRoot();
    }
  }

  Future<void> _detect() async {
    final found = await detectEmulationRoot();
    if (found == null) {
      setState(() => _msg = 'No se encontró una instalación de EmuDeck.');
      return;
    }
    _root.text = found;
    await _applyRoot();
  }

  Future<void> _applyRoot() async {
    final path = _root.text.trim();
    if (path.isEmpty) return;
    final ok = await Directory('$path${Platform.pathSeparator}roms').exists();
    setState(() => _msg = ok
        ? 'Carpeta guardada. Escaneando biblioteca...'
        : 'Ojo: no hay una carpeta "roms" dentro de esa ruta.');
    await AppScope.read(context).setEmulationRoot(path);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        const PageHeader(title: 'Ajustes'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              RetroCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Carpeta Emulation',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    const SizedBox(height: 4),
                    const Text(
                      'La misma estructura de EmuDeck: roms/{plataforma}, bios/, saves/{emulador}/ '
                      'y storage/downloaded_media (carátulas de ES-DE).',
                      style: TextStyle(color: RetroColors.textDim, fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _root,
                      decoration: const InputDecoration(
                        labelText: 'Ruta',
                        hintText: r'F:\Emulation  o  /storage/emulated/0/Emulation',
                      ),
                      onSubmitted: (_) => _applyRoot(),
                    ),
                    const SizedBox(height: 12),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      FilledButton.icon(
                        onPressed: _pick,
                        icon: const Icon(Icons.folder_open_rounded),
                        label: const Text('Elegir carpeta'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _detect,
                        icon: const Icon(Icons.auto_fix_high_rounded),
                        label: const Text('Detectar EmuDeck'),
                      ),
                      OutlinedButton(onPressed: _applyRoot, child: const Text('Guardar ruta')),
                    ]),
                    if (_msg != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(_msg!, style: const TextStyle(color: RetroColors.neon)),
                      ),
                  ],
                ),
              ),
              if (Platform.isAndroid) ...[
                const SizedBox(height: 12),
                RetroCard(
                  child: Row(children: [
                    Icon(
                        app.storageGranted
                            ? Icons.check_circle_rounded
                            : Icons.lock_rounded,
                        color: app.storageGranted ? RetroColors.ok : RetroColors.warn),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text('Acceso a todos los archivos (necesario para leer la carpeta Emulation)'),
                    ),
                    if (!app.storageGranted)
                      FilledButton(
                          onPressed: app.requestStoragePermission,
                          child: const Text('Conceder')),
                  ]),
                ),
              ],
              const SizedBox(height: 12),
              RetroCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Este dispositivo',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _name,
                      decoration: const InputDecoration(labelText: 'Nombre visible en la red'),
                      onChanged: (v) => app.settings.deviceName = v.trim(),
                    ),
                    if (isDesktop) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: 280,
                        child: TextField(
                          controller: _port,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'Puerto del servidor',
                              helperText: 'Reinicia el servidor al cambiarlo'),
                          onChanged: (v) {
                            final port = int.tryParse(v.trim());
                            if (port != null && port > 0 && port < 65536) {
                              app.settings.serverPort = port;
                            }
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const _IgdbCard(),
              const SizedBox(height: 12),
              const _LogCard(),
              const SizedBox(height: 12),
              const RetroCard(
                child: Text(
                  'RetroHub 0.3 · Las ROMs y BIOS solo se descargan del servidor a los clientes. '
                  'Las partidas (saves) se sincronizan en ambos sentidos y nunca se borran: '
                  'antes de reemplazar una se guarda una copia en saves/.retrohub_history.',
                  style: TextStyle(color: RetroColors.textDim, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Registro de actividad y errores (también se guarda en un archivo).
class _LogCard extends StatelessWidget {
  const _LogCard();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appLog,
      builder: (context, _) {
        final entries = appLog.entries;
        return RetroCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.receipt_long_rounded, color: RetroColors.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    appLog.errorCount == 0
                        ? 'Registro'
                        : 'Registro · ${appLog.errorCount} errores',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: appLog.errorCount == 0 ? null : RetroColors.danger),
                  ),
                ),
                IconButton(
                  tooltip: 'Copiar todo',
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: appLog.exportText()));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Registro copiado')));
                    }
                  },
                  icon: const Icon(Icons.copy_rounded, size: 18),
                ),
                IconButton(
                  tooltip: 'Limpiar',
                  onPressed: appLog.clear,
                  icon: const Icon(Icons.delete_sweep_rounded, size: 18),
                ),
              ]),
              if (appLog.filePath != null)
                SelectableText('Archivo: ${appLog.filePath}',
                    style: const TextStyle(fontSize: 11, color: RetroColors.textDim)),
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(maxHeight: 320),
                decoration: BoxDecoration(
                  color: RetroColors.bg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: entries.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('Sin actividad todavía.',
                            style: TextStyle(color: RetroColors.textDim)),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        padding: const EdgeInsets.all(10),
                        itemCount: entries.length,
                        itemBuilder: (context, i) {
                          final e = entries[i];
                          final color = switch (e.level) {
                            LogLevel.error => RetroColors.danger,
                            LogLevel.warn => RetroColors.warn,
                            LogLevel.info => RetroColors.textDim,
                          };
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: SelectableText(e.format(),
                                style: TextStyle(
                                    fontFamily: 'monospace', fontSize: 11, color: color)),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Credenciales opcionales de IGDB para el scraper.
class _IgdbCard extends StatefulWidget {
  const _IgdbCard();

  @override
  State<_IgdbCard> createState() => _IgdbCardState();
}

class _IgdbCardState extends State<_IgdbCard> {
  late final TextEditingController _id;
  late final TextEditingController _secret;
  bool _testing = false;
  String? _result;
  bool _ok = false;

  @override
  void initState() {
    super.initState();
    final s = AppScope.read(context).settings;
    _id = TextEditingController(text: s.igdbClientId);
    _secret = TextEditingController(text: s.igdbClientSecret);
  }

  @override
  void dispose() {
    _id.dispose();
    _secret.dispose();
    super.dispose();
  }

  void _save() {
    final s = AppScope.read(context).settings;
    s.igdbClientId = _id.text.trim();
    s.igdbClientSecret = _secret.text.trim();
  }

  Future<void> _test() async {
    _save();
    setState(() {
      _testing = true;
      _result = null;
    });
    final client = http.Client();
    try {
      await IgdbSource(client, _id.text.trim(), _secret.text.trim()).verify();
      _ok = true;
      _result = 'Conexión correcta. El scraper usará IGDB.';
    } catch (e) {
      _ok = false;
      _result = '$e';
    } finally {
      client.close();
    }
    if (mounted) setState(() => _testing = false);
  }

  @override
  Widget build(BuildContext context) {
    return RetroCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.auto_awesome_rounded, color: RetroColors.neon),
            SizedBox(width: 8),
            Text('Scraper · IGDB (opcional)',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          ]),
          const SizedBox(height: 6),
          const SelectableText(
            'Sin cuenta, el scraper usa libretro: carátulas, capturas, desarrollador, '
            'género, año y jugadores de consolas clásicas. Con IGDB (gratis) agrega '
            'descripciones y cubre consolas modernas como Switch, PS3 y PS4.\n'
            'Cómo obtener las credenciales: entra a dev.twitch.tv/console con tu cuenta '
            'de Twitch (activa la verificación en 2 pasos), registra una aplicación con '
            'URL de redirección http://localhost y categoría "Application Integration", '
            'y copia aquí su Client ID y un Client Secret nuevo.',
            style: TextStyle(color: RetroColors.textDim, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 12, runSpacing: 12, children: [
            SizedBox(
              width: 300,
              child: TextField(
                controller: _id,
                decoration: const InputDecoration(labelText: 'Client ID'),
                onChanged: (_) => _save(),
              ),
            ),
            SizedBox(
              width: 300,
              child: TextField(
                controller: _secret,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Client Secret'),
                onChanged: (_) => _save(),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            OutlinedButton.icon(
              onPressed: _testing ? null : _test,
              icon: _testing
                  ? const SizedBox(
                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.wifi_tethering_rounded),
              label: const Text('Probar conexión'),
            ),
            const SizedBox(width: 12),
            if (_result != null)
              Expanded(
                child: Text(_result!,
                    style: TextStyle(color: _ok ? RetroColors.ok : RetroColors.danger)),
              ),
          ]),
        ],
      ),
    );
  }
}
