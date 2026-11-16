import 'package:fl_clash/common/http.dart';
import 'package:fl_clash/common/print.dart';
import 'package:fl_clash/common/privacy_check.dart';
import 'package:fl_clash/common/service_probe.dart';
import 'package:fl_clash/common/system.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'app.dart';
import 'config.dart';
import 'core.dart';

part 'generated/privacy_check.g.dart';

enum PrivacyCheckPhase { idle, running, done, failed }

class PrivacyCheckState {
  const PrivacyCheckState({this.phase = PrivacyCheckPhase.idle, this.report});

  final PrivacyCheckPhase phase;
  final PrivacyReport? report;
}

/// Android's VPN takes this app's sockets too; a desktop only while TUN runs.
@riverpod
bool capturesAppSockets(Ref ref) {
  if (!system.isDesktop) return true;
  final tun = ref.watch(
    patchClashConfigProvider.select((state) => state.tun.enable),
  );
  return tun &&
      ref.watch(authorizedTunEnableProvider) ==
          TunAuthorizationState.authorized;
}

@Riverpod(keepAlive: true)
class PrivacyCheck extends _$PrivacyCheck {
  int _run = 0;

  @override
  PrivacyCheckState build() => const PrivacyCheckState();

  Future<void> run() async {
    if (state.phase == PrivacyCheckPhase.running) return;
    final run = ++_run;
    state = PrivacyCheckState(
      phase: PrivacyCheckPhase.running,
      report: state.report,
    );
    try {
      final report = await runPrivacyCheck(
        realIp: await _realIp(),
        findProxy: ref.read(capturesAppSocketsProvider)
            ? null
            : (url) => FlClashHttpOverrides.findProxyForReader(ref.read, url),
      );
      if (run != _run) return;
      state = PrivacyCheckState(phase: PrivacyCheckPhase.done, report: report);
    } on Object catch (error) {
      commonPrint.log(
        'Privacy check failed: $error',
        logLevel: LogLevel.warning,
      );
      if (run != _run) return;
      state = PrivacyCheckState(
        phase: PrivacyCheckPhase.failed,
        report: state.report,
      );
    }
  }

  Future<String?> _realIp() async {
    try {
      final result = await lookupOutboundIp(
        ref.read(coreHandlerProvider),
        directOutbound,
      );
      return parseOutboundIp(result)?.ip;
    } on Object catch (error) {
      commonPrint.log(
        'Direct IP lookup failed: $error',
        logLevel: LogLevel.warning,
      );
      return null;
    }
  }

  void reset() {
    _run++;
    state = const PrivacyCheckState();
  }
}
