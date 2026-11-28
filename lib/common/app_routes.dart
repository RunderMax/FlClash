import 'package:fl_clash/common/programs.dart';
import 'package:fl_clash/common/slothive.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';

const appRouteDirect = 'DIRECT';
const appRouteBlock = 'REJECT';

/// How the Core names the rule types an app route makes.
const processNameRule = 'ProcessName';
const processPathRule = 'ProcessPathRegex';

/// The app whose folder holds the program at [processPath]; the longest folder
/// wins and case is ignored, as in core/app_folders.go.
String? folderAppOf(Map<String, String> folders, String processPath) {
  if (processPath.isEmpty || folders.isEmpty) return null;
  final path = processPath.toLowerCase();
  String? app;
  var length = 0;
  for (final MapEntry(:key, :value) in folders.entries) {
    if (value.length > length && path.startsWith(value.toLowerCase())) {
      app = key;
      length = value.length;
    }
  }
  return app;
}

/// The Core names the group of an app's own picks so; kept in step with
/// appPickGroupPrefix in core/auto_pick.go.
const appPicksGroupPrefix = 'Sloth Pick · ';

/// Kept in step with linePrefix in core/auto_pick.go.
const slothLinePrefix = 'Sloth Line';

String appPicksGroupOf(String packageName) =>
    '$appPicksGroupPrefix$packageName';

List<String> _toggled(List<String> items, String item, bool on) => [
  for (final element in items)
    if (element != item) element,
  if (on) item,
];

extension AppRoutesExt on PatchClashConfig {
  /// Routed apps first, then those only guarded.
  List<String> get appRouteApps => [
    ...slothAppRoutes.keys,
    for (final app in slothAppPureOnly)
      if (!slothAppRoutes.containsKey(app)) app,
  ];

  bool usesOwnPicks(String packageName) =>
      slothAppRoutes[packageName] == appPicksGroupOf(packageName);

  Map<String, Object> get appPicksRequest => {
    for (final MapEntry(key: app, value: picks) in slothAppPicks.entries)
      if (picks.isNotEmpty && usesOwnPicks(app))
        app: {'proxies': picks, 'auto': slothAppAuto.contains(app)},
  };

  /// The folders of the apps routed or guarded, each standing for every
  /// program under it.
  Map<String, String> get appFolderRequest => {
    for (final MapEntry(key: app, value: folder) in slothAppFolders.entries)
      if (slothAppRoutes.containsKey(app) || slothAppPureOnly.contains(app))
        app: folder,
  };

  PatchClashConfig withAppFolder(String packageName, String folder) =>
      slothAppFolders[packageName] == folder
      ? this
      : copyWith(slothAppFolders: {...slothAppFolders, packageName: folder});

  /// Folds what was set on one program of an app at a time, before an app was
  /// routed whole, into the app: its lead takes the first such program's
  /// settings unless it has its own, and the programs' entries go.
  PatchClashConfig mergedIntoApps(Iterable<ProgramGroup> groups) {
    var config = this;
    for (final group in groups) {
      final folder = group.folder;
      if (folder == null) continue;
      final lead = group.lead.packageName;
      final olds = [
        for (final program in group.programs)
          if (program.packageName != lead &&
              config.appRouteApps.contains(program.packageName))
            program.packageName,
      ];
      if (olds.isEmpty) continue;
      if (!config.appRouteApps.contains(lead)) {
        config = config._moved(olds.first, lead);
      }
      for (final old in olds) {
        config = config._without(old);
      }
      config = config.withAppFolder(lead, folder);
    }
    return config;
  }

