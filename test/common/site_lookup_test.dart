import 'dart:typed_data';

import 'package:fl_clash/common/site_lookup.dart';
import 'package:flutter_test/flutter_test.dart';

List<int> _field(int number, List<int> bytes) => [
  number << 3 | 2,
  bytes.length,
  ...bytes,
];

List<int> _domain(int type, String value) => [
  ...[1 << 3, type],
  ..._field(2, value.codeUnits),
];

List<int> _site(String code, List<List<int>> domains) => _field(1, [
  ..._field(1, code.codeUnits),
  for (final domain in domains) ..._field(2, domain),
]);

void main() {
  final book = parseGeosite(
    Uint8List.fromList([
      ..._site('TELEGRAM', [_domain(2, 'telegram.org'), _domain(1, 'tg.*')]),
      ..._site('OPENAI', [_domain(2, 'openai.com'), _domain(3, 'chatgpt.com')]),
    ]),
  );

  test('reads each category with the domains it routes whole', () {
    expect(book, {
      'telegram': ['telegram.org'],
      'openai': ['openai.com', 'chatgpt.com'],
    });
  });

  test('finds a category by its name or by a site of its own', () {
    expect(findCategories(book, 'Telegram'), ['telegram']);
    expect(findCategories(book, 'https://www.chatgpt.com/'), ['openai']);
    expect(findCategories(book, 'nothing.example'), isEmpty);
  });

  test('keeps the part of a host its owner registered', () {
    expect(registrableDomain('web.telegram.org'), 'telegram.org');
    expect(registrableDomain('shop.example.co.uk'), 'example.co.uk');
    expect(hostOf('Telegram'), isNull);
    expect(hostOf('https://www.example.com/path'), 'example.com');
  });
}
