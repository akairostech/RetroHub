import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/models.dart';
import 'libretro.dart';

/// IDs de plataforma de IGDB para cada carpeta de EmuDeck.
const Map<String, List<int>> kIgdbPlatforms = {
  'nes': [18, 99], 'famicom': [99, 18], 'snes': [19, 58], 'sfc': [58, 19],
  'n64': [4], 'gc': [21], 'wii': [5], 'primehack': [5], 'wiiu': [41],
  'switch': [130], 'gb': [33], 'gbc': [22], 'gba': [24], 'nds': [20],
  'n3ds': [37], 'virtualboy': [87],
  'psx': [7], 'ps2': [8], 'ps3': [9], 'ps4': [48], 'psp': [38], 'psvita': [46],
  'mastersystem': [64], 'genesis': [29], 'megadrive': [29], 'segacd': [78],
  'sega32x': [30], 'saturn': [32], 'dreamcast': [23], 'gamegear': [35],
  'xbox': [11], 'xbox360': [12],
  'arcade': [52], 'mame': [52], 'fbneo': [52], 'model2': [52], 'model3': [52],
  'naomi': [52], 'atomiswave': [52], 'neogeo': [80, 79], 'ngpc': [120],
  'pcengine': [86], 'tg16': [86], 'atari2600': [59], 'atarilynx': [61],
  'atarijaguar': [62], 'wonderswancolor': [123], '3do': [50],
  'dos': [13], 'pc': [6], 'scummvm': [13, 6],
};

class IgdbResult {
  final GameMeta meta;
  final String? coverUrl;
  final String? screenshotUrl;
  IgdbResult(this.meta, this.coverUrl, this.screenshotUrl);
}

/// Fuente con cuenta gratuita: IGDB (usa credenciales de una app de Twitch).
/// Aporta descripción, valoración y portadas de cualquier sistema.
class IgdbSource {
  final http.Client client;
  final String clientId;
  final String clientSecret;
  String? _token;
  DateTime _tokenExpiry = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastCall = DateTime.fromMillisecondsSinceEpoch(0);

  IgdbSource(this.client, this.clientId, this.clientSecret);

  Future<String> _accessToken() async {
    if (_token != null && DateTime.now().isBefore(_tokenExpiry)) return _token!;
    final res = await client.post(Uri.parse(
        'https://id.twitch.tv/oauth2/token?client_id=${Uri.encodeComponent(clientId)}'
        '&client_secret=${Uri.encodeComponent(clientSecret)}&grant_type=client_credentials'));
    if (res.statusCode != 200) {
      throw Exception('IGDB: credenciales rechazadas (${res.statusCode}). '
          'Revisa el Client ID y el Client Secret en Ajustes.');
    }
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    _token = j['access_token'] as String;
    final secs = (j['expires_in'] as num?)?.toInt() ?? 3600;
    _tokenExpiry = DateTime.now().add(Duration(seconds: secs - 120));
    return _token!;
  }

  /// Prueba las credenciales (para el botón "Probar" de Ajustes).
  Future<void> verify() async {
    _token = null;
    await _accessToken();
  }

  Future<IgdbResult?> search(String platform, String title) async {
    final ids = kIgdbPlatforms[platform];
    // IGDB permite 4 peticiones por segundo.
    final wait = 300 - DateTime.now().difference(_lastCall).inMilliseconds;
    if (wait > 0) await Future.delayed(Duration(milliseconds: wait));
    _lastCall = DateTime.now();

    final safeTitle = title.replaceAll('"', ' ');
    final where = ids == null ? '' : ' where platforms = (${ids.join(',')});';
    final body = 'search "$safeTitle"; fields name,summary,first_release_date,'
        'genres.name,involved_companies.company.name,involved_companies.developer,'
        'involved_companies.publisher,cover.image_id,screenshots.image_id,'
        'total_rating,game_modes.name;$where limit 10;';
    final res = await client
        .post(Uri.parse('https://api.igdb.com/v4/games'),
            headers: {
              'Client-ID': clientId,
              'Authorization': 'Bearer ${await _accessToken()}',
              'Accept': 'application/json',
            },
            body: body)
        .timeout(const Duration(seconds: 30));
    if (res.statusCode == 401) _token = null;
    if (res.statusCode != 200) {
      throw Exception('IGDB respondió ${res.statusCode}: ${res.body}');
    }
    final list = (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
    final best = pickBest(list, title);
    return best == null ? null : toResult(best);
  }

  /// Elige el resultado cuyo nombre normalizado coincide mejor con el título.
  static Map<String, dynamic>? pickBest(List<Map<String, dynamic>> list, String title) {
    if (list.isEmpty) return null;
    final target = normalizeGameName(title);
    for (final g in list) {
      if (normalizeGameName(g['name'] as String? ?? '') == target) return g;
    }
    for (final g in list) {
      final n = normalizeGameName(g['name'] as String? ?? '');
      if (n.isNotEmpty && (n.startsWith(target) || target.startsWith(n))) return g;
    }
    return null; // Mejor no adivinar si no hay una coincidencia razonable.
  }

  static IgdbResult toResult(Map<String, dynamic> g) {
    String? companyWith(String role) {
      final list = (g['involved_companies'] as List?)?.cast<Map<String, dynamic>>();
      final c = list?.where((c) => c[role] == true).firstOrNull;
      return (c?['company'] as Map?)?['name'] as String?;
    }

    final ts = (g['first_release_date'] as num?)?.toInt();
    final genres = (g['genres'] as List?)
        ?.map((x) => (x as Map)['name'] as String)
        .take(2)
        .join(', ');
    final cover = (g['cover'] as Map?)?['image_id'] as String?;
    final shots = (g['screenshots'] as List?)?.cast<Map>();
    final shot = shots == null || shots.isEmpty ? null : shots.first['image_id'] as String?;
    final modes = (g['game_modes'] as List?)?.map((x) => (x as Map)['name']).toList() ?? [];
    return IgdbResult(
      GameMeta(
        name: g['name'] as String?,
        description: g['summary'] as String?,
        developer: companyWith('developer'),
        publisher: companyWith('publisher'),
        genre: (genres == null || genres.isEmpty) ? null : genres,
        year: ts == null ? null : DateTime.fromMillisecondsSinceEpoch(ts * 1000).year,
        players: modes.contains('Multiplayer') || modes.contains('Split screen') ? 2 : null,
        rating: (g['total_rating'] as num?)?.toDouble(),
        source: 'igdb',
      ),
      cover == null
          ? null
          : 'https://images.igdb.com/igdb/image/upload/t_cover_big_2x/$cover.jpg',
      shot == null
          ? null
          : 'https://images.igdb.com/igdb/image/upload/t_screenshot_big/$shot.jpg',
    );
  }
}
