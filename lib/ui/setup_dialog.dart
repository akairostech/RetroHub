import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../app_state.dart';
import '../core/app_log.dart';
import '../core/layout.dart';
import '../core/platforms.dart';
import 'theme.dart';

/// Diálogo para crear (o completar) la estructura de carpetas de la biblioteca.
Future<void> showCreateLibraryDialog(BuildContext context, {String? initialPath}) {
  return showDialog(
    context: context,
    builder: (_) => _CreateLibraryDialog(initialPath: initialPath),
  );
}

class _CreateLibraryDialog extends StatefulWidget {
  final String? initialPath;
  const _CreateLibraryDialog({this.initialPath});

  @override
  State<_CreateLibraryDialog> createState() => _CreateLibraryDialogState();
}

class _CreateLibraryDialogState extends State<_CreateLibraryDialog> {
  late final TextEditingController _path;
  bool _allPlatforms = true;
  bool _busy = false;
  String? _error;
  List<String>? _missing;

  @override
  void initState() {
    super.initState();
    _path = TextEditingController(text: widget.initialPath ?? defaultLibraryRoot());
    _refresh();
  }

  @override
  void dispose() {
    _path.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final path = _path.text.trim();
    if (path.isEmpty) return;
    final missing = await LibraryLayout(path).missingFolders(allPlatforms: _allPlatforms);
    if (mounted) setState(() => _missing = missing);
  }

  Future<void> _pick() async {
    final dir = await FilePicker.getDirectoryPath(dialogTitle: 'Dónde crear la biblioteca');
    if (dir == null) return;
    // Si la carpeta elegida no es ya una biblioteca, creamos "Emulation" dentro.
    final isLibrary = await Directory(p.join(dir, 'roms')).exists() ||
        p.basename(dir).toLowerCase() == 'emulation';
    _path.text = isLibrary ? dir : p.join(dir, 'Emulation');
    await _refresh();
  }

  Future<void> _create() async {
    final app = AppScope.read(context);
    final path = _path.text.trim();
    if (path.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (Platform.isAndroid && !app.storageGranted) {
        await app.requestStoragePermission();
        throw 'Concede "Acceso a todos los archivos" y vuelve a intentarlo.';
      }
      final created =
          await LibraryLayout(path).createStructure(allPlatforms: _allPlatforms);
      appLog.info('Biblioteca creada en $path ($created carpetas nuevas)');
      await app.setEmulationRoot(path);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context);
      messenger.showSnackBar(SnackBar(
          content: Text(created == 0
              ? 'La estructura ya estaba completa.'
              : 'Listo: se crearon $created carpetas en $path')));
    } catch (e, st) {
      appLog.error('No se pudo crear la biblioteca en $path', e, st);
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final missing = _missing;
    return AlertDialog(
      title: const Row(children: [
        Icon(Icons.create_new_folder_rounded, color: RetroColors.neon),
        SizedBox(width: 10),
        Text('Crear biblioteca'),
      ]),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'RetroHub creará las carpetas que falten. Lo que ya exista no se toca.',
              style: TextStyle(color: RetroColors.textDim),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _path,
                  decoration: const InputDecoration(labelText: 'Ubicación'),
                  onChanged: (_) => _refresh(),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _busy ? null : _pick,
                icon: const Icon(Icons.folder_open_rounded),
                label: const Text('Elegir'),
              ),
            ]),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Carpetas para todas las plataformas'),
              subtitle: Text('${kPlatforms.length} carpetas dentro de roms/ (snes, psx, gc...)'),
              value: _allPlatforms,
              onChanged: (v) {
                setState(() => _allPlatforms = v);
                _refresh();
              },
            ),
            const SizedBox(height: 4),
            const Text(
              'roms/{plataforma}   ·   bios/   ·   saves/\n'
              'storage/downloaded_media/   ·   storage/retrohub/',
              style: TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
            const SizedBox(height: 10),
            if (missing != null)
              Text(
                missing.isEmpty
                    ? 'La estructura ya está completa en esta ubicación.'
                    : 'Se crearán ${missing.length} carpetas.',
                style: TextStyle(
                    color: missing.isEmpty ? RetroColors.ok : RetroColors.neon,
                    fontWeight: FontWeight.w600),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: const TextStyle(color: RetroColors.danger)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton.icon(
          autofocus: true,
          onPressed: _busy ? null : _create,
          icon: _busy
              ? const SizedBox(
                  width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.check_rounded),
          label: Text(missing != null && missing.isEmpty ? 'Usar esta carpeta' : 'Crear'),
        ),
      ],
    );
  }
}
