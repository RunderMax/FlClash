import 'package:fl_clash/common/print.dart';
import 'package:fl_clash/common/privacy_check.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'generated/privacy_check.g.dart';

enum PrivacyCheckPhase { idle, running, done, failed }

class PrivacyCheckState {
  const PrivacyCheckState({this.phase = PrivacyCheckPhase.idle, this.report});

  final PrivacyCheckPhase phase;
  final PrivacyReport? report;
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
      final report = await runPrivacyCheck();
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

  void reset() {
    _run++;
    state = const PrivacyCheckState();
  }
}
