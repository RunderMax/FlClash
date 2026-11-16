import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/models/models.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

final _appName = RegExp(r'^[A-Za-z0-9_][A-Za-z0-9_ \-]*(\.[A-Za-z0-9_\-]+)+$');

const _listProcesses =
    r'[Console]::OutputEncoding = [Text.Encoding]::UTF8; '
    r'Get-Process | Where-Object { $_.SessionId -ne 0 -and $_.Path } | '
    r'Select-Object Path, Description | ConvertTo-Json -Compress';

/// Windows keeps no list of installed programs by the executable name a rule
/// matches, so the programs running in the user's session stand for them.
Future<List<Package>> runningPrograms() async {
  final result = await Process.run('powershell', [
    '-NoProfile',
    '-NonInteractive',
    '-Command',
    _listProcesses,
  ], stdoutEncoding: utf8);
  if (result.exitCode != 0) {
    throw ProcessException(
      'powershell',
      const ['Get-Process'],
      '${result.stderr}',
      result.exitCode,
    );
  }
  return parsePrograms(
    result.stdout as String,
    systemRoot: Platform.environment['SystemRoot'] ?? r'C:\Windows',
    own: path.windows.dirname(Platform.resolvedExecutable),
  );
}

/// Programs under [systemRoot] count as system ones; those under [own], this
/// app and its core, are left out.
@visibleForTesting
List<Package> parsePrograms(
  String output, {
  required String systemRoot,
  required String own,
}) {
  final decoded = output.trim().isEmpty ? null : jsonDecode(output);
  final items = switch (decoded) {
    final List<dynamic> list => list,
    final Map<dynamic, dynamic> map => [map],
    _ => const [],
  };
  final byName = <String, Package>{};
  for (final item in items) {
    if (item is! Map) continue;
    final file = item['Path'];
    if (file is! String || path.windows.isWithin(own, file)) continue;
    final name = path.windows.basename(file);
    if (!_appName.hasMatch(name)) continue;
    final description = switch (item['Description']) {
      final String text => text.trim(),
      _ => '',
    };
    final system = path.windows.isWithin(systemRoot, file);
    byName.putIfAbsent(
      name.toLowerCase(),
      () => Package(
        packageName: name,
        label: description.isNotEmpty
            ? description
            : path.windows.basenameWithoutExtension(file),
        system: system,
        internet: true,
        lastUpdateTime: 0,
        launchable: !system,
      ),
    );
  }
  return byName.values.toList();
}
