import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../core/emudeck.dart';
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
              const RetroCard(
                child: Text(
                  'RetroHub 0.2 · Las ROMs y BIOS solo se descargan del servidor a los clientes. '
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
