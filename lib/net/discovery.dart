import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'protocol.dart';

/// Responde a búsquedas por broadcast UDP para que los clientes
/// encuentren el servidor sin escribir la IP.
class DiscoveryResponder {
  RawDatagramSocket? _socket;

  Future<void> start({required String name, required int httpPort}) async {
    await stop();
    final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4, kDiscoveryPort,
        reuseAddress: true);
    _socket = socket;
    socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final dg = socket.receive();
      if (dg == null) return;
      final msg = utf8.decode(dg.data, allowMalformed: true);
      if (msg.trim() != kDiscoverMsg) return;
      final reply = utf8.encode(jsonEncode({
        'app': kAppName,
        'v': kApiVersion,
        'name': name,
        'port': httpPort,
      }));
      socket.send(reply, dg.address, dg.port);
    });
  }

  Future<void> stop() async {
    _socket?.close();
    _socket = null;
  }
}

/// Envía un broadcast y recoge las respuestas durante [timeout].
Future<List<ServerAddress>> discoverServers(
    {Duration timeout = const Duration(seconds: 2)}) async {
  final found = <ServerAddress>{};
  final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  socket.broadcastEnabled = true;

  final sub = socket.listen((event) {
    if (event != RawSocketEvent.read) return;
    final dg = socket.receive();
    if (dg == null) return;
    try {
      final j = jsonDecode(utf8.decode(dg.data)) as Map<String, dynamic>;
      if (j['app'] != kAppName) return;
      found.add(ServerAddress(
        j['name'] as String? ?? dg.address.address,
        dg.address.address,
        (j['port'] as num).toInt(),
      ));
    } catch (_) {}
  });

  final payload = utf8.encode(kDiscoverMsg);
  final targets = <InternetAddress>{InternetAddress('255.255.255.255')};
  // Broadcast dirigido por cada interfaz /24 (más fiable en algunos routers).
  try {
    for (final iface in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
      for (final a in iface.addresses) {
        final parts = a.address.split('.');
        if (parts.length == 4 && !a.isLoopback) {
          targets.add(InternetAddress('${parts[0]}.${parts[1]}.${parts[2]}.255'));
        }
      }
    }
  } catch (_) {}

  for (var i = 0; i < 2; i++) {
    for (final t in targets) {
      try {
        socket.send(payload, t, kDiscoveryPort);
      } catch (_) {}
    }
    await Future.delayed(timeout ~/ 2);
  }

  await sub.cancel();
  socket.close();
  return found.toList();
}

/// IPs locales (para mostrarlas en la pantalla del servidor).
Future<List<String>> localIPv4Addresses() async {
  try {
    final list = await NetworkInterface.list(type: InternetAddressType.IPv4);
    final ips = [
      for (final i in list)
        for (final a in i.addresses)
          if (!a.isLoopback) a.address
    ];
    // Primero las IPs típicas de una red Wi-Fi doméstica; las de VPN,
    // WSL o Docker (10.x, 172.x) suelen ser adaptadores virtuales.
    int rank(String ip) => ip.startsWith('192.168.')
        ? 0
        : ip.startsWith('10.')
            ? 1
            : 2;
    ips.sort((a, b) => rank(a).compareTo(rank(b)));
    return ips;
  } catch (_) {
    return const [];
  }
}
