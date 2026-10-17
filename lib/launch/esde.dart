import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

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

/// Lee la configuración de ES-DE (la que instala EmuDeck) para lanzar un juego
/// exactamente como lo haría ES-DE, respetando el emulador elegido en cada
/// sistema (alternativeEmulator del gamelist).
class EsdeConfig {
  final String esPath; // carpeta donde está ES-DE.exe
  final String userDir; // carpeta ES-DE (custom_systems, gamelists...)
  final String romPath;
  final Map<String, List<(String, String)>> systems; // id -> [(label, command)]
  final Map<String, List<(String, List<String>)>> emulatorRules; // NOMBRE -> [(tipo, entradas)]
  final Map<String, List<String>> coreRules;

  EsdeConfig._(this.esPath, this.userDir, this.romPath, this.systems, this.emulatorRules,
      this.coreRules);

  /// Busca ES-DE en las rutas típicas de EmuDeck. Devuelve null si no está.
  static Future<EsdeConfig?> load({required String romPath}) async {
    final candidates = <String>[];
    final env = Platform.environment;
    if (Platform.isWindows) {
      final appData = env['APPDATA'];
      if (appData != null) candidates.add(p.join(appData, 'EmuDeck', 'EmulationStation-DE'));
      final local = env['LOCALAPPDATA'];
      if (local != null) candidates.add(p.join(local, 'Programs', 'ES-DE'));
    } else {
      final home = env['HOME'];
      if (home != null) {
        // Instalación con recursos extraídos (no AppImage).
        candidates.add(p.join(home, 'Applications', 'ES-DE'));
      }
    }
    for (final dir in candidates) {
      final osName = Platform.isWindows ? 'windows' : 'linux';
      final res = Directory(p.join(dir, 'resources', 'systems', osName));
      if (!await res.exists()) continue;
      final userDir = await Directory(p.join(dir, 'ES-DE')).exists()
          ? p.join(dir, 'ES-DE')
          : p.join(env['HOME'] ?? env['USERPROFILE'] ?? dir, 'ES-DE');
      return parse(
        esPath: dir,
        userDir: userDir,
        romPath: romPath,
        systemsXml: [
          await _read(p.join(res.path, 'es_systems.xml')),
          await _read(p.join(userDir, 'custom_systems', 'es_systems.xml')),
        ],
        findRulesXml: [
          await _read(p.join(userDir, 'custom_systems', 'es_find_rules.xml')),
          await _read(p.join(res.path, 'es_find_rules.xml')),
        ],
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
  static EsdeConfig parse({
    required String esPath,
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
    return EsdeConfig._(esPath, userDir, romPath, systems, emulators, cores);
  }

  /// Emulador elegido para el sistema en ES-DE (gamelist.xml).
  Future<String?> alternativeEmulator(String system) async {
    final xml = await _read(p.join(userDir, 'gamelists', system, 'gamelist.xml'));
    if (xml == null) return null;
    final m = RegExp(r'<alternativeEmulator>\s*<label>([^<]+)</label>').firstMatch(xml);
    return m?.group(1)?.trim();
  }

  String _expandPathVars(String s, {String? emuPath}) {
    var out = s.replaceAll('%ESPATH%', esPath).replaceAll('%ROMPATH%', romPath);
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
  /// emulador elegido en ES-DE y si no está instalado, los demás en orden.
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

  /// Reemplaza las variables de ES-DE. Devuelve null si falta el emulador.
  LaunchCommand? expand(String template, String label, String romFile) {
    var t = template;
    // Opciones que no aplican fuera de ES-DE.
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
        .replaceAll('%ESPATH%', esPath)
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
