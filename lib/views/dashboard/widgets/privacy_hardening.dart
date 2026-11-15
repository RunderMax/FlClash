import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/views/dashboard/layout.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'card.dart';

const _rowPadding = EdgeInsets.fromLTRB(10, 10, 12, 10);
const _rowIcon = 38.0;

class PrivacyHardeningCard extends ConsumerWidget {
  const PrivacyHardeningCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appLocalizations = context.appLocalizations;
    final mobile = !DashboardDensityScope.of(context).isDesktop;
    final allowBypass = ref.watch(
      vpnSettingProvider.select((state) => state.allowBypass),
    );
    void setBlockBypass(bool block) => ref
        .read(vpnSettingProvider.notifier)
        .update((state) => state.copyWith(allowBypass: !block));
    final (:blockQuic, :blockAds) = ref.watch(
      patchClashConfigProvider.select(
        (state) =>
            (blockQuic: state.slothBlockQuic, blockAds: state.slothBlockAds),
      ),
    );
    void setBlockQuic(bool value) => ref
        .read(patchClashConfigProvider.notifier)
        .update((state) => state.copyWith(slothBlockQuic: value));
    final secureWindow = ref.watch(
      appSettingProvider.select((state) => state.secureWindow),
    );
    void setSecureWindow(bool value) => ref
        .read(appSettingProvider.notifier)
        .update((state) => state.copyWith(secureWindow: value));
    void setBlockAds(bool value) => ref
        .read(patchClashConfigProvider.notifier)
        .update((state) => state.copyWith(slothBlockAds: value));
    final plugin = app;
    return DashboardCard(
      semanticLabel: appLocalizations.privacyHardening,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: mobile ? MainAxisSize.min : MainAxisSize.max,
        spacing: 8,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.verified,
            title: appLocalizations.privacyHardening,
          ),
          const SizedBox(height: 4),
          DashboardSwitchRow(
            glyph: AppGlyphs.vpn,
            title: appLocalizations.blockBypass,
            subtitle: appLocalizations.blockBypassDesc,
            value: !allowBypass,
            iconSize: _rowIcon,
            padding: _rowPadding,
            radius: AppCorner.md,
            onTap: () => setBlockBypass(allowBypass),
            onChanged: setBlockBypass,
          ),
          DashboardSwitchRow(
            glyph: AppGlyphs.block,
            title: appLocalizations.blockQuicStun,
            subtitle: appLocalizations.blockQuicStunDesc,
            value: blockQuic,
            iconSize: _rowIcon,
            padding: _rowPadding,
            radius: AppCorner.md,
            onTap: () => setBlockQuic(!blockQuic),
            onChanged: setBlockQuic,
          ),
          DashboardSwitchRow(
            glyph: AppGlyphs.broom,
            title: appLocalizations.blockAds,
            subtitle: appLocalizations.blockAdsDesc,
            value: blockAds,
            iconSize: _rowIcon,
            padding: _rowPadding,
            radius: AppCorner.md,
            onTap: () => setBlockAds(!blockAds),
            onChanged: setBlockAds,
          ),
          if (plugin != null)
            DashboardSwitchRow(
              glyph: AppGlyphs.eyeOff,
              title: appLocalizations.secureWindow,
              subtitle: appLocalizations.secureWindowDesc,
              value: secureWindow,
              iconSize: _rowIcon,
              padding: _rowPadding,
              radius: AppCorner.md,
              onTap: () => setSecureWindow(!secureWindow),
              onChanged: setSecureWindow,
            ),
          if (plugin != null)
            _LinkRow(
              title: appLocalizations.killSwitch,
              subtitle: appLocalizations.killSwitchDesc,
              onTap: plugin.openVpnSettings,
            ),
        ],
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    return DashboardBlock(
      radius: AppCorner.md,
      padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
      onTap: onTap,
      semanticLabel: title,
      child: Row(
        spacing: 10,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                Text(
                  title,
                  style: AppTextStyle.subheadline.of(context, emphasized: true),
                ),
                Text(
                  subtitle,
                  style: AppTextStyle.caption1
                      .of(context)
                      .copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          GlyphIcon(
            AppGlyphs.openExternal,
            size: 18,
            color: colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}
