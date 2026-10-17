import 'package:flutter/material.dart';

/// Información visual de cada plataforma (carpeta de EmuDeck / ES-DE).
class PlatformInfo {
  final String id;
  final String name;
  final String maker;
  final Color color;
  final int? year;

  /// Nombre del sistema en libretro-thumbnails (para carátulas de respaldo).
  final String? libretro;

  const PlatformInfo(this.id, this.name, this.maker, this.color,
      {this.year, this.libretro});

  String get shortName => name.length <= 14 ? name : id.toUpperCase();
}

const _nintendo = Color(0xFFE4000F);
const _sony = Color(0xFF2E6BD8);
const _sega = Color(0xFF1A8CFF);
const _microsoft = Color(0xFF2EA043);
const _arcade = Color(0xFFFFA000);
const _nec = Color(0xFFFF6B35);
const _snk = Color(0xFF00B8A9);
const _atari = Color(0xFFB0413E);
const _pc = Color(0xFF607D8B);
const _other = Color(0xFF8E5BFF);

const Map<String, PlatformInfo> kPlatforms = {
  // Nintendo
  'nes': PlatformInfo('nes', 'NES', 'Nintendo', _nintendo,
      year: 1983, libretro: 'Nintendo - Nintendo Entertainment System'),
  'famicom': PlatformInfo('famicom', 'Famicom', 'Nintendo', _nintendo,
      year: 1983, libretro: 'Nintendo - Nintendo Entertainment System'),
  'snes': PlatformInfo('snes', 'Super Nintendo', 'Nintendo', _nintendo,
      year: 1990, libretro: 'Nintendo - Super Nintendo Entertainment System'),
  'sfc': PlatformInfo('sfc', 'Super Famicom', 'Nintendo', _nintendo,
      year: 1990, libretro: 'Nintendo - Super Nintendo Entertainment System'),
  'n64': PlatformInfo('n64', 'Nintendo 64', 'Nintendo', _nintendo,
      year: 1996, libretro: 'Nintendo - Nintendo 64'),
  'gc': PlatformInfo('gc', 'GameCube', 'Nintendo', _nintendo,
      year: 2001, libretro: 'Nintendo - GameCube'),
  'wii': PlatformInfo('wii', 'Wii', 'Nintendo', _nintendo,
      year: 2006, libretro: 'Nintendo - Wii'),
  'wiiu': PlatformInfo('wiiu', 'Wii U', 'Nintendo', _nintendo, year: 2012),
  'switch': PlatformInfo('switch', 'Switch', 'Nintendo', _nintendo, year: 2017),
  'gb': PlatformInfo('gb', 'Game Boy', 'Nintendo', _nintendo,
      year: 1989, libretro: 'Nintendo - Game Boy'),
  'gbc': PlatformInfo('gbc', 'Game Boy Color', 'Nintendo', _nintendo,
      year: 1998, libretro: 'Nintendo - Game Boy Color'),
  'gba': PlatformInfo('gba', 'Game Boy Advance', 'Nintendo', _nintendo,
      year: 2001, libretro: 'Nintendo - Game Boy Advance'),
  'nds': PlatformInfo('nds', 'Nintendo DS', 'Nintendo', _nintendo,
      year: 2004, libretro: 'Nintendo - Nintendo DS'),
  'n3ds': PlatformInfo('n3ds', 'Nintendo 3DS', 'Nintendo', _nintendo,
      year: 2011, libretro: 'Nintendo - Nintendo 3DS'),
  'virtualboy': PlatformInfo('virtualboy', 'Virtual Boy', 'Nintendo', _nintendo,
      year: 1995, libretro: 'Nintendo - Virtual Boy'),
  'primehack': PlatformInfo('primehack', 'PrimeHack', 'Nintendo', _nintendo),
  // Sony
  'psx': PlatformInfo('psx', 'PlayStation', 'Sony', _sony,
      year: 1994, libretro: 'Sony - PlayStation'),
  'ps2': PlatformInfo('ps2', 'PlayStation 2', 'Sony', _sony,
      year: 2000, libretro: 'Sony - PlayStation 2'),
  'ps3': PlatformInfo('ps3', 'PlayStation 3', 'Sony', _sony, year: 2006),
  'ps4': PlatformInfo('ps4', 'PlayStation 4', 'Sony', _sony, year: 2013),
  'psp': PlatformInfo('psp', 'PSP', 'Sony', _sony,
      year: 2004, libretro: 'Sony - PlayStation Portable'),
  'psvita': PlatformInfo('psvita', 'PS Vita', 'Sony', _sony,
      year: 2011, libretro: 'Sony - PlayStation Vita'),
  // Sega
  'mastersystem': PlatformInfo('mastersystem', 'Master System', 'Sega', _sega,
      year: 1985, libretro: 'Sega - Master System - Mark III'),
  'genesis': PlatformInfo('genesis', 'Genesis', 'Sega', _sega,
      year: 1988, libretro: 'Sega - Mega Drive - Genesis'),
  'megadrive': PlatformInfo('megadrive', 'Mega Drive', 'Sega', _sega,
      year: 1988, libretro: 'Sega - Mega Drive - Genesis'),
  'segacd': PlatformInfo('segacd', 'Sega CD', 'Sega', _sega,
      year: 1991, libretro: 'Sega - Mega-CD - Sega CD'),
  'sega32x': PlatformInfo('sega32x', '32X', 'Sega', _sega,
      year: 1994, libretro: 'Sega - 32X'),
  'saturn': PlatformInfo('saturn', 'Saturn', 'Sega', _sega,
      year: 1994, libretro: 'Sega - Saturn'),
  'dreamcast': PlatformInfo('dreamcast', 'Dreamcast', 'Sega', _sega,
      year: 1998, libretro: 'Sega - Dreamcast'),
  'gamegear': PlatformInfo('gamegear', 'Game Gear', 'Sega', _sega,
      year: 1990, libretro: 'Sega - Game Gear'),
  'model2': PlatformInfo('model2', 'Sega Model 2', 'Sega', _arcade),
  'model3': PlatformInfo('model3', 'Sega Model 3', 'Sega', _arcade),
  'naomi': PlatformInfo('naomi', 'NAOMI', 'Sega', _arcade),
  'atomiswave': PlatformInfo('atomiswave', 'Atomiswave', 'Sammy', _arcade),
  // Microsoft
  'xbox': PlatformInfo('xbox', 'Xbox', 'Microsoft', _microsoft,
      year: 2001, libretro: 'Microsoft - Xbox'),
  'xbox360': PlatformInfo('xbox360', 'Xbox 360', 'Microsoft', _microsoft,
      year: 2005),
  // Arcade
  'arcade': PlatformInfo('arcade', 'Arcade', 'Arcade', _arcade, libretro: 'MAME'),
  'mame': PlatformInfo('mame', 'MAME', 'Arcade', _arcade, libretro: 'MAME'),
  'fbneo': PlatformInfo('fbneo', 'FinalBurn Neo', 'Arcade', _arcade,
      libretro: 'FBNeo - Arcade Games'),
  'neogeo': PlatformInfo('neogeo', 'Neo Geo', 'SNK', _snk,
      year: 1990, libretro: 'SNK - Neo Geo'),
  'ngpc': PlatformInfo('ngpc', 'Neo Geo Pocket Color', 'SNK', _snk,
      year: 1999, libretro: 'SNK - Neo Geo Pocket Color'),
  // Otros
  'pcengine': PlatformInfo('pcengine', 'PC Engine', 'NEC', _nec,
      year: 1987, libretro: 'NEC - PC Engine - TurboGrafx 16'),
  'tg16': PlatformInfo('tg16', 'TurboGrafx-16', 'NEC', _nec,
      year: 1989, libretro: 'NEC - PC Engine - TurboGrafx 16'),
  'atari2600': PlatformInfo('atari2600', 'Atari 2600', 'Atari', _atari,
      year: 1977, libretro: 'Atari - 2600'),
  'atarilynx': PlatformInfo('atarilynx', 'Atari Lynx', 'Atari', _atari,
      year: 1989, libretro: 'Atari - Lynx'),
  'atarijaguar': PlatformInfo('atarijaguar', 'Atari Jaguar', 'Atari', _atari,
      year: 1993, libretro: 'Atari - Jaguar'),
  'wonderswancolor': PlatformInfo(
      'wonderswancolor', 'WonderSwan Color', 'Bandai', _other,
      year: 2000, libretro: 'Bandai - WonderSwan Color'),
  '3do': PlatformInfo('3do', '3DO', '3DO', _other,
      year: 1993, libretro: 'The 3DO Company - 3DO'),
  'scummvm': PlatformInfo('scummvm', 'ScummVM', 'PC', _pc),
  'dos': PlatformInfo('dos', 'MS-DOS', 'PC', _pc),
  'pc': PlatformInfo('pc', 'PC', 'PC', _pc),
};

