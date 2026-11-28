import 'dart:async';

import 'package:collection/collection.dart';
import 'package:fl_clash/common/app_routes.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/features/ip_quality/labels.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/download_speed.dart';
import 'package:fl_clash/providers/ip_quality.dart';
import 'package:fl_clash/providers/outbound_ip.dart';
import 'package:fl_clash/providers/pick_routes.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/views/dashboard/layout.dart';
import 'package:fl_clash/views/dashboard/style.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'card.dart';
import 'in_use.dart';
import 'pick_history.dart';

const _builtInTypes = {
  'Direct',
  'Reject',
  'RejectDrop',
  'Pass',
  'Compatible',
  'Dns',
};

/// The nodes of the profile, leaving out its groups and the built-in outbounds.
List<String> nodeNamesOf(List<Group> groups) {
  final groupNames = {for (final group in groups) group.name};
  return {
    for (final group in groups)
      for (final proxy in group.all)
        if (!groupNames.contains(proxy.name) &&
            !_builtInTypes.contains(proxy.type))
          proxy.name,
  }.toList();
}

bool _offersPicks(Group group) =>
    group.type == GroupType.Selector &&
    !group.name.startsWith(appPicksGroupPrefix) &&
    group.all.any((proxy) => proxy.name == slothPicksGroup);

/// mihomo's own GLOBAL lists every group, the picks among them, yet traffic
/// enters it only in global mode.
bool _isBuiltInGlobal(Group group) =>
    group.name == GroupName.GLOBAL.name && group.hidden == true;

/// The select group the Core offered the picks group in.
Group? _hostGroup(List<Group> groups) => groups.firstWhereOrNull(
  (group) => !_isBuiltInGlobal(group) && _offersPicks(group),
);

/// The groups a pick is chosen in to carry traffic in [mode]: rules send it to
/// any select group, so each one leading to a proxy now is taken.
@visibleForTesting
List<Group> pickEntryGroups(
  List<Group> groups,
  Mode mode, [
  Map<String, String> selectedMap = const {},
]) {
  final host = _hostGroup(groups);
  final types = {
    for (final group in groups)
      for (final proxy in group.all) proxy.name: proxy.type,
  };
  bool proxied(Group group) {
    final type =
        types[computeRealSelectedProxyState(
          group.name,
          groups: groups,
          selectedMap: selectedMap,
        ).proxyName];
    return type != null && !_builtInTypes.contains(type);
  }

  return [
    for (final group in groups)
      if (_offersPicks(group) &&
          (mode == Mode.global || !_isBuiltInGlobal(group)) &&
          (group == host || _isBuiltInGlobal(group) || proxied(group)))
        group,
  ];
}

/// Where traffic enters the proxies before any request has shown it.
String? _entryOf(List<Group> groups, Mode mode) =>
    mode == Mode.global ? GroupName.GLOBAL.name : _hostGroup(groups)?.name;

/// The nodes traffic goes through now: what each group recent traffic entered
/// has chosen at present, so a switch shows at once, and nodes rules name
/// themselves. With no traffic seen yet, [entry] stands for it.
Set<String> _inUse(
  List<Group> groups,
  Map<String, String> selectedMap,
  PickRoutes routes,
  String? entry,
) {
  final starts = {
    for (final name in routes.groups)
      if (groups.getGroup(name) != null) name,
  };
  if (starts.isEmpty && routes.nodes.isEmpty && entry != null) {
    starts.add(entry);
  }
  return {
    ...routes.nodes,
    for (final group in starts)
      computeRealSelectedProxyState(
        group,
        groups: groups,
        selectedMap: selectedMap,
      ).proxyName,
  };
}

/// [picks] with [name] moved to the front, the rest standing by in their order.
List<String> mainFirst(List<String> picks, String name) => [
  if (picks.contains(name)) name,
  for (final pick in picks)
    if (pick != name) pick,
];

typedef _Pick = ({
  String name,
  int? delay,
  IpInfo? ip,
  IpQuality? quality,
  _Download download,
});

enum _DownloadState { untested, testing, failed, done }

typedef _Download = ({_DownloadState state, int rate});

