import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/models/models.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

final _appName = RegExp(r'^[A-Za-z0-9_][A-Za-z0-9_ \-]*(\.[A-Za-z0-9_\-]+)+$');
final _noise = RegExp('unins|uninstall|setup|crash', caseSensitive: false);

/// One program as Windows lists it: a Start menu entry's folder, or a running
/// executable outside every such folder.
class ProgramGroup {
  const ProgramGroup({
    required this.name,
    required this.icon,
    required this.programs,
  });

  final String name;
  final String? icon;
  final List<Package> programs;
}

final programGroups = ValueNotifier<List<ProgramGroup>>(const []);
final _icons = <String, String>{};

String? programIconOf(String executable) => _icons[executable.toLowerCase()];

const _script = r'''
[Console]::OutputEncoding = [Text.Encoding]::UTF8
Add-Type -AssemblyName System.Drawing
$icons = $env:SLOTH_ICONS
New-Item -ItemType Directory -Force -Path $icons | Out-Null
$sys = $env:SystemRoot
$md5 = [Security.Cryptography.MD5]::Create()
function Icon($file) {
  $hash = [BitConverter]::ToString($md5.ComputeHash([Text.Encoding]::UTF8.GetBytes($file.ToLower()))).Replace('-', '')
  $png = Join-Path $icons "$hash.png"
  if (-not (Test-Path -LiteralPath $png)) {
    try { [Drawing.Icon]::ExtractAssociatedIcon($file).ToBitmap().Save($png, [Drawing.Imaging.ImageFormat]::Png) } catch { return $null }
  }
  return $png
}
function Exe($file, $running) {
  $info = (Get-Item -LiteralPath $file -ErrorAction SilentlyContinue).VersionInfo
  return [pscustomobject]@{ path = $file; description = "$($info.FileDescription)".Trim(); running = $running; icon = $(if ($running) { Icon $file } else { $null }) }
}
$running = @{}
Get-Process | Where-Object { $_.SessionId -ne 0 -and $_.Path } | ForEach-Object { $running[$_.Path.ToLower()] = $_.Path }
$shell = New-Object -ComObject WScript.Shell
$apps = [ordered]@{}
$menus = @("$env:ProgramData\Microsoft\Windows\Start Menu\Programs", "$env:APPDATA\Microsoft\Windows\Start Menu\Programs")
foreach ($lnk in Get-ChildItem -Path $menus -Recurse -Filter *.lnk -ErrorAction SilentlyContinue) {
  try { $target = $shell.CreateShortcut($lnk.FullName).TargetPath } catch { continue }
  if (-not $target -or -not $target.ToLower().EndsWith('.exe') -or $target.StartsWith($sys, 'OrdinalIgnoreCase')) { continue }
  if (-not (Test-Path -LiteralPath $target)) { continue }
  $dir = Split-Path -Parent $target
  if (-not $apps.Contains($dir.ToLower())) { $apps[$dir.ToLower()] = @{ name = $lnk.BaseName; main = $target; dir = $dir } }
}
$out = @()
$claimed = @{}
foreach ($app in $apps.Values) {
  $files = @($app.main) + @(Get-ChildItem -LiteralPath $app.dir -Recurse -Depth 2 -Filter *.exe -ErrorAction SilentlyContinue | Select-Object -First 40 | ForEach-Object { $_.FullName })
  $exes = @()
  foreach ($file in ($files | Sort-Object -Unique)) {
    $claimed[$file.ToLower()] = $true
    $exes += Exe $file $running.ContainsKey($file.ToLower())
  }
  $out += [pscustomobject]@{ name = $app.name; icon = (Icon $app.main); exes = $exes }
}
foreach ($file in $running.Values) {
  if ($claimed.ContainsKey($file.ToLower()) -or $file.StartsWith($sys, 'OrdinalIgnoreCase')) { continue }
  $exe = Exe $file $true
  $out += [pscustomobject]@{ name = $(if ($exe.description) { $exe.description } else { [IO.Path]::GetFileNameWithoutExtension($file) }); icon = $exe.icon; exes = @($exe) }
}
ConvertTo-Json -InputObject $out -Depth 4 -Compress
''';

/// Windows keeps no list of programs by the executable name a PROCESS-NAME
/// rule matches, so the Start menu's entries and what runs stand for one.
Future<List<ProgramGroup>> listPrograms(String iconDir) async {
  final result = await Process.run(
    'powershell',
    ['-NoProfile', '-NonInteractive', '-Command', _script],
    environment: {'SLOTH_ICONS': iconDir},
    stdoutEncoding: utf8,
  );
  if (result.exitCode != 0) {
    throw ProcessException(
      'powershell',
      const ['programs'],
      '${result.stderr}',
      result.exitCode,
    );
  }
  return parsePrograms(
    result.stdout as String,
    own: path.windows.dirname(Platform.resolvedExecutable),
  );
}

/// Programs under [own], this app and its core, are left out, as is what only
/// installs or reports crashes.
@visibleForTesting
List<ProgramGroup> parsePrograms(String output, {required String own}) {
  final decoded = output.trim().isEmpty ? null : jsonDecode(output);
  final items = switch (decoded) {
    final List<dynamic> list => list,
    final Map<dynamic, dynamic> map => [map],
    _ => const [],
  };
  final groups = <ProgramGroup>[];
  final seen = <String>{};
  for (final item in items.whereType<Map<dynamic, dynamic>>()) {
    final icon = _text(item['icon']);
    final programs = <Package>[];
    final rawExes = item['exes'];
    for (final exe in [
      if (rawExes is List) ...rawExes else if (rawExes is Map) rawExes,
    ].whereType<Map<dynamic, dynamic>>()) {
      final file = _text(exe['path']);
      if (file == null || path.windows.isWithin(own, file)) continue;
      final name = path.windows.basename(file);
      if (!_appName.hasMatch(name) || _noise.hasMatch(name)) continue;
      if (!seen.add(name.toLowerCase())) continue;
      final ownIcon = _text(exe['icon']) ?? icon;
      if (ownIcon != null) _icons[name.toLowerCase()] = ownIcon;
      programs.add(
        Package(
          packageName: name,
          label:
              _text(exe['description']) ??
              path.windows.basenameWithoutExtension(file),
          system: false,
          internet: true,
          lastUpdateTime: 0,
          launchable: true,
        ),
      );
    }
    final name = _text(item['name']);
    if (name == null || programs.isEmpty) continue;
    groups.add(ProgramGroup(name: name, icon: icon, programs: programs));
  }
  return groups;
}

String? _text(Object? value) => switch (value) {
  final String text when text.trim().isNotEmpty => text.trim(),
  _ => null,
};
