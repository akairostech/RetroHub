import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../core/app_log.dart';
import '../compat/external_installs.dart';
import '../core/layout.dart';
import '../core/models.dart';
import '../core/settings.dart';
import 'launch_profile.dart';

/// Cómo lanzar cada sistema sin perfil de lanzamiento: scripts de
/// {raíz}/tools/launchers y núcleo de RetroArch de respaldo.
class _DesktopRecipe {
  final List<String> standalone; // prefijos del nombre del lanzador
  final String? core; // núcleo de RetroArch (sin _libretro)
  const _DesktopRecipe({this.standalone = const [], this.core});
}

const Map<String, _DesktopRecipe> _desktop = {
  'nes': _DesktopRecipe(core: 'mesen'),
  'famicom': _DesktopRecipe(core: 'mesen'),
  'snes': _DesktopRecipe(core: 'snes9x'),
  'sfc': _DesktopRecipe(core: 'snes9x'),
  'n64': _DesktopRecipe(core: 'mupen64plus_next'),
  'gb': _DesktopRecipe(core: 'gambatte'),
  'gbc': _DesktopRecipe(core: 'gambatte'),
  'gba': _DesktopRecipe(core: 'mgba'),
  'nds': _DesktopRecipe(standalone: ['melonds'], core: 'melonds'),
  'n3ds': _DesktopRecipe(standalone: ['azahar', 'citra', 'lime3ds']),
  'gc': _DesktopRecipe(standalone: ['dolphin']),
  'wii': _DesktopRecipe(standalone: ['dolphin']),
  'primehack': _DesktopRecipe(standalone: ['primehack']),
  'wiiu': _DesktopRecipe(standalone: ['cemu']),
  'switch': _DesktopRecipe(standalone: ['ryujinx', 'eden', 'citron', 'yuzu']),
  'virtualboy': _DesktopRecipe(core: 'mednafen_vb'),
  'psx': _DesktopRecipe(standalone: ['duckstation'], core: 'swanstation'),
  'ps2': _DesktopRecipe(standalone: ['pcsx2']),
  'ps3': _DesktopRecipe(standalone: ['rpcs3']),
  'ps4': _DesktopRecipe(standalone: ['shadps4']),
  'psp': _DesktopRecipe(standalone: ['ppsspp'], core: 'ppsspp'),
  'psvita': _DesktopRecipe(standalone: ['vita3k']),
  'mastersystem': _DesktopRecipe(core: 'genesis_plus_gx'),
  'genesis': _DesktopRecipe(core: 'genesis_plus_gx'),
  'megadrive': _DesktopRecipe(core: 'genesis_plus_gx'),
  'segacd': _DesktopRecipe(core: 'genesis_plus_gx'),
  'gamegear': _DesktopRecipe(core: 'genesis_plus_gx'),
  'sega32x': _DesktopRecipe(core: 'picodrive'),
  'saturn': _DesktopRecipe(core: 'mednafen_saturn'),
  'dreamcast': _DesktopRecipe(standalone: ['flycast'], core: 'flycast'),
  'naomi': _DesktopRecipe(core: 'flycast'),
  'atomiswave': _DesktopRecipe(core: 'flycast'),
  'model2': _DesktopRecipe(standalone: ['model2']),
  'model3': _DesktopRecipe(standalone: ['supermodel']),
  'xbox': _DesktopRecipe(standalone: ['xemu']),
  'xbox360': _DesktopRecipe(standalone: ['xenia']),
  'arcade': _DesktopRecipe(core: 'mame'),
  'mame': _DesktopRecipe(core: 'mame'),
  'fbneo': _DesktopRecipe(core: 'fbneo'),
  'neogeo': _DesktopRecipe(core: 'fbneo'),
  'pcengine': _DesktopRecipe(core: 'mednafen_pce'),
  'tg16': _DesktopRecipe(core: 'mednafen_pce'),
  'atari2600': _DesktopRecipe(core: 'stella'),
  'atarilynx': _DesktopRecipe(core: 'handy'),
  'atarijaguar': _DesktopRecipe(core: 'virtualjaguar'),
  'ngpc': _DesktopRecipe(core: 'mednafen_ngp'),
  'wonderswancolor': _DesktopRecipe(core: 'mednafen_wswan'),
  '3do': _DesktopRecipe(core: 'opera'),
  'dos': _DesktopRecipe(core: 'dosbox_pure'),
  'scummvm': _DesktopRecipe(standalone: ['scummvm'], core: 'scummvm'),
};

/// Emuladores de Android (paquete, actividad y cómo recibe el juego).
class _AndroidApp {
  final String name;
  final List<String> packages;
  final String? activity;
  final String mode; // retroarch | extra | extraArray | view
  final String? extraKey;
  const _AndroidApp(this.name, this.packages, this.activity, this.mode, [this.extraKey]);
}

