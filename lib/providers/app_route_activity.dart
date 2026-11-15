import 'dart:async';

import 'package:fl_clash/common/app_routes.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'app.dart';

part 'generated/app_route_activity.g.dart';

const _activeFor = Duration(minutes: 5);

const _blocked = {'REJECT', 'REJECT-DROP'};

Map<String, DateTime> routedAppsSince(
  FixedList<TrackerInfo> requests,
  DateTime since,
) {
  final latest = <String, DateTime>{};
  for (var index = requests.length - 1; index >= 0; index--) {
    final request = requests[index];
    if (request.start.isBefore(since)) {
      break;
    }
    if (request.rule != processNameRule ||
        request.chains.isEmpty ||
        _blocked.contains(request.chains.first)) {
      continue;
    }
    latest.putIfAbsent(request.rulePayload, () => request.start);
  }
  return latest;
}

/// An app stays marked for a while after its last routed connection.
@riverpod
class ActiveRoutedApps extends _$ActiveRoutedApps {
  Timer? _expiry;

  @override
  Set<String> build() {
    ref.onDispose(() => _expiry?.cancel());
    ref.listen(requestsProvider, (_, _) => _refresh());
    return _compute();
  }

  Set<String> _compute() {
    _expiry?.cancel();
    final now = DateTime.now();
    final latest = routedAppsSince(
      ref.read(requestsProvider),
      now.subtract(_activeFor),
    );
    if (latest.isNotEmpty) {
      final oldest = latest.values.reduce((a, b) => a.isBefore(b) ? a : b);
      _expiry = Timer(oldest.add(_activeFor).difference(now), _refresh);
    }
    return latest.keys.toSet();
  }

  void _refresh() {
    final next = _compute();
    if (!setEquals(next, state)) {
      state = next;
    }
  }
}
