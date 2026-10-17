import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '../compat/external_installs.dart';

/// Comando listo para ejecutar.
class LaunchCommand {
  final String executable;
  final List<String> arguments;
  final String? workingDirectory;
  final String label;
  const LaunchCommand(this.executable, this.arguments, this.label, {this.workingDirectory});

  @override
  String toString() => '$label: "$executable" ${arguments.map((a) => '"$a"').join(' ')}';
}

/// Perfil de lanzamiento: lista de sistemas con sus comandos y reglas para
/// encontrar cada emulador. Si el usuario ya tiene uno instalado, RetroHub lo
/// reutiliza para abrir cada juego con el emulador que eligió por sistema.
class LaunchProfile {
  final String installDir; // carpeta de instalación del perfil
  final String userDir; // carpeta de datos del usuario del perfil
  final String romPath;
  final Map<String, List<(String, String)>> systems; // id -> [(label, command)]
  final Map<String, List<(String, List<String>)>> emulatorRules; // NOMBRE -> [(tipo, entradas)]
  final Map<String, List<String>> coreRules;

  LaunchProfile._(this.installDir, this.userDir, this.romPath, this.systems, this.emulatorRules,
      this.coreRules);

  /// Busca un perfil de lanzamiento instalado. Devuelve null si no hay.
  static Future<LaunchProfile?> load({required String romPath}) async {
    for (final loc in ExternalInstalls.launchProfileLocations()) {
      if (!await File(loc.systemsFiles.first).exists()) continue;
      return parse(
        installDir: loc.installDir,
        userDir: loc.userDir,
        romPath: romPath,
        systemsXml: [for (final f in loc.systemsFiles) await _read(f)],
        findRulesXml: [for (final f in loc.rulesFiles) await _read(f)],
      );
    }
    return null;
  }

  static Future<String?> _read(String path) async {
    try {
      final f = File(path);
      return await f.exists() ? await f.readAsString() : null;
    } catch (_) {
      return null;
    }
  }

  /// [systemsXml]: el último tiene prioridad (custom_systems reemplaza al
  /// sistema completo). [findRulesXml]: el primero tiene prioridad.
  static LaunchProfile parse({
    required String installDir,
    required String userDir,
    required String romPath,
    required List<String?> systemsXml,
    required List<String?> findRulesXml,
  }) {
    final systems = <String, List<(String, String)>>{};
    for (final xml in systemsXml) {
      if (xml == null) continue;
      final doc = XmlDocument.parse(xml);
      for (final s in doc.findAllElements('system')) {
        final name = s.getElement('name')?.innerText.trim();
        if (name == null) continue;
        final cmds = [
          for (final c in s.findElements('command'))
            (c.getAttribute('label') ?? '', c.innerText.trim())
        ];
        if (cmds.isNotEmpty) systems[name] = cmds;
      }
    }
    final emulators = <String, List<(String, List<String>)>>{};
    final cores = <String, List<String>>{};
    for (final xml in findRulesXml) {
      if (xml == null) continue;
      final doc = XmlDocument.parse(xml);
      for (final e in doc.findAllElements('emulator')) {
        final name = e.getAttribute('name');
        if (name == null || emulators.containsKey(name)) continue;
        emulators[name] = [
          for (final r in e.findElements('rule'))
            (
              r.getAttribute('type') ?? '',
              [for (final en in r.findElements('entry')) en.innerText.trim()]
            )
        ];
      }
      for (final c in doc.findAllElements('core')) {
        final name = c.getAttribute('name');
        if (name == null || cores.containsKey(name)) continue;
        cores[name] = [
          for (final r in c.findElements('rule'))
            for (final en in r.findElements('entry')) en.innerText.trim()
        ];
      }
    }
    return LaunchProfile._(installDir, userDir, romPath, systems, emulators, cores);
  }

  /// Emulador elegido por el usuario para el sistema (si lo hay).
  Future<String?> alternativeEmulator(String system) async {
    final xml = await _read(ExternalInstalls.chosenEmulatorFile(userDir, system));
    if (xml == null) return null;
    final m = RegExp(r'<alternativeEmulator>\s*<label>([^<]+)</label>').firstMatch(xml);
    return m?.group(1)?.trim();
  }

  String _expandPathVars(String s, {String? emuPath}) {
    var out = s.replaceAll(ExternalInstalls.installDirVariable, installDir).replaceAll('%ROMPATH%', romPath);
    if (emuPath != null) out = out.replaceAll('%EMUPATH%', emuPath);
    return out.replaceAll('\\', Platform.pathSeparator).replaceAll('/', Platform.pathSeparator);
  }

  /// Ruta del ejecutable de un emulador según las reglas de búsqueda.
  String? findEmulator(String name) {
    final rules = emulatorRules[name];
    if (rules == null) return null;
    for (final (type, entries) in rules) {
      for (final entry in entries) {
        if (type == 'staticpath') {
          final path = p.normalize(_expandPathVars(entry));
          if (File(path).existsSync()) return path;
        } else if (type == 'systempath') {
          final found = _whichInPath(entry);
          if (found != null) return found;
        }
      }
    }
    return null;
  }