PlatformInfo platformInfo(String id) =>
    kPlatforms[id] ?? PlatformInfo(id, id.toUpperCase(), 'Otro', _other);

/// Orden para mostrar: fabricante, luego año.
int comparePlatforms(String a, String b) {
  const makers = ['Nintendo', 'Sony', 'Sega', 'Microsoft', 'SNK', 'NEC', 'Atari'];
  final pa = platformInfo(a), pb = platformInfo(b);
  int rank(PlatformInfo p) {
    final i = makers.indexOf(p.maker);
    return i < 0 ? makers.length : i;
  }

  final r = rank(pa).compareTo(rank(pb));
  if (r != 0) return r;
  final y = (pa.year ?? 9999).compareTo(pb.year ?? 9999);
  if (y != 0) return y;
  return pa.name.compareTo(pb.name);
}

/// Ícono (SVG en assets/consoles) para cada plataforma.
/// Logos de Simple Icons (CC0) y pictogramas de Material Design Icons
/// (Pictogrammers Free License). Ver README → Créditos.
String platformIconAsset(String id) {
  const byId = {
    'psx': 'playstation',
    'ps2': 'playstation2',
    'ps3': 'playstation3',
    'ps4': 'playstation4',
    'psp': 'psp',
    'psvita': 'psvita',
    'switch': 'switch',
    'wii': 'wii',
    'primehack': 'wii',
    'wiiu': 'wiiu',
    'gb': 'handheld',
    'gbc': 'handheld',
    'gba': 'handheld',
    'nds': 'handheld',
    'n3ds': 'handheld',
    'virtualboy': 'handheld',
    'gamegear': 'handheld',
    'ngpc': 'handheld',
    'wonderswancolor': 'handheld',
    'atarilynx': 'handheld',
    'nes': 'classic_pad',
    'famicom': 'classic_pad',
    'snes': 'classic_pad',
    'sfc': 'classic_pad',
    'pcengine': 'classic_pad',
    'tg16': 'classic_pad',
    'n64': 'modern_pad',
    'gc': 'round_pad',
    'xbox': 'xbox',
    'xbox360': 'xbox',
    'neogeo': 'pacman',
    '3do': 'disc',
    'scummvm': 'floppy',
    'dos': 'floppy',
    'pc': 'floppy',
  };
  const byMaker = {
    'Sony': 'playstation',
    'Sega': 'sega',
    'Atari': 'atari',
    'Microsoft': 'xbox',
    'Arcade': 'arcade',
    'Sammy': 'arcade',
    'SNK': 'pacman',
    'PC': 'floppy',
    'Nintendo': 'classic_pad',
  };
  final name = byId[id] ?? byMaker[platformInfo(id).maker] ?? 'generic';
  return 'assets/consoles/$name.svg';
}