_Download _downloadOf(DownloadSpeeds speeds, String name) {
  if (speeds.pending.contains(name)) {
    return (state: _DownloadState.testing, rate: speeds.rates[name] ?? 0);
  }
  if (!speeds.rates.containsKey(name)) {
    return (state: _DownloadState.untested, rate: 0);
  }
  final rate = speeds.rates[name];
  return rate == null
      ? (state: _DownloadState.failed, rate: 0)
      : (state: _DownloadState.done, rate: rate);
}

/// Timeouts and untested nodes go last, in that order.
int _delayRank(int? delay) => switch (delay) {
  null => 1 << 30,
  < 0 => 1 << 29,
  final delay => delay,
};

int _purityRank(IpQuality? quality) => switch (quality?.level) {
  IpQualityLevel.good => 0,
  IpQualityLevel.normal => 1,
  IpQualityLevel.risky => 2,
  null => 3,
};

int _byPurity(_Pick a, _Pick b) {
  final purity = _purityRank(a.quality).compareTo(_purityRank(b.quality));
  return purity != 0
      ? purity
      : _delayRank(a.delay).compareTo(_delayRank(b.delay));
}

List<_Pick> _sorted(List<_Pick> picks, PickSort sort) => switch (sort) {
  PickSort.custom => picks,
  PickSort.speed => picks.sortedBy<num>((pick) => _delayRank(pick.delay)),
  PickSort.purity => picks.sorted(_byPurity),
  PickSort.download => picks.sortedBy<num>((pick) => -pick.download.rate),
};

String _sortLabel(BuildContext context, PickSort sort) {
  final appLocalizations = context.appLocalizations;
  return switch (sort) {
    PickSort.custom => appLocalizations.pickSortCustom,
    PickSort.speed => appLocalizations.pickSortSpeed,
    PickSort.purity => appLocalizations.pickSortPurity,
    PickSort.download => appLocalizations.pickSortDownload,
  };
}

class FastestNodesCard extends ConsumerStatefulWidget {
  const FastestNodesCard({super.key});

  @override
  ConsumerState<FastestNodesCard> createState() => _FastestNodesCardState();
}

/// What a list of picks needs to show and test its nodes.
mixin _PickProbes<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  late final OutboundIpProbe _probe;
  final Set<String> _watched = {};

  @override
  void initState() {
    super.initState();
    _probe = ref.read(outboundIpProbeProvider.notifier);
  }

  @override
  void dispose() {
    _watched.forEach(_probe.unwatch);
    super.dispose();
  }

  /// The probe defers its state changes, so the rows may be watched from build.
  void _watchPicks(List<String> picks) {
    final next = picks.toSet();
    for (final name in _watched.difference(next)) {
      _probe.unwatch(name);
    }
    for (final name in next.difference(_watched)) {
      _probe.watch(name);
    }
    _watched
      ..clear()
      ..addAll(next);
  }

  void _test(List<String> picks) {
    final byName = {
      for (final group in ref.read(groupsProvider))
        for (final proxy in group.all) proxy.name: proxy,
    };
    ref.read(proxiesActionProvider.notifier).delayTest([
      ...picks.map((name) => byName[name]).nonNulls,
    ]);
    _probe.refresh(picks);
  }

  Future<void> _testDownload(List<String> picks) async {
    final allowed = await ref
        .read(downloadSpeedTestProvider.notifier)
        .run(picks);
    if (allowed || !mounted) return;
    await dialogs.showAlert(
      title: context.appLocalizations.picksDownloadTest,
      message: TextSpan(text: context.appLocalizations.picksDownloadWifiOnly),
    );
  }

  _Pick _pickOf(String name, DownloadSpeeds speeds) {
    final ip = ref.watch(
      outboundIpProbeProvider.select((state) => state.valueOf(name)),
    );
    return (
      name: name,
      delay: ref.watch(delayProvider(proxyName: name)),
      ip: ip,
      quality: ip == null ? null : ref.watch(ipQualityProvider(ip.ip)).value,
      download: _downloadOf(speeds, name),
    );
  }
}

