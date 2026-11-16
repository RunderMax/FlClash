import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

enum LeakVerdict { safe, possibleLeak, unreachable }

class IpPlace {
  const IpPlace({required this.ip, this.countryCode, this.isp});

  final String ip;
  final String? countryCode;
  final String? isp;

  String get label => [
    ?countryCode,
    if (isp case final isp? when isp.isNotEmpty) isp,
  ].join(' · ');
}

class DnsCheck {
  const DnsCheck({
    required this.fakeIp,
    required this.resolvers,
    required this.verdict,
  });

  /// Null where the requests went through the proxy port, which looks host
  /// names up at the far end rather than here.
  final bool? fakeIp;
  final List<IpPlace> resolvers;
  final LeakVerdict verdict;
}

class WebRtcCheck {
  const WebRtcCheck({required this.mapped, required this.verdict});

  final IpPlace? mapped;
  final LeakVerdict verdict;
}

class PrivacyReport {
  const PrivacyReport({
    required this.exit,
    required this.real,
    required this.dns,
    required this.webRtc,
  });

  final IpPlace exit;
  final IpPlace? real;
  final DnsCheck dns;
  final WebRtcCheck webRtc;
}

const _stunServers = [
  ('stun.l.google.com', 19302),
  ('stun.cloudflare.com', 3478),
];
const _stunMagicCookie = 0x2112A442;
const _dnsProbeRounds = 6;
const _maxResolverLookups = 6;
const _timeout = Duration(seconds: 6);

/// Every request here leaves through a plain socket, so it takes the same path
/// through the VPN and its rules as any other app, not the core's own proxy port.
/// Where nothing captures the app's own sockets, as under a desktop system
/// proxy, [findProxy] sends the web requests the way a browser goes; STUN
/// stays a plain socket, as a page's WebRTC does.
/// [realIp] is the address the network itself gives out, found without the
/// proxy; a leak is anything that shows it or its provider.
Future<PrivacyReport> runPrivacyCheck({
  String? realIp,
  String Function(Uri url)? findProxy,
}) async {
  final client = HttpClient()
    ..findProxy = findProxy ?? ((_) => 'DIRECT')
    ..connectionTimeout = _timeout;
  try {
    final exit = await _lookupPlace(client, null);
    final real = realIp == null || realIp == exit.ip
        ? null
        : await _lookupPlaceOrBare(client, realIp);
    final results = await Future.wait([
      _checkDns(client, exit, real, localLookups: findProxy == null),
      _checkWebRtc(client, exit, real),
    ]);
    return PrivacyReport(
      exit: exit,
      real: real,
      dns: results[0] as DnsCheck,
      webRtc: results[1] as WebRtcCheck,
    );
  } finally {
    client.close(force: true);
  }
}

Future<Map<String, dynamic>> _getJson(HttpClient client, Uri uri) async {
  final request = await client.getUrl(uri).timeout(_timeout);
  final response = await request.close().timeout(_timeout);
  final body = await response.transform(utf8.decoder).join().timeout(_timeout);
  if (response.statusCode != HttpStatus.ok) {
    throw HttpException('HTTP ${response.statusCode}', uri: uri);
  }
  return jsonDecode(body) as Map<String, dynamic>;
}

Future<IpPlace> _lookupPlace(HttpClient client, String? ip) async {
  final json = await _getJson(
    client,
    Uri.https('ipleak.net', '/json/${ip ?? ''}'),
  );
  return IpPlace(
    ip: json['ip'] as String? ?? ip ?? '',
    countryCode: json['country_code'] as String?,
    isp: json['isp_name'] as String?,
  );
}

Future<IpPlace> _lookupPlaceOrBare(HttpClient client, String ip) async {
  try {
    return await _lookupPlace(client, ip);
  } on Object {
    return IpPlace(ip: ip);
  }
}

String _randomHex(int length) {
  final random = Random.secure();
  return List.generate(
    length,
    (_) => random.nextInt(16).toRadixString(16),
  ).join();
}

Future<DnsCheck> _checkDns(
  HttpClient client,
  IpPlace exit,
  IpPlace? real, {
  required bool localLookups,
}) async {
  final fakeIp = localLookups ? await _resolvesToFakeIp() : null;
  final session = _randomHex(40);
  var seen = <String, int>{};
  for (var round = 0; round < _dnsProbeRounds; round++) {
    try {
      final json = await _getJson(
        client,
        Uri.https('$session-${_randomHex(8)}.ipleak.net', '/dnsdetection/'),
      );
      seen = {
        for (final MapEntry(:key, :value)
            in (json['ip'] as Map<String, dynamic>? ?? const {}).entries)
          key: (value as num).toInt(),
      };
    } on Object {
      continue;
    }
  }
  final ranked = seen.keys.toList()
    ..sort((a, b) => seen[b]!.compareTo(seen[a]!));
  final resolvers = await Future.wait(
    ranked
        .take(_maxResolverLookups)
        .map((ip) => _lookupPlaceOrBare(client, ip)),
  );
  return DnsCheck(
    fakeIp: fakeIp,
    resolvers: resolvers,
    verdict: dnsVerdict(exit, resolvers, real: real),
  );
}