const _retroarch = _AndroidApp('RetroArch', ['com.retroarch.aarch64', 'com.retroarch', 'com.retroarch.ra32'],
    'com.retroarch.browser.retroactivity.RetroActivityFuture', 'retroarch');
const _ppsspp = _AndroidApp('PPSSPP', ['org.ppsspp.ppssppgold', 'org.ppsspp.ppsspp'],
    'org.ppsspp.ppsspp.PpssppActivity', 'view');
const _dolphin = _AndroidApp('Dolphin', ['org.dolphinemu.dolphinemu', 'org.dolphinemu.mmjr'],
    'org.dolphinemu.dolphinemu.ui.main.MainActivity', 'extraArray', 'AutoStartFiles');
const _nethersx2 = _AndroidApp('NetherSX2', ['xyz.aethersx2.android'],
    'xyz.aethersx2.android.EmulationActivity', 'extra', 'bootPath');
const _duckstation = _AndroidApp('DuckStation', ['com.github.stenzek.duckstation'],
    'com.github.stenzek.duckstation.EmulationActivity', 'extra', 'bootPath');

/// Núcleos de RetroArch para Android.
const Map<String, String> _androidCores = {
  'nes': 'mesen', 'famicom': 'mesen', 'snes': 'snes9x', 'sfc': 'snes9x',
  'n64': 'mupen64plus_next_gles3', 'gb': 'gambatte', 'gbc': 'gambatte', 'gba': 'mgba',
  'nds': 'melonds', 'virtualboy': 'mednafen_vb', 'mastersystem': 'genesis_plus_gx',
  'genesis': 'genesis_plus_gx', 'megadrive': 'genesis_plus_gx', 'segacd': 'genesis_plus_gx',
  'gamegear': 'genesis_plus_gx', 'sega32x': 'picodrive', 'saturn': 'yabasanshiro',
  'dreamcast': 'flycast', 'naomi': 'flycast', 'atomiswave': 'flycast',
  'arcade': 'mame2003_plus', 'mame': 'mame2003_plus', 'fbneo': 'fbneo', 'neogeo': 'fbneo',
  'pcengine': 'mednafen_pce_fast', 'tg16': 'mednafen_pce_fast', 'atari2600': 'stella',
  'atarilynx': 'handy', 'ngpc': 'mednafen_ngp', 'wonderswancolor': 'mednafen_wswan',
  '3do': 'opera', 'dos': 'dosbox_pure', 'psx': 'pcsx_rearmed',
};

/// Emuladores propios por sistema (se prueban en orden; si ninguno está
/// instalado se usa RetroArch con el núcleo correspondiente).
const Map<String, List<_AndroidApp>> _androidStandalone = {
  'psp': [_ppsspp],
  'gc': [_dolphin],
  'wii': [_dolphin],
  'ps2': [_nethersx2],
  'psx': [_duckstation],
};

/// Lanza juegos con el emulador correcto en cada sistema operativo.
class GameLauncher {
  static const _channel = MethodChannel('retro_hub/launch');
  LaunchProfile? _profile;
  bool _profileLoaded = false;

  /// Lanza [game]. Devuelve null si todo salió bien o un mensaje de error.
  Future<String?> launch(Game game, LibraryLayout layout, AppSettings settings) async {
    final rom = game.localPath;
    if (rom == null) return 'Este juego no está en este dispositivo.';
    try {
      final custom = settings.launchCommand(game.platform);
      if (custom.isNotEmpty) return await _runCustom(custom, rom, game);
      if (Platform.isAndroid) return await _launchAndroid(game, rom);
      return await _launchDesktop(game, rom, layout);
    } catch (e, st) {
      appLog.error('No se pudo abrir ${game.title}', e, st);
      return '$e';
    }
  }

  Future<String?> _runCustom(String template, String rom, Game game) async {
    final parts = splitCommandLine(template
        .replaceAll('{rom}', '"$rom"')
        .replaceAll('{romdir}', '"${p.dirname(rom)}"')
        .replaceAll('{name}', p.basenameWithoutExtension(rom)));
    if (parts.isEmpty) return 'El comando personalizado está vacío.';
    if (Platform.isAndroid) return 'Los comandos personalizados solo funcionan en PC.';
    return _start(LaunchCommand(parts.first, parts.sublist(1), 'Personalizado'), game);
  }

