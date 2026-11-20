import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/models/models.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

final _appName = RegExp(r'^[^\s,@][^,\x00-\x1f]*[^\s,]$');
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
final _paths = <String, String>{};
final _ownIcons = <String>{};

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
Get-CimInstance Win32_Process -Property SessionId, ExecutablePath | Where-Object { $_.SessionId -ne 0 -and $_.ExecutablePath } | ForEach-Object { $running[$_.ExecutablePath.ToLower()] = $_.ExecutablePath }
$shell = New-Object -ComObject WScript.Shell
$apps = [ordered]@{}
$menus = @("$env:ProgramData\Microsoft\Windows\Start Menu\Programs", "$env:APPDATA\Microsoft\Windows\Start Menu\Programs", "$env:PUBLIC\Desktop", [Environment]::GetFolderPath('Desktop'))
foreach ($lnk in Get-ChildItem -Path $menus -Recurse -Filter *.lnk -ErrorAction SilentlyContinue) {
  try { $target = $shell.CreateShortcut($lnk.FullName).TargetPath } catch { continue }
  if (-not $target -or -not $target.ToLower().EndsWith('.exe') -or $target.StartsWith($sys, 'OrdinalIgnoreCase')) { continue }
  if ($lnk.BaseName -match '卸载|删除|uninstall|remove' -or [IO.Path]::GetFileName($target) -match 'unins|uninstall|setup|update') { continue }
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

const _macScript = r"""
ObjC.import('Foundation');
var sh = Application.currentApplication();
sh.includeStandardAdditions = true;
var fm = $.NSFileManager.defaultManager;
var iconDir = ObjC.unwrap($.NSProcessInfo.processInfo.environment.objectForKey('SLOTH_ICONS'));
fm.createDirectoryAtPathWithIntermediateDirectoriesAttributesError($(iconDir), true, $(), $());
function q(s) { return "'" + s.replace(/'/g, "'\\''") + "'"; }
function lines(cmd) { try { return sh.doShellScript(cmd).split(/[\r\n]+/).filter(String); } catch (e) { return []; } }
function plist(bundle) { var d = $.NSDictionary.dictionaryWithContentsOfFile($(bundle + '/Contents/Info.plist')); return d.isNil() ? null : d; }
function key(d, k) { var v = d.objectForKey(k); return v.isNil() ? null : ObjC.unwrap(v); }
function hash(s) { var h = 5381; for (var i = 0; i < s.length; i++) h = ((h * 33) ^ s.charCodeAt(i)) >>> 0; return h.toString(16); }
function icon(bundle, d) {
  var name = key(d, 'CFBundleIconFile');
  if (!name) return null;
  if (!/\.icns$/.test(name)) name += '.icns';
  var src = bundle + '/Contents/Resources/' + name;
  if (!fm.fileExistsAtPath($(src))) return null;
  var png = iconDir + '/' + hash(bundle) + '.png';
  if (!fm.fileExistsAtPath($(png))) {
    try { sh.doShellScript('sips -s format png -Z 64 ' + q(src) + ' --out ' + q(png)); } catch (e) { return null; }
  }
  return png;
}
function exe(bundle, d) { var e = key(d, 'CFBundleExecutable'); return e ? bundle + '/Contents/MacOS/' + e : null; }
function label(bundle, d) { return key(d, 'CFBundleDisplayName') || key(d, 'CFBundleName') || bundle.split('/').pop().replace(/\.app$/, ''); }
var running = {};
lines('ps -axo comm=').forEach(function (p) { running[p] = true; });
var bundles = [];
['/Applications', ObjC.unwrap($.NSHomeDirectory()) + '/Applications'].forEach(function (dir) {
  lines('find ' + q(dir) + ' -maxdepth 2 -name "*.app" -prune').forEach(function (b) { bundles.push(b); });
});
var claimed = {};
var out = [];
function group(bundle) {
  var d = plist(bundle);
  if (!d) return;
  var exes = [];
  var main = exe(bundle, d);
  if (main) exes.push({ path: main, description: label(bundle, d), running: !!running[main], icon: null });
  lines('find ' + q(bundle + '/Contents') + ' -maxdepth 6 -name "*.app" -prune').forEach(function (h) {
    var hd = plist(h);
    var he = hd && exe(h, hd);
    if (he) exes.push({ path: he, description: label(h, hd), running: !!running[he], icon: null });
  });
  exes.forEach(function (e) { claimed[e.path] = true; });
  if (exes.length) out.push({ name: label(bundle, d), icon: icon(bundle, d), exes: exes });
}
bundles.forEach(group);
Object.keys(running).forEach(function (p) {
  var m = p.match(/^(.*?\.app)\/Contents\/MacOS\//);
  if (!m || claimed[p] || /^\/System\//.test(p)) return;
  group(m[1]);
});
JSON.stringify(out);
""";

/// Windows keeps no list of programs by the executable name a PROCESS-NAME
/// rule matches, so the Start menu's entries and what runs stand for one; a
/// Mac lists its apps' bundles and the helper apps inside them.
Future<List<ProgramGroup>> listPrograms(String iconDir) async {
  final mac = Platform.isMacOS;
  final result = await Process.run(
    mac ? 'osascript' : 'powershell',
    mac
        ? ['-l', 'JavaScript', '-e', _macScript]
        : ['-NoProfile', '-NonInteractive', '-Command', _script],
    environment: {'SLOTH_ICONS': iconDir},
    stdoutEncoding: utf8,
  );
  if (result.exitCode != 0) {
    throw ProcessException(
      mac ? 'osascript' : 'powershell',
      const ['programs'],
      '${result.stderr}',
      result.exitCode,
    );
  }
  final executable = Platform.resolvedExecutable;
  return parsePrograms(
    result.stdout as String,
    own: mac
        ? path.posix.dirname(path.posix.dirname(path.posix.dirname(executable)))
        : path.windows.dirname(executable),
  );
}

const _iconScript = r"""
[Console]::OutputEncoding = [Text.Encoding]::UTF8
Add-Type -AssemblyName System.Drawing
$icons = $env:SLOTH_ICONS
$md5 = [Security.Cryptography.MD5]::Create()
$out = @{}
foreach ($file in ($env:SLOTH_FILES -split "`n")) {
  if (-not $file) { continue }
  $hash = [BitConverter]::ToString($md5.ComputeHash([Text.Encoding]::UTF8.GetBytes($file.ToLower()))).Replace('-', '')
  $png = Join-Path $icons "$hash.png"
  if (-not (Test-Path -LiteralPath $png)) {
    try { [Drawing.Icon]::ExtractAssociatedIcon($file).ToBitmap().Save($png, [Drawing.Imaging.ImageFormat]::Png) } catch { continue }
  }
  $out[$file] = $png
}
ConvertTo-Json -InputObject $out -Compress
""";

/// Listing every program's own icon took Windows minutes, so a group's are
/// read once it is opened.
Future<void> loadProgramIcons(ProgramGroup group, String iconDir) async {
  if (!Platform.isWindows) return;
  final files = [
    for (final program in group.programs)
      if (!_ownIcons.contains(program.packageName.toLowerCase()))
        ?_paths[program.packageName.toLowerCase()],
  ];
  if (files.isEmpty) return;
  final result = await Process.run(
    'powershell',
    ['-NoProfile', '-NonInteractive', '-Command', _iconScript],
    environment: {'SLOTH_ICONS': iconDir, 'SLOTH_FILES': files.join('\n')},
    stdoutEncoding: utf8,
  );
  final decoded = jsonDecode(result.stdout as String);
  if (decoded is! Map) return;
  for (final MapEntry(:key, :value) in decoded.entries) {
    if (key is! String || value is! String) continue;
    final name = path.windows.basename(key).toLowerCase();
    _icons[name] = value;
    _ownIcons.add(name);
  }
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
      _paths[name.toLowerCase()] = file;
      final ownIcon = _text(exe['icon']);
      if (ownIcon != null) _ownIcons.add(name.toLowerCase());
      if (ownIcon ?? icon case final shown?) _icons[name.toLowerCase()] = shown;
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
