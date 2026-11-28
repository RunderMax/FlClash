import 'dart:async';

import 'package:fl_clash/common/app_routes.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/programs.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'app.dart';
import 'config.dart';

part 'generated/app_route_activity.g.dart';

const _activeFor = Duration(minutes: 5);
const _guardedFor = Duration(minutes: 2);

const _blocked = {'REJECT', 'REJECT-DROP', slothGuardOutbound};

Map<String, DateTime> routedAppsSince(
  FixedList<TrackerInfo> requests,
  DateTime since, [
  Map<String, String> folders = const {},
]) {
  final latest = <String, DateTime>{};
  for (var index = requests.length - 1; index >= 0; index--) {
    final request = requests[index];
    if (request.start.isBefore(since)) {
      break;
    }
    if (request.chains.isEmpty || _blocked.contains(request.chains.first)) {
      continue;
    }
    final app = switch (request.rule) {
      processNameRule => request.rulePayload,
      processPathRule => folderAppOf(folders, request.metadata.processPath),
      _ => null,
    };
    if (app != null) {
      latest.putIfAbsent(app, () => request.start);
    }
  }
  return latest;
}

const _direct = {'DIRECT', 'COMPATIBLE', 'PASS'};

/// The system's own services are no app the user set going.
bool _ofTheSystem(String processPath) {
  final path = processPath.toLowerCase();
  return path.startsWith('/system/') ||
      path.startsWith('/usr/') ||
      path.startsWith('/sbin/') ||
      path.contains(r':\windows\');
}

/// The apps whose traffic lately went out through a node, whatever rule sent
/// it there; [folders] names the app a program's file belongs to.
Map<String, DateTime> proxiedAppsSince(
  FixedList<TrackerInfo> requests,
  DateTime since, [
  Map<String, String> folders = const {},
]) {
  final latest = <String, DateTime>{};
  for (var index = requests.length - 1; index >= 0; index--) {
    final request = requests[index];
    if (request.start.isBefore(since)) {
      break;
    }
    final process = request.metadata.process;
    if (process.isEmpty ||
        _ofTheSystem(request.metadata.processPath) ||
        request.chains.isEmpty ||
        request.chains.any(_blocked.contains) ||
        request.chains.any(_direct.contains)) {
      continue;
    }
    final app = folderAppOf(folders, request.metadata.processPath) ?? process;
    latest.putIfAbsent(app, () => request.start);
  }
  return latest;
}

@riverpod
class ProxiedApps extends _$ProxiedApps {
  Timer? _expiry;

  @override
  List<String> build() {
    programGroups.addListener(_refresh);
    ref.onDispose(() {
      _expiry?.cancel();
      programGroups.removeListener(_refresh);
    });
    ref.listen(requestsProvider, (_, _) => _refresh());
    return _compute();
  }

  List<String> _compute() {
    _expiry?.cancel();
    final now = DateTime.now();
    final latest =
        proxiedAppsSince(ref.read(requestsProvider), now.subtract(_activeFor), {
          for (final group in programGroups.value)
            group.lead.packageName: ?group.folder,
          ...ref.read(patchClashConfigProvider).slothAppFolders,
        });
    if (latest.isNotEmpty) {
      final oldest = latest.values.reduce((a, b) => a.isBefore(b) ? a : b);
      _expiry = Timer(oldest.add(_activeFor).difference(now), _refresh);
    }
    return latest.keys.toList();
  }

  void _refresh() {
    final next = _compute();
    if (!listEquals(next, state)) {
      state = next;
    }
  }
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
      ref.read(patchClashConfigProvider).slothAppFolders,
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

typedef GuardBlocks = ({Set<String> apps, int count});

/// The apps whose latest connection the guard stopped, how many it stopped in
/// all, and when the earliest of those was.
({GuardBlocks blocks, DateTime? earliest}) guardBlocksSince(
  FixedList<TrackerInfo> requests,
  DateTime since, [
  Map<String, String> folders = const {},
]) {
  final latest = <String, bool>{};
  var count = 0;
  DateTime? earliest;
  for (var index = requests.length - 1; index >= 0; index--) {
    final request = requests[index];
    if (request.start.isBefore(since)) {
      break;
    }
    final stopped = request.chains.firstOrNull == slothGuardOutbound;
    if (stopped) {
      count++;
      earliest = request.start;
    }
    final app = request.metadata.process.isNotEmpty
        ? folderAppOf(folders, request.metadata.processPath) ??
              request.metadata.process
        : request.rule == processNameRule
        ? request.rulePayload
        : '';
    if (app.isNotEmpty) {
      latest.putIfAbsent(app, () => stopped);
    }
  }
  return (
    blocks: (
      apps: {
        for (final MapEntry(key: app, value: stopped) in latest.entries)
          if (stopped) app,
      },
      count: count,
    ),
    earliest: earliest,
  );
}

@riverpod
class GuardBlocked extends _$GuardBlocked {
  Timer? _expiry;

  @override
  GuardBlocks build() {
    ref.onDispose(() => _expiry?.cancel());
    ref.listen(requestsProvider, (_, _) => _refresh());
    return _compute();
  }

  GuardBlocks _compute() {
    _expiry?.cancel();
    final now = DateTime.now();
    final (:blocks, :earliest) = guardBlocksSince(
      ref.read(requestsProvider),
      now.subtract(_guardedFor),
      ref.read(patchClashConfigProvider).slothAppFolders,
    );
    if (earliest != null) {
      _expiry = Timer(earliest.add(_guardedFor).difference(now), _refresh);
    }
    return blocks;
  }

  void _refresh() {
    final next = _compute();
    if (next.count != state.count || !setEquals(next.apps, state.apps)) {
      state = next;
    }
  }
}
