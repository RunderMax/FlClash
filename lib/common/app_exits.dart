import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

const appExitsFile = 'sloth-app-exits.json';

/// One address an app left through, over a run of uses of one node.
@immutable
class AppExit {
  const AppExit({
    required this.node,
    required this.ip,
    required this.country,
    required this.first,
    required this.last,
  });

  final String node;
  final String ip;
  final String country;
  final DateTime first;
  final DateTime last;
}

Map<String, List<AppExit>> parseAppExits(String text) {
  final Object? data;
  try {
    data = jsonDecode(text);
  } on FormatException {
    return const {};
  }
  if (data is! List) {
    return const {};
  }
  final byApp = <String, List<AppExit>>{};
  for (final item in data.reversed) {
    if (item case {
      'app': final String app,
      'node': final String node,
      'ip': final String ip,
      'first': final int first,
      'last': final int last,
    }) {
      (byApp[app] ??= []).add(
        AppExit(
          node: node,
          ip: ip,
          country: switch (item['country']) {
            final String country => country,
            _ => '',
          },
          first: DateTime.fromMillisecondsSinceEpoch(first),
          last: DateTime.fromMillisecondsSinceEpoch(last),
        ),
      );
    }
  }
  return byApp;
}

/// Each app's records, newest first.
Future<Map<String, List<AppExit>>> loadAppExits(String path) =>
    Isolate.run(() async {
      final file = File(path);
      if (!await file.exists()) {
        return const <String, List<AppExit>>{};
      }
      return parseAppExits(await file.readAsString());
    });