  Future<String?> _launchDesktop(Game game, String rom, LibraryLayout layout) async {
    // 1) Perfil de lanzamiento instalado (respeta el emulador elegido).
    if (!_profileLoaded) {
      _profileLoaded = true;
      _profile = await LaunchProfile.load(romPath: layout.roms);
      appLog.info(_profile == null
          ? 'Sin perfil de lanzamiento instalado; se usarán los lanzadores de tools/launchers'
          : 'Perfil de lanzamiento cargado desde ${_profile!.installDir}');
    }
    final profileCmd = await _profile?.commandFor(game.platform, rom);
    if (profileCmd != null) return _start(profileCmd, game);

    // 2) Scripts de tools/launchers / RetroArch.
    final recipe = _desktop[game.platform];
    if (recipe == null) {
      return 'No sé qué emulador usar para ${game.platform}. '
          'Configura un comando en Ajustes → Emuladores.';
    }
    final launchers = Directory(layout.launchers);
    for (final prefix in recipe.standalone) {
      final script = await _findLauncher(launchers, prefix);
      if (script != null) return _start(_scriptCommand(script, [rom], prefix), game);
    }
    if (recipe.core != null) {
      final cmd = await _retroarchCommand(launchers, recipe.core!, rom);
      if (cmd != null) return _start(cmd, game);
    }
    return 'No encontré el emulador para ${game.platform}. '
        'Revisa que esté instalado o configura un comando en Ajustes → Emuladores.';
  }

  Future<String?> _findLauncher(Directory dir, String prefix) async {
    if (!await dir.exists()) return null;
    final ext = Platform.isWindows ? '.ps1' : '.sh';
    await for (final f in dir.list()) {
      final name = p.basename(f.path).toLowerCase();
      if (f is File && name.startsWith(prefix) && name.endsWith(ext)) return f.path;
    }
    return null;
  }

  LaunchCommand _scriptCommand(String script, List<String> args, String label) {
    if (Platform.isWindows) {
      return LaunchCommand('powershell.exe',
          ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', script, ...args],
          label);
    }
    return LaunchCommand('bash', [script, ...args], label);
  }

  Future<LaunchCommand?> _retroarchCommand(Directory launchers, String core, String rom) async {
    final env = Platform.environment;
    if (Platform.isWindows) {
      final base = ExternalInstalls.windowsRetroArchDir();
      final exe = File(p.join(base, 'retroarch.exe'));
      final coreFile = File(p.join(base, 'cores', '${core}_libretro.dll'));
      if (await exe.exists() && await coreFile.exists()) {
        return LaunchCommand(exe.path, ['-L', coreFile.path, rom], 'RetroArch ($core)');
      }
      return null;
    }
    final home = env['HOME'] ?? '';
    for (final dir in [
      p.join(home, '.var', 'app', 'org.libretro.RetroArch', 'config', 'retroarch', 'cores'),
      p.join(home, '.config', 'retroarch', 'cores'),
    ]) {
      final coreFile = File(p.join(dir, '${core}_libretro.so'));
      if (!await coreFile.exists()) continue;
      final script = await _findLauncher(launchers, 'retroarch');
      if (script != null) {
        return _scriptCommand(script, ['-L', coreFile.path, rom], 'RetroArch ($core)');
      }
      if (dir.contains('org.libretro.RetroArch')) {
        return LaunchCommand('flatpak',
            ['run', 'org.libretro.RetroArch', '-L', coreFile.path, rom], 'RetroArch ($core)');
      }
      return LaunchCommand('retroarch', ['-L', coreFile.path, rom], 'RetroArch ($core)');
    }
    return null;
  }

  Future<String?> _start(LaunchCommand cmd, Game game) async {
    appLog.info('Jugar ${game.title} → $cmd');
    await Process.start(cmd.executable, cmd.arguments,
        workingDirectory: cmd.workingDirectory, mode: ProcessStartMode.detached);
    return null;
  }

  Future<String?> _launchAndroid(Game game, String rom) async {
    final core = _androidCores[game.platform];
    final specs = [
      for (final app in _androidStandalone[game.platform] ?? const <_AndroidApp>[])
        _spec(app, rom),
      if (core != null) _spec(_retroarch, rom, core: core),
    ];
    if (specs.isEmpty) {
      // Sin receta: que Android pregunte con qué app abrirlo.
      specs.add({'mode': 'view', 'path': rom, 'name': 'un emulador'});
    }
    final missing = <String>[];
    for (final spec in specs) {
      appLog.info('Jugar ${game.title} en Android: $spec');
      final err = await _channel.invokeMethod<String>('launch', spec);
      if (err == null) return null;
      if (!err.startsWith('NOT_INSTALLED:')) return err;
      missing.add(err.substring('NOT_INSTALLED:'.length));
    }
    return 'No está instalado ningún emulador para este sistema '
        '(${missing.join(' ni ')}). Instálalo desde su tienda o su página oficial.';
  }

  Map<String, Object?> _spec(_AndroidApp app, String rom, {String? core}) => {
        'name': app.name,
        'packages': app.packages,
        'activity': app.activity,
        'mode': app.mode,
        'extraKey': app.extraKey,
        'path': rom,
        if (core != null) 'core': core,
      };
}
