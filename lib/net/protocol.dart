/// Constantes compartidas entre servidor y cliente.
const kApiVersion = 1;
const kAppName = 'RetroHub';
const kDiscoveryPort = 47820;
const kDiscoverMsg = 'RETROHUB_DISCOVER_V1';
const kPinHeader = 'x-retrohub-pin';
const kMtimeHeader = 'x-retrohub-mtime';

/// Áreas que se pueden leer. Solo "saves" acepta escrituras.
const kReadableAreas = {'roms', 'bios', 'saves'};
const kWritableAreas = {'saves'};

/// Servidor encontrado en la red.
class ServerAddress {
  final String name;
  final String host;
  final int port;

  /// Identificador de instalación (si el servidor lo anunció).
  final String? id;
  const ServerAddress(this.name, this.host, this.port, {this.id});

  String get baseUrl => 'http://$host:$port';

  @override
  bool operator ==(Object other) =>
      other is ServerAddress && other.host == host && other.port == port;

  @override
  int get hashCode => Object.hash(host, port);
}
