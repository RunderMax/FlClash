import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/dns_guard.dart';
import 'package:fl_clash/common/privacy_check.dart';
import 'package:fl_clash/providers/privacy_check.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/views/dashboard/layout.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'card.dart';

class PrivacyCheckCard extends ConsumerStatefulWidget {
  const PrivacyCheckCard({super.key});

  @override
  ConsumerState<PrivacyCheckCard> createState() => _PrivacyCheckCardState();
}

class _PrivacyCheckCardState extends ConsumerState<PrivacyCheckCard> {
  Timer? _recheck;

  bool get _connected =>
      ref.read(isStartProvider) && !ref.read(suspendProvider);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_connected) return;
      if (ref.read(privacyCheckProvider).phase == PrivacyCheckPhase.idle) {
        ref.read(privacyCheckProvider.notifier).run();
      }
    });
  }

  @override
  void dispose() {
    _recheck?.cancel();
    super.dispose();
  }

  /// The core takes a moment to load the new DNS before a check can see it.
  void _setDnsGuard(bool enabled) {
    ref
        .read(patchClashConfigProvider.notifier)
        .update((state) => state.withDnsGuard(enabled));
    _recheck?.cancel();
    _recheck = Timer(const Duration(seconds: 3), () {
      if (mounted && _connected) {
        ref.read(privacyCheckProvider.notifier).run();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(isStartProvider, (_, started) {
      if (!started) ref.read(privacyCheckProvider.notifier).reset();
    });
    final appLocalizations = context.appLocalizations;
    final mobile = !DashboardDensityScope.of(context).isDesktop;
    final check = ref.watch(privacyCheckProvider);
    final connected = ref.watch(isStartProvider) && !ref.watch(suspendProvider);
    final dnsGuard = ref.watch(
      patchClashConfigProvider.select((state) => state.dnsGuard),
    );
    final running = check.phase == PrivacyCheckPhase.running;
    final report = check.report;
    final hint = !connected
        ? appLocalizations.privacyCheckNeedsVpn
        : running
        ? appLocalizations.loading
        : check.phase == PrivacyCheckPhase.failed
        ? appLocalizations.privacyCheckFailed
        : appLocalizations.privacyCheckIdle;
    return DashboardCard(
      semanticLabel: appLocalizations.privacyCheck,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: mobile ? MainAxisSize.min : MainAxisSize.max,
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.lock,
            title: appLocalizations.privacyCheck,
            trailing: [
              Transform.translate(
                offset: const Offset(8, 0),
                child: DashboardIconButton(
                  glyph: AppGlyphs.refresh,
                  tooltip: appLocalizations.runCheck,
                  onPressed: connected && !running
                      ? ref.read(privacyCheckProvider.notifier).run
                      : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (report == null || !connected)
            _Hint(hint)
          else ...[
            _LeakRow(
              title: appLocalizations.dnsLeak,
              verdict: report.dns.verdict,
              unreachableLabel: appLocalizations.checkNoResult,
              running: running,
              detail: _dnsDetail(context, report.dns),
            ),
            const SizedBox(height: 8),
            _LeakRow(
              title: appLocalizations.webrtcLeak,
              verdict: report.webRtc.verdict,
              unreachableLabel: appLocalizations.udpUnreachable,
              running: running,
              detail: _webRtcDetail(context, report.webRtc),
            ),
          ],
          const SizedBox(height: 8),
          DashboardSwitchRow(
            glyph: AppGlyphs.dns,
            title: appLocalizations.dnsGuard,
            subtitle: dnsGuard
                ? appLocalizations.dnsGuardOnDesc
                : appLocalizations.dnsGuardOffDesc,
            value: dnsGuard,
            iconSize: 38,
            padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
            radius: AppCorner.md,
            onTap: () => _setDnsGuard(!dnsGuard),
            onChanged: _setDnsGuard,
          ),
        ],
      ),
    );
  }
}

String _dnsDetail(BuildContext context, DnsCheck dns) {
  final appLocalizations = context.appLocalizations;
  final places = {
    for (final resolver in dns.resolvers)
      resolver.label.isEmpty ? resolver.ip : resolver.label,
  };
  return [
    [
      dns.fakeIp ? 'Fake-IP' : appLocalizations.dnsRealIp,
      appLocalizations.dnsResolverCount(dns.resolvers.length),
    ].join(' · '),
    if (places.isNotEmpty) places.take(3).join('\n'),
  ].join('\n');
}

String _webRtcDetail(BuildContext context, WebRtcCheck webRtc) {
  final mapped = webRtc.mapped;
  if (mapped == null) return '-';
  return [mapped.ip, if (mapped.label.isNotEmpty) mapped.label].join('\n');
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTextStyle.subheadline
          .of(context)
          .copyWith(color: context.colorScheme.onSurfaceVariant),
    );
  }
}

class _LeakRow extends StatelessWidget {
  const _LeakRow({
    required this.title,
    required this.verdict,
    required this.unreachableLabel,
    required this.running,
    required this.detail,
  });

  final String title;
  final LeakVerdict verdict;
  final String unreachableLabel;
  final bool running;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final (label, tone) = running
        ? (appLocalizations.loading, DashboardChipTone.idle)
        : switch (verdict) {
            LeakVerdict.safe => (
              appLocalizations.leakSafe,
              DashboardChipTone.ok,
            ),
            LeakVerdict.possibleLeak => (
              appLocalizations.leakPossible,
              DashboardChipTone.warn,
            ),
            LeakVerdict.unreachable => (
              unreachableLabel,
              DashboardChipTone.idle,
            ),
          };
    return DashboardBlock(
      radius: AppCorner.md,
      padding: const EdgeInsets.fromLTRB(14, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 6,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.subheadline.of(context, emphasized: true),
                ),
              ),
              DashboardChip(label: label, tone: tone, dot: true),
            ],
          ),
          Text(
            detail,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyle.caption1
                .of(context)
                .copyWith(color: context.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