Future<bool> _resolvesToFakeIp() async {
  try {
    final addresses = await InternetAddress.lookup(
      'example.com',
    ).timeout(_timeout);
    return addresses.any((address) => isFakeIp(address.address));
  } on Object {
    return false;
  }
}

Future<WebRtcCheck> _checkWebRtc(
  HttpClient client,
  IpPlace exit,
  IpPlace? real,
) async {
  for (final (host, port) in _stunServers) {
    final ip = await stunMappedAddress(host, port);
    if (ip == null) continue;
    final mapped = ip == exit.ip ? exit : await _lookupPlaceOrBare(client, ip);
    return WebRtcCheck(
      mapped: mapped,
      verdict: webRtcVerdict(exit, mapped, real: real),
    );
  }
  return const WebRtcCheck(mapped: null, verdict: LeakVerdict.unreachable);
}

bool isFakeIp(String address) {
  final parts = address.split('.');
  if (parts.length != 4) return false;
  final first = int.tryParse(parts[0]);
  final second = int.tryParse(parts[1]);
  return first == 198 && (second == 18 || second == 19);
}

bool _sameProvider(IpPlace a, IpPlace b) {
  final isp = a.isp?.trim().toLowerCase();
  return isp != null && isp.isNotEmpty && isp == b.isp?.trim().toLowerCase();
}

/// Big public resolvers answer from anycast addresses that geolocate to their
/// head office, so only the real network's own provider, or a resolver in the
/// real country when the exit is elsewhere, shows where the lookup came from.
LeakVerdict dnsVerdict(IpPlace exit, List<IpPlace> resolvers, {IpPlace? real}) {
  if (resolvers.isEmpty) return LeakVerdict.unreachable;
  if (real == null) return LeakVerdict.safe;
  final realCountry = real.countryCode;
  final leaks = resolvers.any(
    (resolver) =>
        _sameProvider(resolver, real) ||
        (realCountry != null &&
            realCountry != exit.countryCode &&
            resolver.countryCode == realCountry),
  );
  return leaks ? LeakVerdict.possibleLeak : LeakVerdict.safe;
}

/// Some nodes send UDP out of a sibling address, so only the real address or
/// its provider counts as a leak.
LeakVerdict webRtcVerdict(IpPlace exit, IpPlace mapped, {IpPlace? real}) {
  if (mapped.ip == exit.ip || real == null) return LeakVerdict.safe;
  return mapped.ip == real.ip || _sameProvider(mapped, real)
      ? LeakVerdict.possibleLeak
      : LeakVerdict.safe;
}

Uint8List stunBindingRequest(List<int> transactionId) {
  final data = ByteData(20)
    ..setUint16(0, 0x0001)
    ..setUint16(2, 0)
    ..setUint32(4, _stunMagicCookie);
  final bytes = data.buffer.asUint8List();
  bytes.setRange(8, 20, transactionId);
  return bytes;
}

String? parseStunMappedAddress(Uint8List packet, List<int> transactionId) {
  if (packet.length < 20) return null;
  final data = ByteData.sublistView(packet);
  if (data.getUint16(0) != 0x0101 || data.getUint32(4) != _stunMagicCookie) {
    return null;
  }
  for (var i = 0; i < 12; i++) {
    if (packet[8 + i] != transactionId[i]) return null;
  }
  final end = min(packet.length, 20 + data.getUint16(2));
  String? plain;
  var offset = 20;
  while (offset + 4 <= end) {
    final type = data.getUint16(offset);
    final length = data.getUint16(offset + 2);
    final value = offset + 4;
    if (value + length > end) break;
    if ((type == 0x0020 || type == 0x0001) &&
        length >= 8 &&
        packet[value + 1] == 0x01) {
      final raw = data.getUint32(value + 4);
      final ip = type == 0x0020 ? raw ^ _stunMagicCookie : raw;
      final address = [
        ip >> 24 & 0xff,
        ip >> 16 & 0xff,
        ip >> 8 & 0xff,
        ip & 0xff,
      ].join('.');
      if (type == 0x0020) return address;
      plain = address;
    }
    offset = value + (length + 3) ~/ 4 * 4;
  }
  return plain;
}

Future<String?> stunMappedAddress(String host, int port) async {
  final List<InternetAddress> addresses;
  try {
    addresses = await InternetAddress.lookup(
      host,
      type: InternetAddressType.IPv4,
    ).timeout(_timeout);
  } on Object {
    return null;
  }
  if (addresses.isEmpty) return null;
  final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  final random = Random.secure();
  final transactionId = List.generate(12, (_) => random.nextInt(256));
  final completer = Completer<String?>();
  final subscription = socket.listen((event) {
    if (event != RawSocketEvent.read) return;
    final datagram = socket.receive();
    if (datagram == null || completer.isCompleted) return;
    final address = parseStunMappedAddress(datagram.data, transactionId);
    if (address != null) completer.complete(address);
  });
  final request = stunBindingRequest(transactionId);
  final resend = Timer.periodic(const Duration(milliseconds: 700), (_) {
    socket.send(request, addresses.first, port);
  });
  socket.send(request, addresses.first, port);
  try {
    return await completer.future.timeout(
      const Duration(seconds: 3),
      onTimeout: () => null,
    );
  } finally {
    resend.cancel();
    await subscription.cancel();
    socket.close();
  }
}
