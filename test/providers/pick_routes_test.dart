import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/pick_routes.dart';
import 'package:flutter_test/flutter_test.dart';

TrackerInfo _request(List<String> chains) => TrackerInfo(
  id: chains.join(),
  start: DateTime(2026),
  metadata: Metadata.fromJson(const {}),
  chains: chains,
  rule: 'MATCH',
  rulePayload: '',
);

void main() {
  test('takes the rule target group, not the groups it went through', () {
    final routes = pickRoutesOf([
      _request(['JP 03', 'Japan', 'Main']),
      _request(['HK 01', 'Hong Kong', 'Main']),
      _request(['DIRECT']),
    ]);

    expect(routes.groups, {'Main'});
    expect(routes.nodes, {'DIRECT'});
  });

  test('routes compare by content', () {
    expect(
      pickRoutesOf([
        _request(['a', 'Main']),
      ]),
      pickRoutesOf([
        _request(['b', 'Main']),
      ]),
    );
    expect(pickRoutesOf(const []).isEmpty, isTrue);
  });
}
