import 'package:fl_clash/common/app_exits.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('gives each app its records newest first', () {
    final exits = parseAppExits('''[
      {"app": "com.example.video", "node": "JP-01", "ip": "1.1.1.1", "country": "JP", "first": 1000, "last": 2000},
      {"app": "com.example.chat", "node": "DIRECT", "ip": "3.3.3.3", "first": 1500, "last": 1500},
      {"app": "com.example.video", "node": "US-01", "ip": "2.2.2.2", "country": "US", "first": 3000, "last": 4000}
    ]''');

    expect(
      exits.keys,
      unorderedEquals(['com.example.video', 'com.example.chat']),
    );
    expect(
      [for (final exit in exits['com.example.video']!) exit.ip],
      ['2.2.2.2', '1.1.1.1'],
    );
    final chat = exits['com.example.chat']!.single;
    expect(chat.node, 'DIRECT');
    expect(chat.country, isEmpty);
    expect(chat.first, DateTime.fromMillisecondsSinceEpoch(1500));
  });

  test('skips what it cannot read', () {
    expect(parseAppExits('not json'), isEmpty);
    expect(parseAppExits('{"app": "a"}'), isEmpty);
    expect(parseAppExits('[{"app": "a", "ip": "1.1.1.1"}, 3]'), isEmpty);
  });
}
