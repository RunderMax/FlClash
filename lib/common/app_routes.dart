import 'package:fl_clash/common/slothive.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';

const appRouteDirect = 'DIRECT';
const appRouteBlock = 'REJECT';

/// How the Core names the rule type an app route makes.
const processNameRule = 'ProcessName';

/// The Core names the group of an app's own picks so; kept in step with
/// appPickGroupPrefix in core/auto_pick.go.
const appPicksGroupPrefix = 'Sloth Pick · ';

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

  PatchClashConfig withAppPureOnly(String packageName, bool on) =>
      copyWith(slothAppPureOnly: _toggled(slothAppPureOnly, packageName, on));
}
