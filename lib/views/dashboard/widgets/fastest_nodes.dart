import 'package:collection/collection.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/features/ip_quality/labels.dart';
import 'package:fl_clash/models/models.dart';
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
import 'pick_history.dart';

const _builtInTypes = {
  'Direct',
  'Reject',
  'RejectDrop',
  'Pass',
  'Compatible',
  'Dns',
};

List<String> _candidates(List<Group> groups) {
  final groupNames = {for (final group in groups) group.name};
  return {
    for (final group in groups)
      for (final proxy in group.all)
        if (!groupNames.contains(proxy.name) &&
            !_builtInTypes.contains(proxy.type))
          proxy.name,
  }.toList();
}

/// The select group the Core offered the picks group in.
Group? _hostGroup(List<Group> groups) => groups.firstWhereOrNull(
  (group) =>
      group.type == GroupType.Selector &&
      group.all.any((proxy) => proxy.name == slothPicksGroup),
);

/// The nodes traffic goes through now: what each group recent traffic entered
/// has chosen at present, so a switch shows at once, and nodes rules name
/// themselves. With no traffic seen yet, the group the picks are offered in
/// stands for it.
Set<String> _inUse(
  List<Group> groups,
  Map<String, String> selectedMap,
  PickRoutes routes,
  String? host,
) {
  final starts = {
    for (final name in routes.groups)
      if (groups.getGroup(name) != null) name,
  };
  if (starts.isEmpty && routes.nodes.isEmpty && host != null) {
    starts.add(host);
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

typedef _Pick = ({String name, int? delay, IpInfo? ip, IpQuality? quality});

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
};

String _sortLabel(BuildContext context, PickSort sort) {
  final appLocalizations = context.appLocalizations;
  return switch (sort) {
    PickSort.custom => appLocalizations.pickSortCustom,
    PickSort.speed => appLocalizations.pickSortSpeed,
    PickSort.purity => appLocalizations.pickSortPurity,
  };
}

class FastestNodesCard extends ConsumerStatefulWidget {
  const FastestNodesCard({super.key});

  @override
  ConsumerState<FastestNodesCard> createState() => _FastestNodesCardState();
}

class _FastestNodesCardState extends ConsumerState<FastestNodesCard> {
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

  Future<void> _select(String name) async {
    final actions = ref.read(proxiesActionProvider.notifier);
    await actions.changeProxy(groupName: slothPicksGroup, proxyName: name);
    final host = _hostGroup(ref.read(groupsProvider));
    if (host != null && host.now != slothPicksGroup) {
      await actions.changeProxy(
        groupName: host.name,
        proxyName: slothPicksGroup,
      );
    }
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
      builder: (_) => _PicksSheet(
        candidates: _candidates(ref.read(groupsProvider)),
        picks: ref.read(patchClashConfigProvider).slothPicks,
        onConfirm: (picks) => ref
            .read(patchClashConfigProvider.notifier)
            .update((state) => state.copyWith(slothPicks: picks)),
      ),
    );
  }

  _Pick _pickOf(String name) {
    final ip = ref.watch(
      outboundIpProbeProvider.select((state) => state.valueOf(name)),
    );
    return (
      name: name,
      delay: ref.watch(delayProvider(proxyName: name)),
      ip: ip,
      quality: ip == null ? null : ref.watch(ipQualityProvider(ip.ip)).value,
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
    final groups = ref.watch(groupsProvider);
    final inUse = _inUse(
      groups,
      ref.watch(selectedMapProvider),
      ref.watch(pickRoutesStateProvider),
      _hostGroup(groups)?.name,
    );
    _watchPicks(names);
    final picks = _sorted([for (final name in names) _pickOf(name)], sort);
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
              DashboardIconButton(
                glyph: AppGlyphs.dataUsage,
                tooltip: appLocalizations.pickHistory,
                onPressed: names.isEmpty
                    ? null
                    : () => _showHistory([for (final pick in picks) pick.name]),
              ),
              Transform.translate(
                offset: const Offset(8, 0),
                child: DashboardIconButton(
                  glyph: AppGlyphs.speed,
                  tooltip: appLocalizations.picksTest,
                  onPressed: names.isEmpty ? null : () => _test(names),
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

class _PickTile extends StatelessWidget {
  const _PickTile({
    required this.pick,
    required this.selected,
    required this.onTap,
  });

  final _Pick pick;
  final bool selected;
  final VoidCallback onTap;

  static const _mark = 26.0;
  static const _border = 1.5;

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
    final shape = AppShape.all(AppCorner.md);
    // The mark and the frame both say which pick carries traffic, so a
    // glance finds it without reading.
    return TweenAnimationBuilder<double>(
      tween: Tween(end: selected ? 1 : 0),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, emphasis, child) => DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: ShapeDecoration(
          shape: shape.copyWith(
            side: BorderSide(
              color: colorScheme.primary.withValues(alpha: emphasis),
              width: _border,
            ),
          ),
        ),
        child: child,
      ),
      child: DashboardBlock(
        radius: AppCorner.md,
        padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
        onTap: onTap,
        semanticLabel: selected
            ? '${pick.name} ${appLocalizations.pickInUse}'
            : pick.name,
        child: Row(
          children: [
            AnimatedSize(
              duration: duration,
              curve: Curves.easeOutCubic,
              alignment: AlignmentDirectional.centerStart,
              child: AnimatedSwitcher(
                duration: duration,
                transitionBuilder: (child, animation) =>
                    ScaleTransition(scale: animation, child: child),
                child: selected
                    ? const Padding(
                        key: ValueKey(true),
                        padding: EdgeInsetsDirectional.only(end: 10),
                        child: SelectionBadge(size: _mark),
                      )
                    : const SizedBox.shrink(key: ValueKey(false)),
              ),
            ),
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
          ],
        ),
      ),
    );
  }
}

class _PicksSheet extends StatefulWidget {
  const _PicksSheet({
    required this.candidates,
    required this.picks,
    required this.onConfirm,
  });

  final List<String> candidates;
  final List<String> picks;
  final ValueChanged<List<String>> onConfirm;

  @override
  State<_PicksSheet> createState() => _PicksSheetState();
}

class _PicksSheetState extends State<_PicksSheet> {
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
