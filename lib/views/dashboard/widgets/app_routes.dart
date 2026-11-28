import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:fl_clash/common/app_exits.dart';
import 'package:fl_clash/common/app_routes.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/programs.dart';
import 'package:fl_clash/common/site_lookup.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:fl_clash/providers/app_exits.dart';
import 'package:fl_clash/providers/app_route_activity.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/views/dashboard/layout.dart';
import 'package:fl_clash/views/dashboard/style.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' show join;

import 'card.dart';
import 'fastest_nodes.dart';
import 'in_use.dart';

const _cardRows = 4;
const _cardIcon = 32.0;
const _listIcon = 40.0;

String _targetLabel(BuildContext context, String target) {
  final appLocalizations = context.appLocalizations;
  return switch (target) {
    appRouteDirect => appLocalizations.direct,
    appRouteBlock => appLocalizations.appRouteBlock,
    slothPicksGroup => appLocalizations.fastestNodes,
    _ when target.startsWith(appPicksGroupPrefix) =>
      appLocalizations.fastestNodes,
    _ => target,
  };
}

/// Every name a route can still reach; empty while the Core has sent none.
Set<String> _reachable(List<Group> groups) => {
  for (final group in groups) ...[
    group.name,
    for (final proxy in group.all) proxy.name,
  ],
};

/// Direct and blocked traffic leave through no node to time.
bool _measured(String target) =>
    target != appRouteDirect && target != appRouteBlock;

/// An app's own picks group comes after the Core applies them, so the picks
/// stand for it meanwhile.
bool _missing(
  String target,
  Set<String> reachable, [
  List<String> picks = const [],
]) {
  if (reachable.isEmpty ||
      target == appRouteDirect ||
      target == appRouteBlock) {
    return false;
  }
  if (target.startsWith(appPicksGroupPrefix)) {
    return !picks.any(reachable.contains);
  }
  return !reachable.contains(target);
}

/// What a speed test times: an app's own picks stand in for its group.
Set<String> _timed(PatchClashConfig config) => {
  for (final MapEntry(key: app, value: target) in config.slothAppRoutes.entries)
    if (config.usesOwnPicks(app))
      ...?config.slothAppPicks[app]
    else if (_measured(target))
      target,
};

Color _targetColor(BuildContext context, String target, bool missing) {
  final colorScheme = context.colorScheme;
  if (missing || target == appRouteBlock) {
    return colorScheme.error;
  }
  return target == appRouteDirect
      ? colorScheme.onSurfaceVariant
      : colorScheme.primary;
}

/// An automatic group's pick is the line holding its nodes; the line's is the node.
String? _pickInUse(WidgetRef ref, String group) {
  final name = ref.watch(selectedProxyNameProvider(group));
  return name != null && name.startsWith(slothLinePrefix)
      ? ref.watch(selectedProxyNameProvider(name))
      : name;
}

void _showApps(BuildContext context) {
  showSheet<void>(
    context: context,
    props: nestedPagedSheetProps,
    builder: (_) => NestedPagedSheet(builder: (_) => const _AppsPage()),
  );
}

void _showTargets(BuildContext context, String packageName, String label) {
  unawaited(
    showInSheet<void>(
      context,
      builder: (_) => _TargetsPage(packageName: packageName, label: label),
    ),
  );
}

class AppRoutesCard extends ConsumerStatefulWidget {
  const AppRoutesCard({super.key});

  @override
  ConsumerState<AppRoutesCard> createState() => _AppRoutesCardState();
}

class _AppRoutesCardState extends ConsumerState<AppRoutesCard> {
  final Set<String> _tested = {};

  @override
  void initState() {
    super.initState();
    final listed = ref.read(patchClashConfigProvider).appRouteApps;
    if (listed.isNotEmpty && ref.read(packagesProvider).isEmpty) {
      unawaited(
        ref
            .read(systemActionProvider.notifier)
            .getPackages()
            .catchError((Object _) => const <Package>[]),
      );
    }
    void testLater() => runAfterFrame(_testUnmeasured);
    ref.listenManual(groupsProvider, (_, _) => testLater());
    ref.listenManual(
      patchClashConfigProvider.select(
        (state) => (state.slothAppRoutes, state.slothAppPicks),
      ),
      (_, _) => testLater(),
    );
    testLater();
  }

  /// Each target is timed once by itself, so a speed shows without a tap.
  void _testUnmeasured() {
    if (!mounted || ref.read(groupsProvider).isEmpty) {
      return;
    }
    _test([
      for (final target in _timed(ref.read(patchClashConfigProvider)))
        if (_tested.add(target) &&
            ref.read(delayProvider(proxyName: target)) == null)
          target,
    ]);
  }

