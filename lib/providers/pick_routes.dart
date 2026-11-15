import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'app.dart';

part 'generated/pick_routes.g.dart';

const _recentRequests = 200;

/// Where recent traffic entered the proxies: the group a rule sent it to,
/// whose present choice is what such traffic uses now, or a node a rule names
/// itself.
@immutable
class PickRoutes {
  const PickRoutes({this.groups = const {}, this.nodes = const {}});

  final Set<String> groups;
  final Set<String> nodes;

  bool get isEmpty => groups.isEmpty && nodes.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is PickRoutes &&
      setEquals(other.groups, groups) &&
      setEquals(other.nodes, nodes);

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(groups),
    Object.hashAllUnordered(nodes),
  );
}

/// mihomo lists a connection's chain from the node outward, so its last entry
/// is the rule's own target; inner groups are left out, as they only say what
/// the outer group chose back then.
PickRoutes pickRoutesOf(Iterable<TrackerInfo> newestFirst) {
  final groups = <String>{};
  final nodes = <String>{};
  for (final request in newestFirst.take(_recentRequests)) {
    final chains = request.chains;
    if (chains.length > 1) {
      groups.add(chains.last);
    } else if (chains.isNotEmpty) {
      nodes.add(chains.first);
    }
  }
  return PickRoutes(groups: groups, nodes: nodes);
}

Iterable<T> _newestFirst<T>(FixedList<T> list) sync* {
  for (var index = list.length - 1; index >= 0; index--) {
    yield list[index];
  }
}

/// Changes only when the routes do, not with every request.
@Riverpod(keepAlive: true)
class PickRoutesState extends _$PickRoutesState {
  @override
  PickRoutes build() {
    ref.listen(requestsProvider, (_, requests) {
      final next = pickRoutesOf(_newestFirst(requests));
      if (next != state) state = next;
    });
    return pickRoutesOf(_newestFirst(ref.read(requestsProvider)));
  }
}
