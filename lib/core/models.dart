import 'package:path/path.dart' as p;

/// Un juego (archivo o carpeta) dentro de roms/{platform}.
class Game {
  final String platform;

  /// Nombre del archivo o carpeta dentro de roms/{platform}.
  final String fileName;
  final String title;
  final String? tags;
  final int size;
  final bool isFolder;

  /// Ruta local completa (null si el juego es remoto).
  final String? localPath;

  /// Carátula local (archivo de ES-DE) si existe.
  final String? coverFile;

  /// Carátula remota servida por otro dispositivo.
  final String? coverUrl;

  const Game({
    required this.platform,
    required this.fileName,
    required this.title,
    required this.size,
    this.tags,
    this.isFolder = false,
    this.localPath,
    this.coverFile,
    this.coverUrl,
  });

  String get key => '$platform/$fileName';

  /// Nombre base usado por ES-DE para buscar media.
  String get mediaName => isFolder ? fileName : p.basenameWithoutExtension(fileName);

  Map<String, dynamic> toJson() => {
        'file': fileName,
        'title': title,
        'tags': tags,
        'size': size,
        'folder': isFolder,
        'cover': coverFile != null,
      };

  factory Game.fromJson(String platform, Map<String, dynamic> j,
          {String? coverUrl}) =>
      Game(
        platform: platform,
        fileName: j['file'] as String,
        title: j['title'] as String,
        tags: j['tags'] as String?,
        size: (j['size'] as num?)?.toInt() ?? 0,
        isFolder: j['folder'] == true,
        coverUrl: coverUrl,
      );
}

/// Archivo en un árbol remoto o local (rutas relativas con "/").
class FileEntry {
  final String path;
  final int size;
  final int mtime; // milisegundos desde epoch
  final String? sha1;

  const FileEntry(this.path, this.size, this.mtime, [this.sha1]);

  Map<String, dynamic> toJson() =>
      {'path': path, 'size': size, 'mtime': mtime, if (sha1 != null) 'sha1': sha1};

  factory FileEntry.fromJson(Map<String, dynamic> j) => FileEntry(
        j['path'] as String,
        (j['size'] as num).toInt(),
        (j['mtime'] as num).toInt(),
        j['sha1'] as String?,
      );
}

final _numPrefix = RegExp(r'^\d{3,5}\s*-\s*');

/// Extensiones de ROM que a veces quedan en nombres de carpetas.
const _romExts = {
  '.xci', '.nsp', '.nsz', '.xcz', '.iso', '.chd', '.cso', '.rvz', '.wbfs',
  '.zip', '.7z', '.cue', '.pkg', '.3ds', '.cia', '.nds', '.gba',
};

/// Etiquetas que no aportan nada al usuario: IDs de título de Switch,
/// versiones, nombres de sitios web, "Dumped", "NSP", DLC, etc.
final _junkTag = RegExp(
  r'^[\(\[]\s*(?:[0-9a-f]{16}|v\d[^\)\]]*|[^\)\]]*\.(?:com|net|org)|dumped|nsp|xci|nsz|'
  r'\d+g\+\d+u|[^\)\]]*dlc[^\)\]]*|update[^\)\]]*)\s*[\)\]]$',
  caseSensitive: false,
);
final _tagRe = RegExp(r'[\(\[][^\)\]]*[\)\]]');
final _articleRe =
    RegExp(r'^(.*?), (The|A|An|El|La|Los|Las|Le|Les|Die|Der)( - .*)?$');

/// Convierte "Legend of Zelda, The - A Link to the Past (U) [!].smc"
/// en ("The Legend of Zelda - A Link to the Past", "(U) [!]").
(String, String?) parseTitle(String fileName, {bool isFolder = false}) {
  var base = isFolder ? fileName : p.basenameWithoutExtension(fileName);
  if (isFolder && _romExts.contains(p.extension(base).toLowerCase())) {
    base = p.basenameWithoutExtension(base);
  }
  base = base.replaceFirst(_numPrefix, '');
  final tags = _tagRe
      .allMatches(base)
      .map((m) => m.group(0)!)
      .where((t) => !_junkTag.hasMatch(t))
      .join(' ');
  var title = base
      .replaceAll(_tagRe, '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'^[\s+\-_]+|[\s+\-_]+$'), '')
      .trim();
  final m = _articleRe.firstMatch(title);
  if (m != null) title = '${m.group(2)} ${m.group(1)}${m.group(3) ?? ''}';
  if (title.isEmpty) title = base;
  return (title, tags.isEmpty ? null : tags);
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  double v = bytes / 1024;
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(v < 10 ? 1 : 0)} ${units[i]}';
}

String toPosix(String path) => path.replaceAll('\\', '/');

/// Une una ruta relativa (con "/") a una raíz, rechazando "..", unidades, etc.
String? safeJoin(String root, String rel) {
  final parts = rel
      .replaceAll('\\', '/')
      .split('/')
      .where((s) => s.isNotEmpty && s != '.')
      .toList();
  if (parts.isEmpty) return root;
  if (parts.any((s) => s == '..' || s.contains(':'))) return null;
  return p.joinAll([root, ...parts]);
}
