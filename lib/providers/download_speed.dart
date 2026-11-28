import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'core.dart';

part 'generated/download_speed.g.dart';

const downloadSpeedMetered = 'metered';

/// Bytes a second each node last reached; null where its test failed.
@immutable
class DownloadSpeeds {
  const DownloadSpeeds({this.rates = const {}, this.pending = const {}});

  final Map<String, int?> rates;
  final Set<String> pending;

  bool get busy => pending.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      other is DownloadSpeeds &&
      mapEquals(other.rates, rates) &&
      setEquals(other.pending, pending);

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(rates.entries.map((e) => (e.key, e.value))),
    Object.hashAllUnordered(pending),
  );
}

@Riverpod(keepAlive: true)
class DownloadSpeedTest extends _$DownloadSpeedTest {
  @override
  DownloadSpeeds build() => const DownloadSpeeds();

  /// Tests [names] one after another, as two downloads at once would share the
  /// line. False when the Core refused because the network is metered.
  Future<bool> run(List<String> names) async {
    if (state.busy || names.isEmpty) return true;
    final core = ref.read(coreHandlerProvider);
    state = DownloadSpeeds(rates: state.rates, pending: names.toSet());
    try {
      for (final name in names) {
        int? rate;
        try {
          final result = await core.downloadSpeed(name);
          if (result.error == downloadSpeedMetered) return false;
          rate = result.rate;
        } catch (_) {
          rate = null;
        }
        state = DownloadSpeeds(
          rates: {...state.rates, name: rate},
          pending: {...state.pending}..remove(name),
        );
      }
      return true;
    } finally {
      state = DownloadSpeeds(rates: state.rates);
    }
  }
}
