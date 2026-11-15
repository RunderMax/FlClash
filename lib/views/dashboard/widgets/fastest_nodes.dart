import 'package:collection/collection.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/views/dashboard/layout.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'card.dart';

const _builtInTypes = {
  'Direct',
  'Reject',
  'RejectDrop',
  'Pass',
  'Compatible',
  'Dns',
};

List<String> _fastestCandidates(List<Group> groups) {
  final groupNames = {for (final group in groups) group.name};
  return {
    for (final group in groups)
      for (final proxy in group.all)
        if (!groupNames.contains(proxy.name) &&
            !_builtInTypes.contains(proxy.type) &&
            proxy.name != slothFastestGroup)
          proxy.name,
  }.toList();
}

/// The select group the Core offered the fastest group in, first of the
/// profile's select groups.
Group? _fastestHostGroup(List<Group> groups) => groups.firstWhereOrNull(
  (group) =>
      group.type == GroupType.Selector &&
      group.all.any((proxy) => proxy.name == slothFastestGroup),
);

class FastestNodesCard extends ConsumerStatefulWidget {
  const FastestNodesCard({super.key});

  @override
  ConsumerState<FastestNodesCard> createState() => _FastestNodesCardState();
}

class _FastestNodesCardState extends ConsumerState<FastestNodesCard> {
  /// Switching on picks the group once the Core has built it; a later choice
  /// in the proxies page is the user's and stays.
  bool _selectPending = false;

  void _selectWhenReady(List<Group> groups) {
    final host = _fastestHostGroup(groups);
    if (!_selectPending || host == null) return;
    _selectPending = false;
    if (host.now != slothFastestGroup) {
      ref
          .read(proxiesActionProvider.notifier)
          .changeProxy(groupName: host.name, proxyName: slothFastestGroup);
    }
  }

  void _setEnabled(bool enabled) {
    _selectPending = enabled;
    ref
        .read(patchClashConfigProvider.notifier)
        .update((state) => state.copyWith(slothFastest: enabled));
    _selectWhenReady(ref.read(groupsProvider));
  }

  void _choose() {
    showSheet<void>(
      context: context,
      builder: (_) => _FastestNodesSheet(
        candidates: _fastestCandidates(ref.read(groupsProvider)),
        selected: ref.read(patchClashConfigProvider).slothFastestProxies,
        onConfirm: (proxies) => ref
            .read(patchClashConfigProvider.notifier)
            .update((state) => state.copyWith(slothFastestProxies: proxies)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(groupsProvider, (_, groups) => _selectWhenReady(groups));
    final appLocalizations = context.appLocalizations;
    final colorScheme = context.colorScheme;
    final mobile = !DashboardDensityScope.of(context).isDesktop;
    final (:enabled, :count) = ref.watch(
      patchClashConfigProvider.select(
        (state) => (
          enabled: state.slothFastest,
          count: state.slothFastestProxies.length,
        ),
      ),
    );
    final current = ref.watch(
      groupsProvider.select(
        (groups) =>
            groups.firstWhereOrNull((group) => group.name == slothFastestGroup),
      ),
    );
    final status = !enabled || count == 0
        ? appLocalizations.fastestNodesIdle
        : current == null
        ? appLocalizations.fastestNodesMissing
        : appLocalizations.fastestNodesCurrent(current.now ?? '-');
    return DashboardCard(
      semanticLabel: appLocalizations.fastestNodes,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: mobile ? MainAxisSize.min : MainAxisSize.max,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.bolt,
            title: appLocalizations.fastestNodes,
          ),
          const SizedBox(height: 12),
          Text(
            status,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyle.subheadline
                .of(context)
                .copyWith(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          DashboardSwitchRow(
            glyph: AppGlyphs.speed,
            title: appLocalizations.fastestNodesSwitch,
            subtitle: appLocalizations.fastestNodesCount(count),
            value: enabled && count > 0,
            iconSize: 38,
            padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
            radius: AppCorner.md,
            onTap: count == 0 ? _choose : () => _setEnabled(!enabled),
            onChanged: count == 0 ? null : _setEnabled,
          ),
          const SizedBox(height: 8),
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

class _FastestNodesSheet extends StatefulWidget {
  const _FastestNodesSheet({
    required this.candidates,
    required this.selected,
    required this.onConfirm,
  });

  final List<String> candidates;
  final List<String> selected;
  final ValueChanged<List<String>> onConfirm;

  @override
  State<_FastestNodesSheet> createState() => __FastestNodesSheetState();
}

class __FastestNodesSheetState extends State<_FastestNodesSheet> {
  late final _selected = {...widget.selected};

  void _toggle(String name) {
    setState(() => _selected.addOrRemove(name));
  }

  void _confirm() {
    Navigator.of(context).pop();
    widget.onConfirm([
      for (final name in widget.candidates)
        if (_selected.contains(name)) name,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final candidates = widget.candidates;
    return Scaffold(
      title: appLocalizations.fastestNodesChoose,
      confirmationAction: IconButtonData(
        glyph: AppGlyphs.check,
        onPressed: _confirm,
        tooltip: appLocalizations.confirm,
      ),
      body: candidates.isEmpty
          ? Center(
              child: Text(
                appLocalizations.fastestNodesEmpty,
                style: AppTextStyle.subheadline
                    .of(context)
                    .copyWith(color: context.colorScheme.onSurfaceVariant),
              ),
            )
          : PrismListView(
              padding: const EdgeInsets.symmetric(horizontal: 16).copyWith(
                top: context.contentTopPadding,
                bottom: 20 + context.bottomInset,
              ),
              itemCount: candidates.length,
              itemBuilder: (context, index) {
                final name = candidates[index];
                final isSelected = _selected.contains(name);
                return ItemPositionProvider(
                  position: ItemPosition.get(index, candidates.length),
                  child: DecorationListItem(
                    title: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    isSelected: isSelected,
                    trailing: isSelected ? const SelectionCheck() : null,
                    onPressed: () => _toggle(name),
                  ),
                );
              },
            ),
    );
  }
}