class _FastestNodesCardState extends ConsumerState<FastestNodesCard>
    with _PickProbes {
  /// While the choice is automatic, a tap makes the node the main line.
  Future<void> _select(String name) async {
    final config = ref.read(patchClashConfigProvider);
    if (config.slothPickAuto) {
      ref
          .read(patchClashConfigProvider.notifier)
          .update(
            (state) =>
                state.copyWith(slothPicks: mainFirst(state.slothPicks, name)),
          );
      return;
    }
    final actions = ref.read(proxiesActionProvider.notifier);
    await actions.changeProxy(groupName: slothPicksGroup, proxyName: name);
    await _enterPicks();
  }

  Future<void> _enterPicks() async {
    final actions = ref.read(proxiesActionProvider.notifier);
    final selectedMap = ref.read(selectedMapProvider);
    final entries = pickEntryGroups(
      ref.read(groupsProvider),
      ref.read(patchClashConfigProvider).mode,
      selectedMap,
    );
    for (final group in entries) {
      final selected = group.getCurrentSelectedName(
        selectedMap[group.name] ?? '',
      );
      if (selected != slothPicksGroup) {
        await actions.changeProxy(
          groupName: group.name,
          proxyName: slothPicksGroup,
        );
      }
    }
    actions.updateGroupsDebounce();
  }

  void _setAuto(bool auto) {
    ref
        .read(patchClashConfigProvider.notifier)
        .update((state) => state.copyWith(slothPickAuto: auto));
    if (auto) unawaited(_enterPicks());
  }

  void _setSort(PickSort sort) {
    ref
        .read(appSettingProvider.notifier)
        .update((state) => state.copyWith(pickSort: sort));
  }

  void _showHistory(List<String> names) {
    showSheet<void>(
      context: context,
      builder: (_) => PickHistorySheet(names: names),
    );
  }

  void _choose() {
    showSheet<void>(
      context: context,
      builder: (_) => PicksSheet(
        candidates: nodeNamesOf(ref.read(groupsProvider)),
        picks: ref.read(patchClashConfigProvider).slothPicks,
        onConfirm: (picks) => ref
            .read(patchClashConfigProvider.notifier)
            .update((state) => state.copyWith(slothPicks: picks)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final colorScheme = context.colorScheme;
    final mobile = !DashboardDensityScope.of(context).isDesktop;
    final names = ref.watch(
      patchClashConfigProvider.select((state) => state.slothPicks),
    );
    final sort = ref.watch(
      appSettingProvider.select((state) => state.pickSort),
    );
    final auto = ref.watch(
      patchClashConfigProvider.select((state) => state.slothPickAuto),
    );
    final groups = ref.watch(groupsProvider);
    final mode = ref.watch(
      patchClashConfigProvider.select((state) => state.mode),
    );
    final inUse = _inUse(
      groups,
      ref.watch(selectedMapProvider),
      ref.watch(pickRoutesStateProvider),
      _entryOf(groups, mode),
    );
    _watchPicks(names);
    final speeds = ref.watch(downloadSpeedTestProvider);
    final picks = _sorted([
      for (final name in names) _pickOf(name, speeds),
    ], sort);
    return DashboardCard(
      semanticLabel: appLocalizations.fastestNodes,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: mobile ? MainAxisSize.min : MainAxisSize.max,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.bolt,
            title: appLocalizations.fastestNodes,
            trailing: [
              Transform.translate(
                offset: const Offset(8, 0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 8,
                  children: [
                    DashboardIconButton(
                      glyph: AppGlyphs.dataUsage,
                      tooltip: appLocalizations.pickHistory,
                      onPressed: names.isEmpty
                          ? null
                          : () => _showHistory([
                              for (final pick in picks) pick.name,
                            ]),
                    ),
                    DashboardIconButton(
                      glyph: AppGlyphs.cloudDownload,
                      tooltip: appLocalizations.picksDownloadTest,
                      onPressed: names.isEmpty || speeds.busy
                          ? null
                          : () => _testDownload(names),
                    ),
                    DashboardIconButton(
                      glyph: AppGlyphs.speed,
                      tooltip: appLocalizations.picksTest,
                      onPressed: names.isEmpty ? null : () => _test(names),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (picks.isEmpty)
            Text(
              appLocalizations.picksIdle,
              style: AppTextStyle.subheadline
                  .of(context)
                  .copyWith(color: colorScheme.onSurfaceVariant),
            )
          else ...[
            DashboardSwitchRow(
              glyph: AppGlyphs.swap,
              title: appLocalizations.autoSwitch,
              subtitle: appLocalizations.autoSwitchDesc,
              value: auto,
              iconSize: 38,
              padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
              radius: AppCorner.md,
              onTap: () => _setAuto(!auto),
              onChanged: _setAuto,
            ),
            const SizedBox(height: 8),
            DashboardConnectedGroup(
              children: [
                for (final (index, item) in PickSort.values.indexed)
                  Expanded(
                    child: DashboardConnectedButton(
                      selected: item == sort,
                      first: index == 0,
                      last: index == PickSort.values.length - 1,
                      outer: AppCorner.md,
                      inner: AppCorner.sm,
                      background: DashboardColors.of(context).tone,
                      semanticLabel: _sortLabel(context, item),
                      onTap: () => _setSort(item),
                      builder: (foreground) => SizedBox(
                        height: 36,
                        child: Center(
                          child: Text(
                            _sortLabel(context, item),
                            maxLines: 1,
                            style: AppTextStyle.footnote
                                .of(context, emphasized: true)
                                .copyWith(color: foreground),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            for (final pick in picks) ...[
              _PickTile(
                pick: pick,
                role: switch (auto ? names.indexOf(pick.name) : -1) {
                  < 0 => null,
                  0 => appLocalizations.pickRoleMain,
                  final index => appLocalizations.pickRoleBackup(index),
                },
                selected: inUse.contains(pick.name),
                onTap: () => _select(pick.name),
              ),
              const SizedBox(height: 6),
            ],
          ],
          const SizedBox(height: 6),
          DashboardBlock(
            radius: AppCorner.md,
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            onTap: _choose,
            semanticLabel: appLocalizations.fastestNodesChoose,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    appLocalizations.fastestNodesChoose,
                    style: AppTextStyle.subheadline.of(
                      context,
                      emphasized: true,
                    ),
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

String _rateLabel(int bytesPerSecond) {
  final show = bytesPerSecond.traffic;
  return '${show.value} ${show.unit}/s';
}

class _PickTile extends StatelessWidget {
  const _PickTile({
    required this.pick,
    required this.role,
    required this.selected,
    required this.onTap,
  });

  final _Pick pick;
  final String? role;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final appLocalizations = context.appLocalizations;
    final secondary = AppTextStyle.caption1
        .of(context)
        .copyWith(color: colorScheme.onSurfaceVariant);
    final delay = pick.delay;
    final ip = pick.ip;
    final quality = pick.quality;
    final duration = context.motionDuration(commonDuration);
    return InUseFrame(
      inUse: selected,
      radius: AppCorner.md,
      child: DashboardBlock(
        radius: AppCorner.md,
        padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
        onTap: onTap,
        semanticLabel: selected
            ? '${pick.name} ${appLocalizations.pickInUse}'
            : pick.name,
        child: Row(
          children: [
            InUseBadge(inUse: selected),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: [
                  AnimatedDefaultTextStyle(
                    duration: duration,
                    style: AppTextStyle.subheadline
                        .of(context, emphasized: true)
                        .copyWith(
                          color: selected
                              ? colorScheme.primary
                              : colorScheme.onSurface,
                        ),
                    child: Text(
                      pick.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (role case final role?)
                    Text(
                      role,
                      style: AppTextStyle.caption1
                          .of(context, emphasized: true)
                          .copyWith(color: colorScheme.primary),
                    ),
                  Text(
                    ip == null ? '-' : '${ip.ip} · ${ip.countryCode}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: secondary,
                  ),
                  if (quality != null)
                    Text(
                      [
                        quality.type.label(context),
                        [
                          appLocalizations.ipQualityShort,
                          quality.level.label(context),
                        ].join(' '),
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: secondary.copyWith(
                        color: quality.level.color(context),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              spacing: 2,
              children: [
                Text(
                  switch (delay) {
                    null => '-',
                    < 0 => appLocalizations.timeout,
                    final delay => '$delay ms',
                  },
                  style: AppTextStyle.footnote
                      .of(context, emphasized: true)
                      .toTabular
                      .copyWith(color: colorScheme.delayColor(delay)),
                ),
                if (pick.download.state != _DownloadState.untested)
                  Text(switch (pick.download.state) {
                    _DownloadState.testing =>
                      appLocalizations.picksDownloadTesting,
                    _DownloadState.failed =>
                      appLocalizations.picksDownloadFailed,
                    _ => _rateLabel(pick.download.rate),
                  }, style: secondary.toTabular),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// An app's own picks with what each one measures, on the app's sheet.
class AppPickNodes extends ConsumerStatefulWidget {
  const AppPickNodes({
    super.key,
    required this.names,
    required this.current,
    required this.auto,
    required this.onSelect,
  });

  final List<String> names;
  final String? current;
  final bool auto;
  final ValueChanged<String> onSelect;

  @override
  ConsumerState<AppPickNodes> createState() => _AppPickNodesState();
}

class _AppPickNodesState extends ConsumerState<AppPickNodes> with _PickProbes {
  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final names = widget.names;
    final speeds = ref.watch(downloadSpeedTestProvider);
    _watchPicks(names);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 6,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          spacing: 8,
          children: [
            DashboardIconButton(
              glyph: AppGlyphs.cloudDownload,
              tooltip: appLocalizations.picksDownloadTest,
              onPressed: speeds.busy ? null : () => _testDownload(names),
            ),
            DashboardIconButton(
              glyph: AppGlyphs.speed,
              tooltip: appLocalizations.picksTest,
              onPressed: () => _test(names),
            ),
          ],
        ),
        for (final (index, name) in names.indexed)
          _PickTile(
            pick: _pickOf(name, speeds),
            role: switch (index) {
              _ when !widget.auto => null,
              0 => appLocalizations.pickRoleMain,
              _ => appLocalizations.pickRoleBackup(index),
            },
            selected: name == widget.current,
            onTap: () => widget.onSelect(name),
          ),
      ],
    );
  }
}

class PicksSheet extends StatefulWidget {
  const PicksSheet({
    super.key,
    required this.candidates,
    required this.picks,
    required this.onConfirm,
  });

  final List<String> candidates;
  final List<String> picks;
  final ValueChanged<List<String>> onConfirm;

  @override
  State<PicksSheet> createState() => _PicksSheetState();
}

class _PicksSheetState extends State<PicksSheet> {
  late final _checked = {...widget.picks};

  /// Picks first, in their order, so dragging sets the custom order.
  late List<String> _order = [
    ...widget.picks.where(widget.candidates.contains),
    ...widget.candidates.where((name) => !widget.picks.contains(name)),
  ];

  void _toggle(String name) {
    setState(() => _checked.addOrRemove(name));
  }

  void _confirm() {
    Navigator.of(context).pop();
    widget.onConfirm([..._order.where(_checked.contains)]);
  }

  Widget _buildItem(int index) {
    final name = _order[index];
    final isSelected = _checked.contains(name);
    return SortableItem(
      key: ValueKey(name),
      index: index,
      child: ItemPositionProvider(
        position: ItemPosition.get(index, _order.length),
        child: DecorationListItem(
          title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
          isSelected: isSelected,
          trailing: isSelected ? const SelectionCheck() : null,
          onPressed: () => _toggle(name),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    return Scaffold(
      canSort: _order.length > 1,
      title: appLocalizations.fastestNodesChoose,
      confirmationAction: IconButtonData(
        glyph: AppGlyphs.check,
        onPressed: _confirm,
        tooltip: appLocalizations.confirm,
      ),
      body: _order.isEmpty
          ? Center(
              child: Text(
                appLocalizations.fastestNodesEmpty,
                style: AppTextStyle.subheadline
                    .of(context)
                    .copyWith(color: context.colorScheme.onSurfaceVariant),
              ),
            )
          : PrismReorderableListView(
              padding: const EdgeInsets.symmetric(horizontal: 16).copyWith(
                top: context.contentTopPadding,
                bottom: 20 + context.bottomInset,
              ),
              itemCount: _order.length,
              itemBuilder: (_, index) => _buildItem(index),
              proxyDecorator: (_, index, animation) =>
                  commonProxyDecorator(_buildItem(index), index, animation),
              onReorderItem: (oldIndex, newIndex) {
                setState(() {
                  _order = _order.copyAndReorder(oldIndex, newIndex);
                });
              },
            ),
    );
  }
}
