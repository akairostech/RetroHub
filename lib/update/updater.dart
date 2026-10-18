import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/app_log.dart';
import '../version.dart';

/// Compara versiones "1.2.3" (ignora una "v" inicial y lo que va tras "+" o "-").
int compareVersions(String a, String b) {
  List<int> parse(String v) => v
      .replaceFirst(RegExp(r'^[vV]'), '')
      .split(RegExp(r'[+\-]'))
      .first
      .split('.')
      .map((x) => int.tryParse(x) ?? 0)
      .toList();
  final pa = parse(a), pb = parse(b);
  for (var i = 0; i < 3; i++) {
    final x = i < pa.length ? pa[i] : 0;
    final y = i < pb.length ? pb[i] : 0;
    if (x != y) return x.compareTo(y);
  }
  return 0;
}

class ReleaseAsset {
  final String name;
  final String url;
  final int size;
  const ReleaseAsset(this.name, this.url, this.size);
}

class ReleaseInfo {
  final String tag;
  final String name;
  final String notes;
  final String htmlUrl;
  final DateTime? publishedAt;
  final List<ReleaseAsset> assets;
  const ReleaseInfo(this.tag, this.name, this.notes, this.htmlUrl, this.publishedAt, this.assets);

  factory ReleaseInfo.fromJson(Map<String, dynamic> j) => ReleaseInfo(
        j['tag_name'] as String,
        (j['name'] as String?) ?? j['tag_name'] as String,
        (j['body'] as String?) ?? '',
        j['html_url'] as String,
        DateTime.tryParse(j['published_at'] as String? ?? ''),
        [
          for (final a in (j['assets'] as List? ?? []).cast<Map<String, dynamic>>())
            ReleaseAsset(a['name'] as String, a['browser_download_url'] as String,
                (a['size'] as num?)?.toInt() ?? 0),
        ],
      );
}

/// Nombre del archivo publicado para este sistema.
String? platformAssetName() {
  if (Platform.isWindows) return 'RetroHub-windows.zip';
  if (Platform.isLinux) return 'RetroHub-linux-x64.tar.gz';
  if (Platform.isAndroid) return 'RetroHub-android.apk';
  return null;
}

enum UpdateStage { idle, checking, downloading, installing, error }

/// Busca versiones nuevas en los Releases de GitHub, las descarga y las instala.
class Updater extends ChangeNotifier {
  static const _channel = MethodChannel('retro_hub/update');
  final http.Client _http = http.Client();

  UpdateStage stage = UpdateStage.idle;
  ReleaseInfo? latest;
  String? message;
  DateTime? lastCheck;
  int received = 0;
  int total = 0;

  String get currentVersion => kAppVersion;
  bool get updateAvailable =>
      latest != null && compareVersions(latest!.tag, kAppVersion) > 0;
  double? get progress => total > 0 ? received / total : null;

  /// Ejecutable compilado en modo desarrollo (no se puede autoactualizar).
  bool get isDevelopmentBuild {
    if (kDebugMode) return true;
    final exe = Platform.resolvedExecutable.replaceAll('\\', '/').toLowerCase();
    return exe.contains('/build/windows/') || exe.contains('/build/linux/');
  }

  ReleaseAsset? get asset {
    final name = platformAssetName();
    return latest?.assets.where((a) => a.name == name).firstOrNull;
  }

