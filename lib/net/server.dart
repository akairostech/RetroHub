import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import '../core/emudeck.dart';
import '../core/file_hash.dart';
import '../core/file_tree.dart';
import '../core/models.dart';
import 'discovery.dart';
import 'protocol.dart';

/// Servidor HTTP que corre dentro de la app de escritorio.
///
/// API (todas requieren el PIN en la cabecera x-retrohub-pin o ?pin=):
///   GET  /api/info
///   GET  /api/library                       -> plataformas y juegos
///   GET  /api/cover?platform=&file=          -> carátula
///   GET  /api/tree?area=roms|bios|saves&path=&hash=1
///   GET  /api/file?area=&path=               -> descarga
///   PUT  /api/file?area=saves&path=          -> subida (solo saves)
class RetroServer extends ChangeNotifier {
  final EmuLayout? Function() layout;
  final Map<String, List<Game>> Function() library;
  final String Function() pin;
  final String Function() deviceName;
  final HashCache hashes;

  RetroServer({
    required this.layout,
    required this.library,
    required this.pin,
    required this.deviceName,
    required this.hashes,
  });

  HttpServer? _http;
  final _discovery = DiscoveryResponder();
  final List<String> log = [];
  String? error;

  bool get running => _http != null;
  int? get port => _http?.port;

  Future<void> start(int port) async {
    await stop();
    error = null;
    try {
      final handler = const Pipeline()
          .addMiddleware(_logRequests())
          .addMiddleware(_auth())
          .addHandler(_route);
      _http = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
      _http!.autoCompress = false;
      try {
        await _discovery.start(name: deviceName(), httpPort: port);
      } catch (e) {
        _addLog('Aviso: descubrimiento automático no disponible ($e)');
      }
      _addLog('Servidor iniciado en el puerto $port');
    } catch (e) {
      error = 'No se pudo iniciar el servidor: $e';
      _http = null;
    }
    notifyListeners();
  }

  Future<void> stop() async {
    await _discovery.stop();
    final h = _http;
    _http = null;
    if (h != null) {
      await h.close(force: true);
      _addLog('Servidor detenido');
    }
    notifyListeners();
  }

  void _addLog(String msg) {
    final t = DateTime.now();
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    final ss = t.second.toString().padLeft(2, '0');
    log.insert(0, '$hh:$mm:$ss  $msg');
    if (log.length > 200) log.removeLast();
    notifyListeners();
  }

  Middleware _logRequests() => (inner) => (req) async {
        final res = await inner(req);
        final path = req.url.path;
        // No registramos cada carátula para no llenar el log.
        if (path != 'api/cover') {
          final q = req.url.queryParameters['path'] ?? '';
          _addLog('${req.method} /$path ${q.isEmpty ? '' : q} → ${res.statusCode}');
        }
        return res;
      };

  Middleware _auth() => (inner) => (req) {
        final expected = pin();
        if (expected.isNotEmpty) {
          final given = req.headers[kPinHeader] ?? req.url.queryParameters['pin'];
          if (given != expected) {
            return Response.forbidden(jsonEncode({'error': 'PIN incorrecto'}),
                headers: _jsonHeaders);
          }
        }
        return inner(req);
      };

  static const _jsonHeaders = {'content-type': 'application/json; charset=utf-8'};

  Response _json(Object data) => Response.ok(jsonEncode(data), headers: _jsonHeaders);

  Response _bad(String msg, [int code = 400]) =>
      Response(code, body: jsonEncode({'error': msg}), headers: _jsonHeaders);

  Future<Response> _route(Request req) async {
    final lay = layout();
    if (lay == null) return _bad('El servidor no tiene carpeta Emulation configurada', 503);
    try {
      final q = req.url.queryParameters;
      switch ((req.method, req.url.path)) {
        case ('GET', 'api/info'): {
          final lib = library();
          return _json({
            'app': kAppName,
            'v': kApiVersion,
            'name': deviceName(),
            'platforms': lib.length,
            'games': lib.values.fold<int>(0, (s, g) => s + g.length),
          });

        }
        case ('GET', 'api/library'): {
          return _json({
            'platforms': [
              for (final e in library().entries)
                {
                  'id': e.key,
                  'games': [for (final g in e.value) g.toJson()],
                }
            ]
          });

        }
        case ('GET', 'api/cover'): {
          final games = library()[q['platform']] ?? const <Game>[];
          final game = games.where((g) => g.fileName == q['file']).firstOrNull;
          final cover = game?.coverFile;
          if (cover == null) return Response.notFound('sin carátula');
          final f = File(cover);
          if (!await f.exists()) return Response.notFound('sin carátula');
          final ext = p.extension(cover).toLowerCase();
          return Response.ok(f.openRead(), headers: {
            'content-type': ext == '.png' ? 'image/png' : 'image/jpeg',
            'content-length': '${await f.length()}',
            'cache-control': 'max-age=86400',
          });

        }
        case ('GET', 'api/tree'): {
          final area = q['area'] ?? '';
          if (!kReadableAreas.contains(area)) return _bad('Área inválida');
          final root = safeJoin(lay.area(area), q['path'] ?? '');
          if (root == null) return _bad('Ruta inválida');
          final entries = await listTree(root, hashes: q['hash'] == '1' ? hashes : null);
          final prefix = toPosix(p.relative(root, from: lay.area(area)));
          return _json({
            'files': [
              for (final e in entries)
                FileEntry(prefix == '.' ? e.path : '$prefix/${e.path}', e.size,
                        e.mtime, e.sha1)
                    .toJson()
            ]
          });

        }
        case ('GET', 'api/file'): {
          final area = q['area'] ?? '';
          if (!kReadableAreas.contains(area)) return _bad('Área inválida');
          final path = safeJoin(lay.area(area), q['path'] ?? '');
          if (path == null) return _bad('Ruta inválida');
          final f = File(path);
          if (!await f.exists()) return Response.notFound('No existe');
          final st = await f.stat();
          return Response.ok(f.openRead(), headers: {
            'content-type': 'application/octet-stream',
            'content-length': '${st.size}',
            kMtimeHeader: '${st.modified.millisecondsSinceEpoch}',
          });

        }
        case ('PUT', 'api/file'): {
          final area = q['area'] ?? '';
          if (!kWritableAreas.contains(area)) return _bad('Solo se puede escribir en saves', 403);
          final rel = q['path'] ?? '';
          final path = safeJoin(lay.area(area), rel);
          if (path == null || path == lay.area(area)) return _bad('Ruta inválida');
          final dest = File(path);
          await dest.parent.create(recursive: true);
          final tmp = File('$path.retrohub_tmp');
          await req.read().pipe(tmp.openWrite());
          // Guardamos la versión anterior antes de reemplazarla.
          await backupToHistory(dest, lay.history, toPosix(rel));
          await replaceFile(tmp, dest);
          final mtime = int.tryParse(req.headers[kMtimeHeader] ?? '');
          if (mtime != null) {
            await dest.setLastModified(DateTime.fromMillisecondsSinceEpoch(mtime));
          }
          hashes.invalidate(dest.path);
          return _json({'ok': true, 'sha1': await hashes.sha1Of(dest)});
        }
      }
      return Response.notFound('No encontrado');
    } catch (e) {
      return _bad('$e', 500);
    }
  }
}