  void _test(Iterable<String> targets) {
    final byName = {
      for (final group in ref.read(groupsProvider))
        for (final proxy in group.all) proxy.name: proxy,
    };
    final proxies = [
      for (final target in targets)
        if (_measured(target)) byName[target] ?? Proxy(name: target, type: ''),
    ];
    if (proxies.isNotEmpty) {
      unawaited(ref.read(proxiesActionProvider.notifier).delayTest(proxies));
    }
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final colorScheme = context.colorScheme;
    final mobile = !DashboardDensityScope.of(context).isDesktop;
    final config = ref.watch(patchClashConfigProvider);
    final labels = {
      for (final package in ref.watch(packagesProvider))
        package.packageName: package.label,
      for (final service in SlothiveService.values) service.key: service.label,
    };
    final reachable = _reachable(ref.watch(groupsProvider));
    final exits = ref.watch(appExitsProvider).value ?? const {};
    final active = ref.watch(activeRoutedAppsProvider);
    final blocked = ref.watch(
      guardBlockedProvider.select((state) => state.apps),
    );
    final apps = config.appRouteApps;
    final timed = _timed(config);
    final shown = apps.take(_cardRows).toList();
    final hidden = apps.length - shown.length;
    return DashboardCard(
      semanticLabel: appLocalizations.appRoutes,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: mobile ? MainAxisSize.min : MainAxisSize.max,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.appsList,
            title: appLocalizations.appRoutes,
            trailing: [
              Transform.translate(
                offset: const Offset(8, 0),
                child: DashboardIconButton(
                  glyph: AppGlyphs.speed,
                  tooltip: appLocalizations.appRoutesTest,
                  onPressed: timed.isNotEmpty ? () => _test(timed) : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (shown.isEmpty)
            Text(
              appLocalizations.appRoutesIdle,
              style: AppTextStyle.subheadline
                  .of(context)
                  .copyWith(color: colorScheme.onSurfaceVariant),
            )
          else
            for (final packageName in shown) ...[
              _RouteRow(
                packageName: packageName,
                label: labels[packageName] ?? packageName.replaceFirst('@', ''),
                target: config.slothAppRoutes[packageName],
                picks: config.usesOwnPicks(packageName)
                    ? config.slothAppPicks[packageName] ?? const []
                    : null,
                auto: config.slothAppAuto.contains(packageName),
                missing: switch (config.slothAppRoutes[packageName]) {
                  final target? => _missing(
                    target,
                    reachable,
                    config.slothAppPicks[packageName] ?? const [],
                  ),
                  null => false,
                },
                latest: exits[packageName]?.firstOrNull,
                active: active.contains(packageName),
                blocked: blocked.contains(packageName),
              ),
              const SizedBox(height: 6),
            ],
          const SizedBox(height: 6),
          DashboardBlock(
            radius: AppCorner.md,
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            onTap: () => _showApps(context),
            semanticLabel: appLocalizations.appRoutesChoose,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    appLocalizations.appRoutesChoose,
                    style: AppTextStyle.subheadline.of(
                      context,
                      emphasized: true,
                    ),
                  ),
                ),
                if (hidden > 0)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 4),
                    child: Text(
                      '+$hidden',
                      style: AppTextStyle.footnote
                          .of(context, emphasized: true)
                          .toTabular
                          .copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ),
                GlyphIcon(
                  AppGlyphs.chevronForward,
                  size: 18,
                  color: colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteRow extends ConsumerWidget {
  const _RouteRow({
    required this.packageName,
    required this.label,
    required this.target,
    required this.picks,
    required this.auto,
    required this.missing,
    required this.latest,
    required this.active,
    required this.blocked,
  });

  final String packageName;
  final String label;

  /// None while the app only has the guard and follows the rules.
  final String? target;

  /// Set while the app takes its own picks.
  final List<String>? picks;
  final bool auto;
  final bool missing;
  final AppExit? latest;
  final bool active;
  final bool blocked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appLocalizations = context.appLocalizations;
    final colorScheme = context.colorScheme;
    final target = this.target;
    final picks = this.picks;
    final current = picks == null
        ? null
        : _pickInUse(ref, appPicksGroupOf(packageName));
    final color = target == null
        ? colorScheme.onSurfaceVariant
        : _targetColor(context, target, missing);
    final targetLabel = switch (target) {
      null => appLocalizations.appRouteFollow,
      _ when current != null && current.isNotEmpty => current,
      final target => _targetLabel(context, target),
    };
    final timed = picks != null
        ? current
        : target != null && _measured(target)
        ? target
        : null;
    final delay = timed == null || timed.isEmpty
        ? null
        : ref.watch(delayProvider(proxyName: timed));
    final inUse = active && !blocked;
    final row = Row(
      children: [
        InUseBadge(inUse: inUse),
        PackageIcon(packageName: packageName, size: _cardIcon),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 2,
            children: [
              AnimatedDefaultTextStyle(
                duration: context.motionDuration(commonDuration),
                style: AppTextStyle.subheadline
                    .of(context, emphasized: true)
                    .copyWith(
                      color: inUse
                          ? colorScheme.primary
                          : colorScheme.onSurface,
                    ),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (latest case final latest?)
                _ExitLine(
                  exit: latest,
                  style: AppTextStyle.caption1
                      .of(context)
                      .copyWith(color: colorScheme.onSurfaceVariant),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        if (missing)
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 4),
            child: GlyphIcon(AppGlyphs.warning, size: 16, color: color),
          ),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            spacing: 2,
            children: [
              Text(
                targetLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyle.footnote
                    .of(context, emphasized: true)
                    .copyWith(color: color),
              ),
              if (blocked)
                Text(
                  appLocalizations.guardStopped,
                  style: AppTextStyle.caption1
                      .of(context, emphasized: true)
                      .copyWith(color: colorScheme.error),
                )
              else if (delay != null)
                Text(
                  delay < 0 ? appLocalizations.timeout : '$delay ms',
                  style: AppTextStyle.caption1
                      .of(context, emphasized: true)
                      .toTabular
                      .copyWith(color: colorScheme.delayColor(delay)),
                ),
            ],
          ),
        ),
      ],
    );
    return InUseFrame(
      inUse: inUse,
      radius: AppCorner.md,
      child: DashboardBlock(
        radius: AppCorner.md,
        padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
        onTap: () => _showTargets(context, packageName, label),
        semanticLabel: [
          label,
          targetLabel,
          if (auto && picks != null) appLocalizations.auto,
          if (inUse) appLocalizations.pickInUse,
          if (blocked) appLocalizations.guardStopped,
          if (missing) appLocalizations.appRouteMissing,
        ].join(' '),
        child: picks == null || picks.isEmpty
            ? row
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 8,
                children: [
                  row,
                  _PicksBar(
                    packageName: packageName,
                    picks: picks,
                    auto: auto,
                    current: current,
                  ),
                ],
              ),
      ),
    );
  }
}

/// Switches an app between its own picks in one tap; picking a node by hand
/// turns the automatic choice off.
class _PicksBar extends ConsumerWidget {
  const _PicksBar({
    required this.packageName,
    required this.picks,
    required this.auto,
    required this.current,
  });

  final String packageName;
  final List<String> picks;
  final bool auto;
  final String? current;

  void _setAuto(WidgetRef ref, bool auto) {
    ref
        .read(patchClashConfigProvider.notifier)
        .update((state) => state.withAppAuto(packageName, auto));
  }

  Future<void> _pick(WidgetRef ref, String node) async {
    if (auto) {
      _setAuto(ref, false);
    }
    await ref
        .read(proxiesActionProvider.notifier)
        .changeProxy(groupName: appPicksGroupOf(packageName), proxyName: node);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final background = DashboardColors.of(context).card;
    final style = AppTextStyle.footnote.of(context, emphasized: true);
    Widget pill(
      String label, {
      required bool selected,
      required VoidCallback onTap,
    }) => DashboardConnectedButton(
      selected: selected,
      first: true,
      last: true,
      outer: AppCorner.full,
      inner: AppCorner.full,
      background: background,
      semanticLabel: label,
      onTap: onTap,
      builder: (foreground) => SizedBox(
        height: 30,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Center(
            widthFactor: 1,
            child: Text(
              label,
              maxLines: 1,
              style: style.copyWith(color: foreground),
            ),
          ),
        ),
      ),
    );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        spacing: 6,
        children: [
          pill(
            context.appLocalizations.auto,
            selected: auto,
            onTap: () => _setAuto(ref, !auto),
          ),
          for (final node in picks)
            pill(
              node,
              selected: !auto && node == current,
              onTap: () => unawaited(_pick(ref, node)),
            ),
        ],
      ),
    );
  }
}

