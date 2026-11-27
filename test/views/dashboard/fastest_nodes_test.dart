import 'package:fl_clash/common/app_routes.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/views/dashboard/widgets/fastest_nodes.dart';
import 'package:flutter_test/flutter_test.dart';

Group _selector(String name, List<String> members, {bool hidden = false}) =>
    Group(
      type: GroupType.Selector,
      name: name,
      hidden: hidden,
      all: [for (final member in members) Proxy(name: member, type: 'ss')],
    );

List<String> _names(List<Group> groups) => [
  for (final group in groups) group.name,
];

void main() {
  final global = _selector(GroupName.GLOBAL.name, [
    'Proxy',
    slothPicksGroup,
    'HK',
  ], hidden: true);
  final host = _selector('Proxy', ['HK', slothPicksGroup]);
  final picks = _selector(slothPicksGroup, ['HK']);
  final groups = [global, host, picks];

  test('rule mode chooses a pick in the group the picks are offered in', () {
    expect(_names(pickEntryGroups(groups, Mode.rule)), ['Proxy']);
  });

  test('global mode also chooses it in GLOBAL, which traffic enters', () {
    expect(_names(pickEntryGroups(groups, Mode.global)), [
      GroupName.GLOBAL.name,
      'Proxy',
    ]);
  });

  test('a GLOBAL the profile defines itself can host the picks', () {
    final own = _selector(GroupName.GLOBAL.name, ['HK', slothPicksGroup]);
    expect(_names(pickEntryGroups([own, picks], Mode.rule)), [
      GroupName.GLOBAL.name,
    ]);
  });

  group('a profile with several select groups', () {
    Group typed(String name, Map<String, String> members) => Group(
      type: GroupType.Selector,
      name: name,
      now: members.keys.first,
      all: [
        for (final MapEntry(:key, :value) in members.entries)
          Proxy(name: key, type: value),
      ],
    );
    final main = typed('Proxy', {'HK': 'ss', slothPicksGroup: 'Selector'});
    final service = typed('Video', {'JP': 'ss', slothPicksGroup: 'Selector'});
    final direct = typed('Domestic', {
      'DIRECT': 'Direct',
      slothPicksGroup: 'Selector',
    });
    final own = typed(appPicksGroupOf('com.example.a'), {
      'JP': 'ss',
      slothPicksGroup: 'Selector',
    });
    final all = [main, service, direct, own, picks];

    test('enters the picks in each one that leads to a proxy', () {
      expect(_names(pickEntryGroups(all, Mode.rule)), ['Proxy', 'Video']);
    });

    test('takes one moved off DIRECT and leaves one moved onto it', () {
      final selected = {'Domestic': slothPicksGroup, 'Video': 'JP'};
      expect(_names(pickEntryGroups(all, Mode.rule, selected)), [
        'Proxy',
        'Video',
        'Domestic',
      ]);
    });
  });
}
