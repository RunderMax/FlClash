import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/app_route_activity.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 11, 15, 22);

TrackerInfo _request(
  int minutesAgo,
  String app, {
  List<String> chains = const ['JP-01'],
  String rule = 'ProcessName',
  String process = '',
}) => TrackerInfo(
  id: '$minutesAgo-$app',
  start: _now.subtract(Duration(minutes: minutesAgo)),
  metadata: Metadata(process: process),
  chains: chains,
  rule: rule,
  rulePayload: app,
);

void main() {
  test('names the apps whose route carried a connection lately', () {
    final requests = FixedList<TrackerInfo>(
      10,
      list: [
        _request(9, 'com.example.old'),
        _request(4, 'com.example.video'),
        _request(3, 'com.example.chat', chains: const ['REJECT']),
        _request(2, 'example.com', rule: 'DomainSuffix'),
        _request(1, 'com.example.video', chains: const ['DIRECT']),
      ],
    );

    final apps = routedAppsSince(
      requests,
      _now.subtract(const Duration(minutes: 5)),
    );

    expect(apps.keys, ['com.example.video']);
    expect(
      apps['com.example.video'],
      _now.subtract(const Duration(minutes: 1)),
    );
  });

  test('names none without a routed connection', () {
    expect(routedAppsSince(FixedList<TrackerInfo>(10), _now), isEmpty);
  });

  test('names the apps the guard stopped last and counts every stop', () {
    const guard = [slothGuardOutbound];
    final requests = FixedList<TrackerInfo>(
      10,
      list: [
        _request(3, 'com.example.old', chains: guard),
        _request(2, 'com.example.chat', chains: guard),
        _request(2, 'com.example.video', chains: guard),
        _request(1, 'com.example.video'),
        _request(1, 'x.com', rule: 'Match', chains: guard),
        _request(
          1,
          'example.com',
          rule: 'DomainSuffix',
          process: 'com.example.web',
          chains: guard,
        ),
      ],
    );

    final (:blocks, :earliest) = guardBlocksSince(
      requests,
      _now.subtract(const Duration(minutes: 2)),
    );

    expect(blocks.apps, {'com.example.chat', 'com.example.web'});
    expect(blocks.count, 4);
    expect(earliest, _now.subtract(const Duration(minutes: 2)));
    expect(
      routedAppsSince(requests, _now.subtract(const Duration(minutes: 5))).keys,
      ['com.example.video'],
    );
  });
}