class _AppsPage extends ConsumerStatefulWidget {
  const _AppsPage();

  @override
  ConsumerState<_AppsPage> createState() => _AppsPageState();
}

class _AppsPageState extends ConsumerState<_AppsPage> {
  late bool _loaded = ref.read(packagesProvider).isNotEmpty;
  bool _granted = true;
  String _query = '';

  /// Taken once, so an app routed from this page keeps its row in place.
  late final Set<String> _pinned = {
    ...ref.read(patchClashConfigProvider).appRouteApps,
  };

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final action = ref.read(systemActionProvider.notifier);
    await action.getPackages().catchError((Object _) => const <Package>[]);
    final granted = await action.isInstalledAppsPermissionGranted();
    if (mounted) {
      setState(() {
        _granted = granted;
        _loaded = true;
      });
    }
  }

  Future<void> _authorize() async {
    final appLocalizations = context.appLocalizations;
    final granted = await ref
        .read(systemActionProvider.notifier)
        .requestInstalledAppsPermission();
    if (!mounted) {
      return;
    }
    if (granted) {
      await _load();
      return;
    }
    final res = await dialogs.showMessage(
      message: TextSpan(
        text: appLocalizations.installedAppsPermissionDeniedMessage,
      ),
      confirmText: appLocalizations.settings,
    );
    if (res == true) {
      await app?.openAppSettings();
    }
  }

  /// Preinstalled apps like YouTube count as system ones, so the list keeps
  /// what has a launcher entry; a search reaches the background ones too.
  List<Package> _visible(List<Package> packages, SearchQuery query) {
    final pinned = <Package>[];
    final rest = <Package>[];
    for (final package in packages) {
      if (_pinned.contains(package.packageName)) {
        pinned.add(package);
      } else if (package.internet &&
          (query.isNotEmpty || package.launchable || !package.system)) {
        rest.add(package);
      }
    }
    int byLabel(Package a, Package b) => a.label.compareTo(b.label);
    return [...pinned..sort(byLabel), ...rest..sort(byLabel)]
        .whereMatches(query, (package) => [package.label, package.packageName])
        .toList();
  }

  /// Windows lists apps as groups of programs, a routed one's first.
  List<ProgramGroup> _visibleGroups(SearchQuery query) {
    bool routed(ProgramGroup group) =>
        group.programs.any((program) => _pinned.contains(program.packageName));
    final groups = [...programGroups.value]
      ..sort((a, b) {
        final first = (routed(a) ? 0 : 1) - (routed(b) ? 0 : 1);
        return first != 0 ? first : a.name.compareTo(b.name);
      });
    return groups
        .whereMatches(
          query,
          (group) => [
            group.name,
            for (final program in group.programs) ...[
              program.label,
              program.packageName,
            ],
          ],
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final packages = ref.watch(packagesProvider);
    final (:routes, :picks) = ref.watch(
      patchClashConfigProvider.select(
        (state) => (routes: state.slothAppRoutes, picks: state.slothAppPicks),
      ),
    );
    final reachable = _reachable(ref.watch(groupsProvider));
    final query = SearchQuery(_query);
    final visible = _visible(packages, query);
    final groups = app == null && system.listsApps
        ? _visibleGroups(query)
        : null;
    final slothive =
        groups != null &&
        query.matches([
          slothiveName,
          for (final service in SlothiveService.values) service.label,
        ]);
    return Scaffold(
      title: appLocalizations.appRoutesChoose,
      searchState: AppBarSearchState(
        onSearch: (value) => setState(() => _query = value),
      ),
      body: packages.isEmpty && !_granted
          ? NullStatus(
              label: appLocalizations.installedAppsPermissionRequired,
              description: appLocalizations.installedAppsPermissionDesc,
              illustration: NullStatusIllustration.permission,
              action: TonalButton(
                size: TonalButtonSize.bar,
                glyph: AppGlyphs.lockOpen,
                label: appLocalizations.authorize,
                onPressed: _authorize,
              ),
            )
          : NullStatusSwitcher(
              isLoading: !_loaded && _query.trim().isEmpty,
              holdsArrival: false,
              isEmpty:
                  _query.trim().isEmpty && (groups?.isEmpty ?? visible.isEmpty),
              isSearching: query.isNotEmpty,
              loadingStatus: const Center(child: ActivityIndicator.page()),
              nullStatus: NullStatus(
                label: appLocalizations.noData,
                illustration: NullStatusIllustration.apps,
              ),
              child: Builder(
                builder: (context) => CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: SizedBox(height: context.contentTopPadding),
                    ),
                    if (app == null)
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                        sliver: SliverToBoxAdapter(
                          child: Text(
                            appLocalizations.appRoutesRunningHint,
                            style: AppTextStyle.footnote
                                .of(context)
                                .copyWith(
                                  color: context.colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ),
                      ),
                    if (_query.trim() case final lookup when lookup.isNotEmpty)
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        sliver: SliverToBoxAdapter(
                          child: ItemPositionProvider(
                            position: ItemPosition.startAndEnd,
                            child: DecorationListItem(
                              leading: const GlyphIcon(AppGlyphs.language),
                              title: Text(
                                appLocalizations.siteLookup(lookup),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: GlyphIcon(
                                AppGlyphs.chevronForward,
                                size: 18,
                                color: context.colorScheme.onSurfaceVariant,
                              ),
                              onPressed: () => unawaited(
                                showInSheet<void>(
                                  context,
                                  builder: (_) =>
                                      _SiteLookupPage(query: lookup),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (slothive)
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        sliver: SliverToBoxAdapter(
                          child: ItemPositionProvider(
                            position: ItemPosition.startAndEnd,
                            child: _SlothiveItem(routes: routes),
                          ),
                        ),
                      ),
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        16,
                        0,
                        16,
                        16 + context.bottomInset,
                      ),
                      sliver: groups != null
                          ? SliverPrismList(
                              itemCount: groups.length,
                              itemBuilder: (_, index) => ItemPositionProvider(
                                key: ValueKey(groups[index].name),
                                position: ItemPosition.get(
                                  index,
                                  groups.length,
                                ),
                                child: _GroupItem(
                                  group: groups[index],
                                  routes: routes,
                                ),
                              ),
                            )
                          : SliverPrismList(
                              itemCount: visible.length,
                              itemBuilder: (_, index) {
                                final package = visible[index];
                                final target = routes[package.packageName];
                                return ItemPositionProvider(
                                  key: ValueKey(package.packageName),
                                  position: ItemPosition.get(
                                    index,
                                    visible.length,
                                  ),
                                  child: _AppItem(
                                    package: package,
                                    target: target,
                                    missing:
                                        target != null &&
                                        _missing(
                                          target,
                                          reachable,
                                          picks[package.packageName] ??
                                              const [],
                                        ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _SlothiveItem extends StatelessWidget {
  const _SlothiveItem({required this.routes});

  final Map<String, String> routes;

  @override
  Widget build(BuildContext context) {
    final routed = [
      for (final service in SlothiveService.values)
        if (routes[service.key] case final target?)
          '${service.name} · ${_targetLabel(context, target)}',
    ];
    return DecorationListItem(
      leading: const PackageIcon(
        packageName: '@$slothiveName',
        size: _listIcon,
      ),
      title: const Text(slothiveName),
      subtitle: Text(
        routed.isEmpty
            ? context.appLocalizations.slothiveDesc
            : routed.join(' / '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: GlyphIcon(
        AppGlyphs.chevronForward,
        size: 18,
        color: context.colorScheme.onSurfaceVariant,
      ),
      onPressed: () => unawaited(
        showInSheet<void>(
          context,
          builder: (_) => _ProgramsPage(
            group: ProgramGroup(
              name: slothiveName,
              icon: null,
              programs: [
                for (final service in SlothiveService.values)
                  slothivePackage(service, service.name),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GroupItem extends ConsumerWidget {
  const _GroupItem({required this.group, required this.routes});

  final ProgramGroup group;
  final Map<String, String> routes;

  /// An app in one folder is routed whole, by its main program.
  void _open(BuildContext context, WidgetRef ref) {
    final folder = group.folder;
    if (folder == null && group.programs.length > 1) {
      unawaited(
        showInSheet<void>(context, builder: (_) => _ProgramsPage(group: group)),
      );
      return;
    }
    if (folder != null) {
      ref
          .read(patchClashConfigProvider.notifier)
          .update(
            (state) => state.withAppFolder(group.lead.packageName, folder),
          );
    }
    _showTargets(context, group.lead.packageName, group.name);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final programs = group.programs;
    final routed = [
      for (final program in programs)
        if (routes[program.packageName] case final target?)
          program == group.lead && group.folder != null
              ? _targetLabel(context, target)
              : '${program.label} · ${_targetLabel(context, target)}',
    ];
    final icon = group.icon;
    return DecorationListItem(
      leading: icon == null
          ? PackageIcon(
              packageName: programs.first.packageName,
              size: _listIcon,
            )
          : ProgramIcon(file: icon, size: _listIcon),
      title: Text(group.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        routed.isEmpty
            ? context.appLocalizations.appRoutesProgramCount(programs.length)
            : routed.join(' / '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: GlyphIcon(
        AppGlyphs.chevronForward,
        size: 18,
        color: context.colorScheme.onSurfaceVariant,
      ),
      onPressed: () => _open(context, ref),
    );
  }
}

class _ProgramsPage extends ConsumerStatefulWidget {
  const _ProgramsPage({required this.group});

  final ProgramGroup group;

  @override
  ConsumerState<_ProgramsPage> createState() => _ProgramsPageState();
}

class _ProgramsPageState extends ConsumerState<_ProgramsPage> {
  @override
  void initState() {
    super.initState();
    unawaited(_loadIcons());
  }

  Future<void> _loadIcons() async {
    try {
      await loadProgramIcons(
        widget.group,
        join(await appPath.homeDirPath, 'program-icons'),
      );
    } on Object catch (_) {
      return;
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    final (:routes, :picks) = ref.watch(
      patchClashConfigProvider.select(
        (state) => (routes: state.slothAppRoutes, picks: state.slothAppPicks),
      ),
    );
    final reachable = _reachable(ref.watch(groupsProvider));
    final programs = group.programs;
    return Scaffold(
      title: group.name,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: SizedBox(height: context.contentTopPadding),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + context.bottomInset),
            sliver: SliverPrismList(
              itemCount: programs.length,
              itemBuilder: (_, index) {
                final program = programs[index];
                final target = routes[program.packageName];
                return ItemPositionProvider(
                  key: ValueKey(program.packageName),
                  position: ItemPosition.get(index, programs.length),
                  child: _AppItem(
                    package: program,
                    target: target,
                    detail: program.packageName.startsWith('@')
                        ? null
                        : program.packageName,
                    missing:
                        target != null &&
                        _missing(
                          target,
                          reachable,
                          picks[program.packageName] ?? const [],
                        ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AppItem extends StatelessWidget {
  const _AppItem({
    required this.package,
    required this.target,
    required this.missing,
    this.detail,
  });

  final Package package;
  final String? target;
  final bool missing;

  /// The executable, which tells apart programs of one app with like names.
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final target = this.target;
    final detail = this.detail;
    return DecorationListItem(
      leading: PackageIcon(packageName: package.packageName, size: _listIcon),
      title: Text(package.label, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: target == null
          ? (detail == null
                ? null
                : Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis))
          : Text(
              detail == null
                  ? _targetLabel(context, target)
                  : '$detail · ${_targetLabel(context, target)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: _targetColor(context, target, missing)),
            ),
      trailing: GlyphIcon(
        AppGlyphs.chevronForward,
        size: 18,
        color: context.colorScheme.onSurfaceVariant,
      ),
      onPressed: () =>
          _showTargets(context, package.packageName, package.label),
    );
  }
}

typedef _Choice = ({
  String? target,
  String title,
  String? subtitle,
  Glyph? glyph,
});

class _TargetsPage extends ConsumerStatefulWidget {
  const _TargetsPage({required this.packageName, required this.label});

  final String packageName;
  final String label;

  @override
  ConsumerState<_TargetsPage> createState() => _TargetsPageState();
}

class _TargetsPageState extends ConsumerState<_TargetsPage> {
  String _query = '';

  String get _ownPicks => appPicksGroupOf(widget.packageName);

  void _update(PatchClashConfig Function(PatchClashConfig state) change) {
    ref.read(patchClashConfigProvider.notifier).update(change);
  }

  /// Its own picks leave the page open, for the switches that come with them.
  void _choose(String? target) {
    if (target == _ownPicks) {
      _choosePicks();
      return;
    }
    _update((state) => state.withAppRoute(widget.packageName, target));
    Navigator.of(context).pop();
  }

  void _choosePicks() {
    final picks = ref
        .read(patchClashConfigProvider)
        .slothAppPicks[widget.packageName];
    unawaited(
      showInSheet<void>(
        context,
        builder: (_) => PicksSheet(
          candidates: nodeNamesOf(ref.read(groupsProvider)),
          picks: picks ?? const [],
          onConfirm: (picks) =>
              _update((state) => state.withAppPicks(widget.packageName, picks)),
        ),
      ),
    );
  }

  Future<void> _selectPick(String node, int index) async {
    final packageName = widget.packageName;
    final config = ref.read(patchClashConfigProvider);
    if (config.slothAppAuto.contains(packageName)) {
      final picks = config.slothAppPicks[packageName] ?? const <String>[];
      final place = await showInSheet<int>(
        context,
        builder: (_) =>
            PickRoleSheet(name: node, count: picks.length, current: index),
      );
      if (place != null) {
        _update(
          (state) => state.withAppPicks(
            packageName,
            placedAt(state.slothAppPicks[packageName] ?? const [], node, place),
          ),
        );
      }
      return;
    }
    unawaited(
      ref
          .read(proxiesActionProvider.notifier)
          .changeProxy(
            groupName: appPicksGroupOf(packageName),
            proxyName: node,
          ),
    );
  }

  List<Widget> _switches({
    required bool ownPicks,
    required bool auto,
    required bool guarded,
    required bool guardAll,
    required bool takesNormal,
  }) {
    final appLocalizations = context.appLocalizations;
    final packageName = widget.packageName;
    void setGuarded(bool value) =>
        _update((state) => state.withAppPureOnly(packageName, value));
    void setNormal(bool value) =>
        _update((state) => state.withAppPureNormal(packageName, value));
    void setAuto(bool value) =>
        _update((state) => state.withAppAuto(packageName, value));
    return [
      if (ownPicks)
        DecorationListItem(
          leading: const GlyphIcon(AppGlyphs.swap),
          title: Text(
            appLocalizations.autoSwitch,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            appLocalizations.autoSwitchDesc,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Switch(value: auto, onChanged: setAuto),
          onPressed: () => setAuto(!auto),
        ),
      if (!packageName.startsWith('@'))
        DecorationListItem(
          leading: const GlyphIcon(AppGlyphs.filter),
          title: Text(
            appLocalizations.pureOnly,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            guardAll
                ? appLocalizations.pureOnlyEverywhere
                : appLocalizations.appPureOnlyDesc,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Switch(
            value: guarded || guardAll,
            onChanged: guardAll ? null : setGuarded,
          ),
          onPressed: guardAll ? null : () => setGuarded(!guarded),
        ),
      if (!packageName.startsWith('@') && (guarded || guardAll))
        DecorationListItem(
          leading: const GlyphIcon(AppGlyphs.sliders),
          title: Text(
            appLocalizations.pureAllowNormal,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            appLocalizations.pureAllowNormalDesc,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Switch(value: takesNormal, onChanged: setNormal),
          onPressed: () => setNormal(!takesNormal),
        ),
    ];
  }

  List<Widget> _section({
    String? title,
    required List<_Choice> choices,
    required String? current,
  }) {
    if (choices.isEmpty) {
      return const [];
    }
    return [
      if (title != null) SliverToBoxAdapter(child: ListHeader(title: title)),
      SliverPrismList(
        itemCount: choices.length,
        itemBuilder: (_, index) {
          final choice = choices[index];
          final selected = choice.target == current;
          final glyph = choice.glyph;
          final subtitle = choice.subtitle;
          return ItemPositionProvider(
            key: ValueKey(choice.target),
            position: ItemPosition.get(index, choices.length),
            child: DecorationListItem(
              leading: glyph == null ? null : GlyphIcon(glyph),
              title: Text(
                choice.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: subtitle == null
                  ? null
                  : Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
              isSelected: selected,
              trailing: selected
                  ? const SelectionCheck()
                  : glyph == null && choice.target != null
                  ? _Delay(name: choice.target!)
                  : null,
              onPressed: () => _choose(choice.target),
            ),
          );
        },
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final packageName = widget.packageName;
    final (:current, :picks, :auto, :guarded, :guardAll, :takesNormal) = ref
        .watch(
          patchClashConfigProvider.select(
            (state) => (
              current: state.slothAppRoutes[packageName],
              picks: state.slothAppPicks[packageName] ?? const <String>[],
              auto: state.slothAppAuto.contains(packageName),
              guarded: state.slothAppPureOnly.contains(packageName),
              guardAll: state.slothPureOnly,
              takesNormal: state.appTakesNormal(packageName),
            ),
          ),
        );
    final groups = ref.watch(groupsProvider);
    final exits = ref.watch(
      appExitsProvider.select((state) => state.value?[widget.packageName]),
    );
    final query = SearchQuery(_query);
    final shownGroups = [
      for (final group in groups)
        if (group.hidden != true && group.name != GroupName.GLOBAL.name) group,
    ].whereMatches(query, (group) => [group.name]);
    final nodes = nodeNamesOf(
      groups,
    ).whereMatches(query, (name) => [name]).toList();
    final fixed = <_Choice>[
      (
        target: null,
        title: appLocalizations.appRouteFollow,
        subtitle: appLocalizations.appRouteFollowDesc,
        glyph: AppGlyphs.rules,
      ),
      (
        target: _ownPicks,
        title: appLocalizations.fastestNodes,
        subtitle: picks.isEmpty
            ? appLocalizations.appRoutePicksDesc
            : appLocalizations.appRoutePicksCount(picks.length),
        glyph: AppGlyphs.bolt,
      ),
      (
        target: appRouteDirect,
        title: appLocalizations.direct,
        subtitle: appLocalizations.appRouteDirectDesc,
        glyph: AppGlyphs.wifi,
      ),
      (
        target: appRouteBlock,
        title: appLocalizations.appRouteBlock,
        subtitle: appLocalizations.appRouteBlockDesc,
        glyph: AppGlyphs.block,
      ),
    ];
    return Scaffold(
      title: widget.label,
      searchState: AppBarSearchState(
        onSearch: (value) => setState(() => _query = value),
      ),
      body: Builder(
        builder: (context) => CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: SizedBox(height: context.sectionsTopPadding),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + context.bottomInset),
              sliver: SliverMainAxisGroup(
                slivers: [
                  if (query.isEmpty && exits != null && exits.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: ListHeader(title: appLocalizations.appExits),
                    ),
                    SliverToBoxAdapter(
                      child: ItemPositionProvider(
                        position: ItemPosition.startAndEnd,
                        child: _ExitItem(
                          exit: exits.first,
                          latest: true,
                          onPressed: () => showInSheet<void>(
                            context,
                            builder: (_) =>
                                _ExitsPage(packageName: widget.packageName),
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (query.isEmpty) ...[
                    ..._section(
                      title: appLocalizations.appRouteTo,
                      choices: fixed,
                      current: current,
                    ),
                    SliverToBoxAdapter(
                      child: ListHeader(title: appLocalizations.settings),
                    ),
                    _SwitchList(
                      items: _switches(
                        ownPicks: current == _ownPicks,
                        auto: auto,
                        guarded: guarded,
                        guardAll: guardAll,
                        takesNormal: takesNormal,
                      ),
                    ),
                    if (current == _ownPicks && picks.isNotEmpty) ...[
                      SliverToBoxAdapter(
                        child: ListHeader(title: appLocalizations.appPickNodes),
                      ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: AppPickNodes(
                            names: picks,
                            current: _pickInUse(
                              ref,
                              appPicksGroupOf(packageName),
                            ),
                            auto: auto,
                            onSelect: _selectPick,
                          ),
                        ),
                      ),
                    ],
                  ],
                  if (query.isEmpty && groups.isEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                        child: Text(
                          appLocalizations.proxyGroupsAfterStart,
                          style: AppTextStyle.footnote
                              .of(context)
                              .copyWith(
                                color: context.colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ),
                    ),
                  ..._section(
                    title: appLocalizations.proxyGroup,
                    current: current,
                    choices: [
                      for (final group in shownGroups)
                        (
                          target: group.name,
                          title: _targetLabel(context, group.name),
                          subtitle: switch (group.now) {
                            final now? when now.isNotEmpty => now,
                            _ => null,
                          },
                          glyph: null,
                        ),
                    ],
                  ),
                  ..._section(
                    title: appLocalizations.nodes,
                    current: current,
                    choices: [
                      for (final name in nodes)
                        (
                          target: name,
                          title: name,
                          subtitle: null,
                          glyph: null,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SwitchList extends StatelessWidget {
  const _SwitchList({required this.items});

  final List<Widget> items;

  @override
  Widget build(BuildContext context) {
    return SliverPrismList(
      itemCount: items.length,
      itemBuilder: (_, index) => ItemPositionProvider(
        position: ItemPosition.get(index, items.length),
        child: items[index],
      ),
    );
  }
}

class _Delay extends ConsumerWidget {
  const _Delay({required this.name});

  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final delay = ref.watch(delayProvider(proxyName: name));
    if (delay == null) {
      return const SizedBox.shrink();
    }
    return Text(
      delay < 0 ? context.appLocalizations.timeout : '$delay ms',
      style: AppTextStyle.footnote
          .of(context, emphasized: true)
          .toTabular
          .copyWith(color: context.colorScheme.delayColor(delay)),
    );
  }
}

String _clock(DateTime time) =>
    '${getDateStringLast2(time.hour)}:${getDateStringLast2(time.minute)}';

String _day(DateTime time) =>
    '${getDateStringLast2(time.month)}-${getDateStringLast2(time.day)}';

String _spanOf(AppExit exit) {
  final AppExit(:first, :last) = exit;
  final start = '${_day(first)} ${_clock(first)}';
  if (last.difference(first) < const Duration(minutes: 1)) {
    return start;
  }
  final sameDay =
      first.year == last.year &&
      first.month == last.month &&
      first.day == last.day;
  return '$start – ${sameDay ? _clock(last) : '${_day(last)} ${_clock(last)}'}';
}

class _ExitLine extends StatelessWidget {
  const _ExitLine({required this.exit, required this.style});

  final AppExit exit;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          if (exit.country.isNotEmpty)
            TextSpan(
              text: '${exit.country.countryFlagEmoji} ',
              style: style.copyWith(fontFamily: FontFamily.twEmoji.value),
            ),
          TextSpan(text: exit.ip),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style.toTabular,
    );
  }
}

class _ExitItem extends StatelessWidget {
  const _ExitItem({required this.exit, this.latest = false, this.onPressed});

  final AppExit exit;
  final bool latest;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final style = AppTextStyle.title3.of(context);
    final when = latest
        ? exit.last.getLastUpdateTimeDesc(context)
        : _spanOf(exit);
    return DecorationListItem(
      leading: SizedBox.square(
        dimension: 28,
        child: Center(
          child: exit.country.isEmpty
              ? const GlyphIcon(AppGlyphs.locate)
              : Text(
                  exit.country.countryFlagEmoji,
                  style: style.copyWith(fontFamily: FontFamily.twEmoji.value),
                ),
        ),
      ),
      title: Text(exit.ip, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${_targetLabel(context, exit.node)} · $when',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: onPressed == null
          ? null
          : GlyphIcon(
              AppGlyphs.chevronForward,
              size: 18,
              color: context.colorScheme.onSurfaceVariant,
            ),
      onPressed: onPressed,
    );
  }
}

class _ExitsPage extends ConsumerWidget {
  const _ExitsPage({required this.packageName});

  final String packageName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exits =
        ref.watch(
          appExitsProvider.select((state) => state.value?[packageName]),
        ) ??
        const [];
    return Scaffold(
      title: context.appLocalizations.appExits,
      body: Builder(
        builder: (context) => CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: SizedBox(height: context.contentTopPadding),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + context.bottomInset),
              sliver: SliverPrismList(
                itemCount: exits.length,
                itemBuilder: (_, index) => ItemPositionProvider(
                  position: ItemPosition.get(index, exits.length),
                  child: _ExitItem(exit: exits[index]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A service named or addressed by [query], made of a category from the
/// bundled list, the sites its official page loads and matching programs.
class _SiteLookupPage extends ConsumerStatefulWidget {
  const _SiteLookupPage({required this.query});

  final String query;

  @override
  ConsumerState<_SiteLookupPage> createState() => _SiteLookupPageState();
}

class _SiteLookupPageState extends ConsumerState<_SiteLookupPage> {
  bool _loading = true;
  List<String> _categories = const [];
  Map<String, int> _sizes = const {};
  String? _category;
  List<String> _domains = const [];
  final _chosenDomains = <String>{};
  List<Package> _programs = const [];
  final _chosenPrograms = <String>{};

  @override
  void initState() {
    super.initState();
    unawaited(_lookup());
  }

  Future<void> _lookup() async {
    final host = hostOf(widget.query);
    final file = join(await appPath.homeDirPath, GEOSITE);
    final results = await Future.wait([
      _categoriesOf(file),
      if (host != null)
        pageDomains(Dio(), host).catchError((_) => [registrableDomain(host)]),
    ]);
    if (!mounted) return;
    final (categories, sizes) =
        results.first as (List<String>, Map<String, int>);
    final domains = results.length > 1
        ? results[1] as List<String>
        : <String>[];
    final words = {
      widget.query.trim().toLowerCase(),
      ...categories.take(1),
    }.where((word) => word.length >= 3);
    final programs = [
      for (final package in ref.read(packagesProvider))
        if (words.any(
          (word) =>
              package.label.toLowerCase().contains(word) ||
              package.packageName.toLowerCase().contains(word),
        ))
          package,
    ];
    setState(() {
      _loading = false;
      _categories = categories.take(5).toList();
      _sizes = sizes;
      _category = categories.firstOrNull;
      _domains = domains;
      _chosenDomains.addAll(domains.where((d) => !sharedDomains.contains(d)));
      _programs = programs;
      _chosenPrograms.addAll(programs.map((program) => program.packageName));
    });
  }

  Future<(List<String>, Map<String, int>)> _categoriesOf(String file) async {
    try {
      final modified = await File(file).lastModified();
      if (DateTime.now().difference(modified) > const Duration(days: 7)) {
        unawaited(
          ref
              .read(geoResourceActionProvider.notifier)
              .updateGeoResource(GeoResource.GEOSITE, announceSuccess: false)
              .catchError((_) {}),
        );
      }
      final book = await readGeosite(file);
      final found = findCategories(book, widget.query);
      return (found, {for (final code in found) code: book[code]!.length});
    } on Object {
      return (const <String>[], const <String, int>{});
    }
  }

  String? get _name {
    final source = _category ?? hostOf(widget.query);
    if (source == null) return null;
    final name = source[0].toUpperCase() + source.substring(1);
    return RegExp(r'^[A-Za-z0-9_][A-Za-z0-9_ .\-]*$').hasMatch(name)
        ? name
        : null;
  }

  void _next() {
    final name = _name;
    if (name == null) return;
    final key = '@$name';
    final matchers = [
      if (_category case final category?) 'GEOSITE,$category',
      for (final domain in _chosenDomains) 'DOMAIN-SUFFIX,$domain',
      for (final program in _chosenPrograms) 'PROCESS-NAME,$program',
    ];
    if (matchers.isEmpty) return;
    ref
        .read(patchClashConfigProvider.notifier)
        .update((state) => state.withSite(key, matchers));
    _showTargets(context, key, name);
  }

  Widget _check(bool on) =>
      on ? const SelectionCheck() : const SizedBox.square(dimension: 24);

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final empty = _categories.isEmpty && _domains.isEmpty && _programs.isEmpty;
    final ready = !empty && _name != null;
    return Scaffold(
      title: widget.query,
      body: NullStatusSwitcher(
        isLoading: _loading,
        holdsArrival: false,
        isEmpty: empty,
        isSearching: false,
        loadingStatus: const Center(child: ActivityIndicator.page()),
        nullStatus: NullStatus(
          label: appLocalizations.siteLookupNone,
          illustration: NullStatusIllustration.apps,
        ),
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: SizedBox(height: context.contentTopPadding),
            ),
            if (_categories.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: ListHeader(title: appLocalizations.siteLookupServices),
              ),
              _SwitchList(
                items: [
                  for (final code in _categories)
                    DecorationListItem(
                      title: Text(code),
                      subtitle: Text(
                        appLocalizations.siteDomainCount(_sizes[code] ?? 0),
                      ),
                      trailing: _check(code == _category),
                      onPressed: () => setState(
                        () => _category = code == _category ? null : code,
                      ),
                    ),
                ],
              ),
            ],
            if (_domains.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: ListHeader(title: appLocalizations.siteLookupDomains),
              ),
              _SwitchList(
                items: [
                  for (final domain in _domains)
                    DecorationListItem(
                      title: Text(domain),
                      subtitle: sharedDomains.contains(domain)
                          ? Text(appLocalizations.siteLookupShared)
                          : null,
                      trailing: _check(_chosenDomains.contains(domain)),
                      onPressed: () => setState(
                        () => _chosenDomains.contains(domain)
                            ? _chosenDomains.remove(domain)
                            : _chosenDomains.add(domain),
                      ),
                    ),
                ],
              ),
            ],
            if (_programs.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: ListHeader(title: appLocalizations.siteLookupPrograms),
              ),
              _SwitchList(
                items: [
                  for (final program in _programs)
                    DecorationListItem(
                      leading: PackageIcon(
                        packageName: program.packageName,
                        size: _listIcon,
                      ),
                      title: Text(program.label),
                      subtitle: Text(program.packageName),
                      trailing: _check(
                        _chosenPrograms.contains(program.packageName),
                      ),
                      onPressed: () => setState(
                        () => _chosenPrograms.contains(program.packageName)
                            ? _chosenPrograms.remove(program.packageName)
                            : _chosenPrograms.add(program.packageName),
                      ),
                    ),
                ],
              ),
            ],
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                16,
                20,
                16,
                16 + context.bottomInset,
              ),
              sliver: SliverToBoxAdapter(
                child: TonalButton(
                  size: TonalButtonSize.bar,
                  glyph: AppGlyphs.chevronForward,
                  label: appLocalizations.siteLookupNext,
                  onPressed: ready ? _next : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