  String? findCoreDir(String name, String emulatorExe) {
    for (final entry in coreRules[name] ?? const <String>[]) {
      final dir = p.normalize(_expandPathVars(entry, emuPath: p.dirname(emulatorExe)));
      if (Directory(dir).existsSync()) return dir;
    }
    return null;
  }

  static String? _whichInPath(String exe) {
    final sep = Platform.isWindows ? ';' : ':';
    for (final dir in (Platform.environment['PATH'] ?? '').split(sep)) {
      if (dir.isEmpty) continue;
      final f = File(p.join(dir, exe));
      if (f.existsSync()) return f.path;
    }
    return null;
  }

  /// Construye el comando para [romFile] en [system]. Prueba primero el
  /// emulador elegido por el usuario y si no está instalado, los demás en orden.
  Future<LaunchCommand?> commandFor(String system, String romFile) async {
    final cmds = systems[system];
    if (cmds == null) return null;
    final preferred = await alternativeEmulator(system);
    final ordered = [
      ...cmds.where((c) => c.$1 == preferred),
      ...cmds.where((c) => c.$1 != preferred),
    ];
    for (final (label, template) in ordered) {
      final cmd = expand(template, label, romFile);
      if (cmd != null) return cmd;
    }
    return null;
  }

  /// Reemplaza las variables del comando. Devuelve null si falta el emulador.
  LaunchCommand? expand(String template, String label, String romFile) {
    var t = template;
    // Opciones de ventana que no aplican al lanzar desde RetroHub.
    t = t
        .replaceAll('%HIDEWINDOW%', '')
        .replaceAll('%ESCAPESPECIALS%', '')
        .replaceAll('%RUNINBACKGROUND%', '')
        .replaceAll(RegExp(r'%INJECT%=\S+'), '');
    if (t.contains('%EMULATOR_OS-SHELL%')) return null;

    String? emulatorExe;
    for (final m in RegExp(r'%EMULATOR_([A-Z0-9_\-]+)%').allMatches(t).toList()) {
      final exe = findEmulator(m.group(1)!);
      if (exe == null) return null;
      emulatorExe ??= exe;
      t = t.replaceFirst(m.group(0)!, '"$exe"');
    }
    for (final m in RegExp(r'%CORE_([A-Z0-9_\-]+)%').allMatches(t).toList()) {
      if (emulatorExe == null) return null;
      final dir = findCoreDir(m.group(1)!, emulatorExe);
      if (dir == null) return null;
      t = t.replaceFirst(m.group(0)!, '"$dir"');
    }

    final romDir = p.dirname(romFile);
    final base = p.basenameWithoutExtension(romFile);
    String? startDir;
    final sd = RegExp(r'%STARTDIR%=("[^"]*"|\S+)').firstMatch(t);
    if (sd != null) {
      var v = sd.group(1)!.replaceAll('"', '');
      v = v
          .replaceAll('%EMUDIR%', emulatorExe == null ? '' : p.dirname(emulatorExe))
          .replaceAll('%GAMEDIR%', romDir)
          .replaceAll('%GAMEDIRRAW%', romDir);
      startDir = v;
      t = t.replaceFirst(sd.group(0)!, '');
    }
    t = t
        .replaceAll('%ROMRAW%', romFile)
        .replaceAll('%ROM%', '"$romFile"')
        .replaceAll('%GAMEDIRRAW%', romDir)
        .replaceAll('%GAMEDIR%', '"$romDir"')
        .replaceAll('%BASENAME%', base)
        .replaceAll('%FILENAME%', p.basename(romFile))
        .replaceAll('%EMUDIR%', emulatorExe == null ? '' : p.dirname(emulatorExe))
        .replaceAll(ExternalInstalls.installDirVariable, installDir)
        .replaceAll('%ROMPATH%', romPath);
    if (RegExp(r'%[A-Z_]+%').hasMatch(t)) return null; // variable desconocida

    final parts = splitCommandLine(t);
    if (parts.isEmpty) return null;
    return LaunchCommand(parts.first, parts.sublist(1), label, workingDirectory: startDir);
  }
}

/// Divide una línea de comandos respetando comillas.
List<String> splitCommandLine(String s) {
  final out = <String>[];
  final buf = StringBuffer();
  var inQuotes = false;
  var hasToken = false;
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (c == '"') {
      inQuotes = !inQuotes;
      hasToken = true;
    } else if ((c == ' ' || c == '\t') && !inQuotes) {
      if (hasToken) {
        out.add(buf.toString());
        buf.clear();
        hasToken = false;
      }
    } else {
      buf.write(c);
      hasToken = true;
    }
  }
  if (hasToken) out.add(buf.toString());
  return out;
}
