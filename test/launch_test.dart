import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:retro_hub/core/library_tools.dart';
import 'package:retro_hub/core/models.dart';
import 'package:retro_hub/launch/launch_profile.dart';

void main() {
  test('divide comandos respetando comillas', () {
    expect(splitCommandLine('"C:\\a b\\ra.exe" -L "C:\\c d"\\core.dll "x y.sfc"'),
        ['C:\\a b\\ra.exe', '-L', 'C:\\c d\\core.dll', 'x y.sfc']);
  });

  test('perfil de lanzamiento: respeta el emulador elegido y expande variables', () async {
    final root = await Directory.systemTemp.createTemp('profile');
    final es = p.join(root.path, 'frontend-app');
    final emus = p.join(root.path, 'Emulators');
    await File(p.join(emus, 'Dolphin-x64', 'Dolphin.exe')).create(recursive: true);
    await File(p.join(emus, 'RetroArch', 'retroarch.exe')).create(recursive: true);
    await Directory(p.join(emus, 'RetroArch', 'cores')).create(recursive: true);
    final userDir = p.join(root.path, 'user');
    await File(p.join(userDir, 'gamelists', 'gc', 'gamelist.xml')).create(recursive: true);
    await File(p.join(userDir, 'gamelists', 'gc', 'gamelist.xml')).writeAsString(
        '<alternativeEmulator>\n\t<label>Dolphin (Standalone)</label>\n</alternativeEmulator>\n<gameList />');

    final cfg = LaunchProfile.parse(
      installDir: es,
      userDir: userDir,
      romPath: p.join(root.path, 'roms'),
      systemsXml: [
        '''<systemList><system><name>gc</name>
          <command label="Dolphin">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/dolphin_libretro.dll %ROM%</command>
          <command label="Dolphin (Standalone)">%EMULATOR_DOLPHIN% -b -e %ROM%</command>
        </system>
        <system><name>snes</name>
          <command label="Snes9x">%HIDEWINDOW% %EMULATOR_RETROARCH% -L %CORE_RETROARCH%/snes9x_libretro.dll %ROM%</command>
        </system></systemList>''',
      ],
      findRulesXml: [
        '''<ruleList>
          <emulator name="RETROARCH"><rule type="staticpath"><entry>%ESPATH%/../Emulators/RetroArch/retroarch.exe</entry></rule></emulator>
          <core name="RETROARCH"><rule type="corepath"><entry>%EMUPATH%/cores</entry></rule></core>
          <emulator name="DOLPHIN"><rule type="staticpath"><entry>%ESPATH%/../Emulators/Dolphin-x64/Dolphin.exe</entry></rule></emulator>
        </ruleList>''',
      ],
    );

    final rom = p.join(root.path, 'roms', 'gc', 'Mario Sunshine.rvz');
    final gc = (await cfg.commandFor('gc', rom))!;
    expect(gc.label, 'Dolphin (Standalone)');
    expect(p.basename(gc.executable), 'Dolphin.exe');
    expect(gc.arguments, ['-b', '-e', rom]);

    final snes = (await cfg.commandFor('snes', p.join(root.path, 'roms', 'snes', 'a b.sfc')))!;
    expect(p.basename(snes.executable), 'retroarch.exe');
    expect(snes.arguments.first, '-L');
    expect(p.basename(snes.arguments[1]), 'snes9x_libretro.dll');
    expect(p.basename(snes.arguments.last), 'a b.sfc');

    try {
      await root.delete(recursive: true);
    } on FileSystemException catch (_) {}
  });

  test('lee System.dat de libretro', () {
    final dat = parseSystemDat('''
game (
	name "System"
	comment "Sony - PlayStation"
	rom ( name scph5501.bin size 524288 crc 8D8CB7E4 md5 490f666e1afb15b7362b406ed1cea246 sha1 0555c6fae8906f3f09baf5988f00e55f88e9f30b )
	comment "Sony - PlayStation 2"
	rom ( name "pcsx2/bios/ps2-0100jd-20000117.bin" size 4194304 crc 5A04500C md5 32f2e4d5ff5ee11072a6bc45530f5765 sha1 5b33 )
)''');
    expect(dat['Sony - PlayStation']!.single.name, 'scph5501.bin');
    expect(dat['Sony - PlayStation 2']!.single.baseName, 'ps2-0100jd-20000117.bin');
  });

  test('detecta duplicados por nombre', () {
    Game g(String f, int size) {
      final (t, tags) = parseTitle(f);
      return Game(platform: 'snes', fileName: f, title: t, tags: tags, size: size);
    }

    final groups = findDuplicates({
      'snes': [
        g('Super Mario World (U) [!].smc', 512),
        g('Super Mario World (USA).sfc', 512),
        g('Chrono Trigger (USA).sfc', 4096),
      ]
    });
    expect(groups, hasLength(1));
    expect(groups.single.games, hasLength(2));
    expect(groups.single.sameSize, isTrue);
    expect(groups.single.wastedBytes, 512);
  });
}
