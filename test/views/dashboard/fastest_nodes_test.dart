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
      'Proxy',
      GroupName.GLOBAL.name,
    ]);
  });

  test('a GLOBAL the profile defines itself can host the picks', () {
    final own = _selector(GroupName.GLOBAL.name, ['HK', slothPicksGroup]);
    expect(_names(pickEntryGroups([own, picks], Mode.rule)), [
      GroupName.GLOBAL.name,
    ]);
  });
}
