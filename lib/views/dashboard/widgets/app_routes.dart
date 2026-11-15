import 'dart:async';

import 'package:fl_clash/common/app_exits.dart';
import 'package:fl_clash/common/app_routes.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:fl_clash/providers/app_exits.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/views/dashboard/layout.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'card.dart';
import 'fastest_nodes.dart';

const _cardRows = 4;
const _cardIcon = 32.0;
const _listIcon = 40.0;

String _targetLabel(BuildContext context, String target) {
  final appLocalizations = context.appLocalizations;
  return switch (target) {
    appRouteDirect => appLocalizations.direct,
    appRouteBlock => appLocalizations.appRouteBlock,
    slothPicksGroup => appLocalizations.fastestNodes,
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

bool _missing(String target, Set<String> reachable) =>
    target != appRouteDirect &&
    target != appRouteBlock &&
    reachable.isNotEmpty &&
    !reachable.contains(target);

Color _targetColor(BuildContext context, String target, bool missing) {
  final colorScheme = context.colorScheme;
  if (missing || target == appRouteBlock) {
    return colorScheme.error;
  }
  return target == appRouteDirect
      ? colorScheme.onSurfaceVariant
      : colorScheme.primary;
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
  @override
  void initState() {
    super.initState();
    final routed = ref.read(patchClashConfigProvider).slothAppRoutes;
    if (routed.isNotEmpty && ref.read(packagesProvider).isEmpty) {
      unawaited(
        ref
            .read(systemActionProvider.notifier)
            .getPackages()
            .catchError((Object _) => const <Package>[]),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final colorScheme = context.colorScheme;
    final mobile = !DashboardDensityScope.of(context).isDesktop;
    final routes = ref.watch(
      patchClashConfigProvider.select((state) => state.slothAppRoutes),
    );
    final labels = {
      for (final package in ref.watch(packagesProvider))
        package.packageName: package.label,
    };
    final reachable = _reachable(ref.watch(groupsProvider));
    final exits = ref.watch(appExitsProvider).value ?? const {};
    final shown = routes.entries.take(_cardRows).toList();
    final hidden = routes.length - shown.length;
    return DashboardCard(
      semanticLabel: appLocalizations.appRoutes,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: mobile ? MainAxisSize.min : MainAxisSize.max,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.appsList,
            title: appLocalizations.appRoutes,
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
            for (final MapEntry(key: packageName, value: target) in shown) ...[
              _RouteRow(
                packageName: packageName,
                label: labels[packageName] ?? packageName,
                target: target,
                missing: _missing(target, reachable),
                latest: exits[packageName]?.firstOrNull,
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

class _RouteRow extends StatelessWidget {
  const _RouteRow({
    required this.packageName,
    required this.label,
    required this.target,
    required this.missing,
    required this.latest,
  });

  final String packageName;
  final String label;
  final String target;
  final bool missing;
  final AppExit? latest;

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final color = _targetColor(context, target, missing);
    final targetLabel = _targetLabel(context, target);
    return DashboardBlock(
      radius: AppCorner.md,
      padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
      onTap: () => _showTargets(context, packageName, label),
      semanticLabel: [
        label,
        targetLabel,
        if (missing) appLocalizations.appRouteMissing,
      ].join(' '),
      child: Row(
        children: [
          PackageIcon(packageName: packageName, size: _cardIcon),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.subheadline.of(context, emphasized: true),
                ),
                if (latest case final latest?)
                  _ExitLine(
                    exit: latest,
                    style: AppTextStyle.caption1
                        .of(context)
                        .copyWith(color: context.colorScheme.onSurfaceVariant),
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
            child: Text(
              targetLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.footnote
                  .of(context, emphasized: true)
                  .copyWith(color: color),
            ),
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
    ...ref.read(patchClashConfigProvider).slothAppRoutes.keys,
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

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final packages = ref.watch(packagesProvider);
    final routes = ref.watch(
      patchClashConfigProvider.select((state) => state.slothAppRoutes),
    );
    final reachable = _reachable(ref.watch(groupsProvider));
    final query = SearchQuery(_query);
    final visible = _visible(packages, query);
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
              isLoading: !_loaded,
              holdsArrival: false,
              isEmpty: visible.isEmpty,
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
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        16,
                        0,
                        16,
                        16 + context.bottomInset,
                      ),
                      sliver: SliverPrismList(
                        itemCount: visible.length,
                        itemBuilder: (_, index) {
                          final package = visible[index];
                          final target = routes[package.packageName];
                          return ItemPositionProvider(
                            key: ValueKey(package.packageName),
                            position: ItemPosition.get(index, visible.length),
                            child: _AppItem(
                              package: package,
                              target: target,
                              missing:
                                  target != null && _missing(target, reachable),
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

class _AppItem extends StatelessWidget {
  const _AppItem({
    required this.package,
    required this.target,
    required this.missing,
  });

  final Package package;
  final String? target;
  final bool missing;

  @override
  Widget build(BuildContext context) {
    final target = this.target;
    return DecorationListItem(
      leading: PackageIcon(packageName: package.packageName, size: _listIcon),
      title: Text(package.label, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: target == null
          ? null
          : Text(
              _targetLabel(context, target),
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

  void _choose(String? target) {
    ref
        .read(patchClashConfigProvider.notifier)
        .update((state) => state.withAppRoute(widget.packageName, target));
    Navigator.of(context).pop();
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
    final current = ref.watch(
      patchClashConfigProvider.select(
        (state) => state.slothAppRoutes[widget.packageName],
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
                  if (query.isEmpty)
                    ..._section(
                      title: appLocalizations.appRouteTo,
                      choices: fixed,
                      current: current,
                    ),
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