  PatchClashConfig _moved(String from, String to) {
    final picks = slothAppPicks[from] ?? const <String>[];
    final route = slothAppRoutes[from];
    var config = this;
    if (usesOwnPicks(from) && picks.isNotEmpty) {
      config = config.withAppPicks(to, picks);
    } else if (route != null) {
      config = config.withAppRoute(to, route);
    }
    return config.copyWith(
      slothAppAuto: _toggled(
        config.slothAppAuto,
        to,
        slothAppAuto.contains(from),
      ),
      slothAppPureOnly: _toggled(
        config.slothAppPureOnly,
        to,
        slothAppPureOnly.contains(from),
      ),
      slothAppPureNormal: _toggled(
        config.slothAppPureNormal,
        to,
        slothAppPureNormal.contains(from),
      ),
    );
  }

  PatchClashConfig _without(String app) => copyWith(
    slothAppRoutes: {...slothAppRoutes}..remove(app),
    slothAppPicks: {...slothAppPicks}..remove(app),
    slothAppAuto: _toggled(slothAppAuto, app, false),
    slothAppPureOnly: _toggled(slothAppPureOnly, app, false),
    slothAppPureNormal: _toggled(slothAppPureNormal, app, false),
    slothAppFolders: {...slothAppFolders}..remove(app),
  );

  Map<String, List<String>> get siteRequest => {
    for (final MapEntry(key: site, value: matchers) in slothSites.entries)
      if (slothAppRoutes.containsKey(site)) site: matchers,
    for (final service in SlothiveService.values)
      if (slothAppRoutes.containsKey(service.key))
        service.key: [service.matcher],
  };

  /// Routes [site] by [matchers], replacing what it was made of before.
  PatchClashConfig withSite(String site, List<String> matchers) =>
      copyWith(slothSites: {...slothSites, site: matchers});

  /// Off never looks up which app a connection is from, as the rules need.
  /// [listsApps] is false where the app cannot name apps as the Core does.
  PatchClashConfig appRoutesFor({required bool listsApps}) {
    if (slothAppRoutes.isEmpty && slothAppPureOnly.isEmpty) {
      return this;
    }
    if (!listsApps) {
      return copyWith(slothAppRoutes: const {}, slothAppPureOnly: const []);
    }
    return findProcessMode == FindProcessMode.off
        ? copyWith(findProcessMode: FindProcessMode.strict)
        : this;
  }

  PatchClashConfig withAppRoute(String packageName, String? target) {
    final routes = {...slothAppRoutes};
    if (target == null) {
      routes.remove(packageName);
      return copyWith(
        slothAppRoutes: routes,
        slothSites: {...slothSites}..remove(packageName),
      );
    }
    routes[packageName] = target;
    return copyWith(slothAppRoutes: routes);
  }

  /// No picks puts an app that took them back on the rules.
  PatchClashConfig withAppPicks(String packageName, List<String> picks) {
    final all = {...slothAppPicks};
    if (picks.isNotEmpty) {
      all[packageName] = picks;
      return copyWith(
        slothAppPicks: all,
      ).withAppRoute(packageName, appPicksGroupOf(packageName));
    }
    all.remove(packageName);
    final next = copyWith(slothAppPicks: all);
    return usesOwnPicks(packageName)
        ? next.withAppRoute(packageName, null)
        : next;
  }

  PatchClashConfig withAppAuto(String packageName, bool auto) =>
      copyWith(slothAppAuto: _toggled(slothAppAuto, packageName, auto));

  PatchClashConfig withAppPureOnly(String packageName, bool on) => copyWith(
    slothAppPureOnly: _toggled(slothAppPureOnly, packageName, on),
    slothAppPureNormal: on
        ? slothAppPureNormal
        : _toggled(slothAppPureNormal, packageName, false),
  );

  bool appTakesNormal(String packageName) =>
      slothAppPureOnly.contains(packageName)
      ? slothAppPureNormal.contains(packageName)
      : slothPureOnly && slothPureNormal;

  /// The app keeps a floor of its own under the switch for all.
  PatchClashConfig withAppPureNormal(String packageName, bool normal) =>
      copyWith(
        slothAppPureOnly: _toggled(slothAppPureOnly, packageName, true),
        slothAppPureNormal: _toggled(slothAppPureNormal, packageName, normal),
      );
}