  Future<void> check() async {
    stage = UpdateStage.checking;
    message = null;
    notifyListeners();
    try {
      final res = await _http.get(
        Uri.parse('https://api.github.com/repos/$kReleasesRepo/releases/latest'),
        headers: {'Accept': 'application/vnd.github+json', 'User-Agent': 'RetroHub/$kAppVersion'},
      ).timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        throw Exception('GitHub respondió ${res.statusCode}');
      }
      latest = ReleaseInfo.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
      lastCheck = DateTime.now();
      stage = UpdateStage.idle;
      appLog.info(updateAvailable
          ? 'Hay una versión nueva: ${latest!.tag} (tienes $kAppVersion)'
          : 'RetroHub está al día ($kAppVersion)');
    } catch (e) {
      stage = UpdateStage.error;
      message = 'No se pudo comprobar: $e';
      appLog.warn('No se pudo comprobar actualizaciones', e);
    }
    notifyListeners();
  }

  /// Descarga la versión nueva y la instala. En PC la app se cierra y se
  /// vuelve a abrir sola ya actualizada.
  Future<void> downloadAndInstall() async {
    final a = asset;
    if (a == null) {
      message = 'Esta versión no tiene archivo para tu sistema.';
      stage = UpdateStage.error;
      notifyListeners();
      return;
    }
    try {
      stage = UpdateStage.downloading;
      received = 0;
      total = a.size;
      message = null;
      notifyListeners();
      final dir = Directory(p.join((await getTemporaryDirectory()).path, 'retrohub_update'));
      await dir.create(recursive: true);
      final file = File(p.join(dir.path, a.name));
      final req = http.Request('GET', Uri.parse(a.url))
        ..headers['User-Agent'] = 'RetroHub/$kAppVersion';
      final res = await _http.send(req);
      if (res.statusCode != 200) throw Exception('Descarga fallida (${res.statusCode})');
      if (res.contentLength != null) total = res.contentLength!;
      final sink = file.openWrite();
      var lastNotify = DateTime.now();
      await for (final chunk in res.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (DateTime.now().difference(lastNotify).inMilliseconds > 150) {
          lastNotify = DateTime.now();
          notifyListeners();
        }
      }
      await sink.close();
      if (total > 0 && await file.length() != total) {
        throw Exception('La descarga quedó incompleta. Vuelve a intentarlo.');
      }

      stage = UpdateStage.installing;
      notifyListeners();
      appLog.info('Instalando ${latest!.tag} desde ${file.path}');
      if (Platform.isAndroid) {
        final err = await _channel.invokeMethod<String>('installApk', {'path': file.path});
        stage = err == null ? UpdateStage.idle : UpdateStage.error;
        message = err ?? 'Sigue los pasos del instalador de Android.';
      } else if (Platform.isWindows) {
        await _installWindows(file, dir);
      } else if (Platform.isLinux) {
        await _installLinux(file, dir);
      }
    } catch (e, st) {
      stage = UpdateStage.error;
      message = '$e';
      appLog.error('Falló la actualización', e, st);
    }
    notifyListeners();
  }

  /// Un script espera a que RetroHub se cierre, reemplaza los archivos y lo
  /// vuelve a abrir.
  Future<void> _installWindows(File zip, Directory work) async {
    final installDir = p.dirname(Platform.resolvedExecutable);
    final exe = p.join(installDir, 'RetroHub.exe');
    final script = File(p.join(work.path, 'actualizar.ps1'));
    String q(String s) => "'${s.replaceAll("'", "''")}'";
    await script.writeAsString('''
\$ErrorActionPreference = 'Stop'
Wait-Process -Id $pid -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 700
try {
  Expand-Archive -LiteralPath ${q(zip.path)} -DestinationPath ${q(installDir)} -Force
} catch {
  Add-Type -AssemblyName PresentationFramework
  [System.Windows.MessageBox]::Show("No se pudo actualizar RetroHub: " + \$_.Exception.Message, "RetroHub") | Out-Null
}
Start-Process -FilePath ${q(exe)}
''');
    await Process.start(
      'powershell.exe',
      ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', script.path],
      mode: ProcessStartMode.detached,
    );
    exit(0);
  }

  Future<void> _installLinux(File tgz, Directory work) async {
    final installDir = p.dirname(Platform.resolvedExecutable);
    final script = File(p.join(work.path, 'actualizar.sh'));
    String q(String s) => "'${s.replaceAll("'", "'\\''")}'";
    await script.writeAsString('''
#!/usr/bin/env bash
while kill -0 $pid 2>/dev/null; do sleep 0.3; done
tmp=\$(mktemp -d)
tar -xzf ${q(tgz.path)} -C "\$tmp"
cp -rf "\$tmp/RetroHub/." ${q(installDir)}/
chmod +x ${q(p.join(installDir, 'RetroHub'))}
rm -rf "\$tmp"
nohup ${q(p.join(installDir, 'RetroHub'))} >/dev/null 2>&1 &
''');
    await Process.start('bash', [script.path], mode: ProcessStartMode.detached);
    exit(0);
  }

  @override
  void dispose() {
    _http.close();
    super.dispose();
  }
}
