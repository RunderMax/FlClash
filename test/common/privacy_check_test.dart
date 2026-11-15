import 'dart:typed_data';

import 'package:fl_clash/common/privacy_check.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _response(List<int> transactionId, List<int> attribute) {
  final header = ByteData(20)
    ..setUint16(0, 0x0101)
    ..setUint16(2, attribute.length)
    ..setUint32(4, 0x2112A442);
  final bytes = header.buffer.asUint8List()..setRange(8, 20, transactionId);
  return Uint8List.fromList([...bytes, ...attribute]);
}

void main() {
  final id = List.generate(12, (i) => i + 1);

  test('reads the xor mapped address of a binding response', () {
    // 203.0.113.5 xor 0x2112A442, port 54321 xor 0x2112.
    final packet = _response(id, [
      0x00, 0x20, 0x00, 0x08, //
      0x00, 0x01, 0xF5, 0x23, //
      0xEA, 0x12, 0xD5, 0x47, //
    ]);
    expect(parseStunMappedAddress(packet, id), '203.0.113.5');
  });

  test('ignores a response to another transaction', () {
    final packet = _response(List.filled(12, 9), [
      0x00, 0x01, 0x00, 0x08, //
      0x00, 0x01, 0x00, 0x50, //
      0xCB, 0x00, 0x71, 0x05, //
    ]);
    expect(parseStunMappedAddress(packet, id), isNull);
  });

  test('builds a twenty byte binding request', () {
    final request = stunBindingRequest(id);
    expect(request.length, 20);
    expect(request.sublist(0, 8), [0, 1, 0, 0, 0x21, 0x12, 0xA4, 0x42]);
    expect(request.sublist(8), id);
  });

  test('a resolver outside the exit country counts as a leak', () {
    const exit = IpPlace(ip: '1.1.1.1', countryCode: 'US');
    expect(
      dnsVerdict(exit, const [IpPlace(ip: '8.8.8.8', countryCode: 'US')]),
      LeakVerdict.safe,
    );
    expect(
      dnsVerdict(exit, const [IpPlace(ip: '9.9.9.9', countryCode: 'MY')]),
      LeakVerdict.possibleLeak,
    );
    expect(dnsVerdict(exit, const []), LeakVerdict.unreachable);
  });

  test('a stun address in another country counts as a leak', () {
    const exit = IpPlace(ip: '1.1.1.1', countryCode: 'JP');
    expect(webRtcVerdict(exit, exit), LeakVerdict.safe);
    expect(
      webRtcVerdict(exit, const IpPlace(ip: '1.1.1.2', countryCode: 'JP')),
      LeakVerdict.safe,
    );
    expect(
      webRtcVerdict(exit, const IpPlace(ip: '2.2.2.2', countryCode: 'MY')),
      LeakVerdict.possibleLeak,
    );
  });

  test('recognises the fake ip range', () {
    expect(isFakeIp('198.18.0.7'), isTrue);
    expect(isFakeIp('93.184.216.34'), isFalse);
  });
}
