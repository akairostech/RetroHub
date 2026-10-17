import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../core/file_tree.dart';
import '../core/models.dart';
import 'protocol.dart';

class ApiException implements Exception {
  final int status;
  final String message;
  ApiException(this.status, this.message);
  @override
  String toString() =>
      status == 403 ? 'PIN incorrecto' : 'Error del servidor ($status): $message';
}

/// Cliente para hablar con otro dispositivo que corre RetroHub en modo servidor.
class RetroClient {
  final ServerAddress server;
  final String pin;
  final http.Client _http = http.Client();

  RetroClient(this.server, this.pin);

  Map<String, String> get headers => {kPinHeader: pin};

  Uri _uri(String path, [Map<String, String>? q]) =>
      Uri.parse('${server.baseUrl}$path').replace(queryParameters: q);

  Future<dynamic> _getJson(String path, [Map<String, String>? q]) async {
    final res = await _http
        .get(_uri(path, q), headers: headers)
        .timeout(const Duration(seconds: 60));
    if (res.statusCode != 200) {
      throw ApiException(res.statusCode, utf8.decode(res.bodyBytes));
    }
    return jsonDecode(utf8.decode(res.bodyBytes));
  }

  Future<Map<String, dynamic>> info() async =>
      Map<String, dynamic>.from(await _getJson('/api/info') as Map);

  Future<Map<String, List<Game>>> library() async {
    final j = await _getJson('/api/library') as Map<String, dynamic>;
    final out = <String, List<Game>>{};
    for (final pl in (j['platforms'] as List).cast<Map<String, dynamic>>()) {
      final id = pl['id'] as String;
      out[id] = [
        for (final g in (pl['games'] as List).cast<Map<String, dynamic>>())
          Game.fromJson(id, g,
              coverUrl: g['cover'] == true ? coverUrl(id, g['file'] as String) : null)
      ];
    }
    return out;
  }

  String coverUrl(String platform, String file) =>
      _uri('/api/cover', {'platform': platform, 'file': file, 'pin': pin}).toString();

  Future<List<FileEntry>> tree(String area, {String path = '', bool hash = false}) async {
    final j = await _getJson('/api/tree', {
      'area': area,
      'path': path,
      if (hash) 'hash': '1',
    }) as Map<String, dynamic>;
    return [
      for (final f in (j['files'] as List).cast<Map<String, dynamic>>())
        FileEntry.fromJson(f)
    ];
  }

  /// Descarga un archivo a [dest] mostrando progreso.
  Future<void> download(
    String area,
    String relPath,
    File dest, {
    void Function(int received, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final req = http.Request('GET', _uri('/api/file', {'area': area, 'path': relPath}))
      ..headers.addAll(headers);
    final res = await _http.send(req);
    if (res.statusCode != 200) {
      final body = await res.stream.bytesToString();
      throw ApiException(res.statusCode, body);
    }
    final total = res.contentLength ?? -1;
    await dest.parent.create(recursive: true);
    final tmp = File('${dest.path}.retrohub_tmp');
    final sink = tmp.openWrite();
    var received = 0;
    try {
      await for (final chunk in res.stream) {
        if (isCancelled?.call() == true) throw const _Cancelled();
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      await sink.flush();
      await sink.close();
    } catch (e) {
      await sink.close();
      if (await tmp.exists()) await tmp.delete();
      if (e is _Cancelled) throw const DownloadCancelled();
      rethrow;
    }
    await replaceFile(tmp, dest);
    final mtime = int.tryParse(res.headers[kMtimeHeader] ?? '');
    if (mtime != null) {
      await dest.setLastModified(DateTime.fromMillisecondsSinceEpoch(mtime));
    }
  }

  /// Sube un archivo a saves/ en el servidor.
  Future<void> uploadSave(String relPath, File src) async {
    final st = await src.stat();
    final req = http.StreamedRequest(
        'PUT', _uri('/api/file', {'area': 'saves', 'path': relPath}))
      ..headers.addAll(headers)
      ..headers[kMtimeHeader] = '${st.modified.millisecondsSinceEpoch}'
      ..contentLength = st.size;
    src.openRead().listen(
          req.sink.add,
          onError: req.sink.addError,
          onDone: req.sink.close,
          cancelOnError: true,
        );
    final res = await _http.send(req);
    if (res.statusCode != 200) {
      throw ApiException(res.statusCode, await res.stream.bytesToString());
    }
    await res.stream.drain<void>();
  }

  void close() => _http.close();
}

class _Cancelled implements Exception {
  const _Cancelled();
}

class DownloadCancelled implements Exception {
  const DownloadCancelled();
  @override
  String toString() => 'Cancelado';
}
