import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

/// Written by the Core next to the app's own data, one JSON sample a line.
const pickHistoryFile = 'sloth-history.jsonl';

/// The Core tests the picks this often, and only on a free network, so a
/// record costs next to no battery or data.
const pickHistoryInterval = Duration(hours: 3);

enum PickStability { stable, fair, unstable, unknown }

class PickSample {
  const PickSample({required this.time, required this.delay});

  /// Seconds since the epoch.
  final int time;

  /// Zero for a test that timed out.
  final int delay;

  bool get ok => delay > 0;
}

class PickStats {
  const PickStats({
    required this.samples,
    required this.timeouts,
    required this.average,
    required this.jitter,
    required this.stability,
  });

  final int samples;
  final int timeouts;
  final double? average;

  /// The mean change between neighbouring delays, which a steady node keeps
  /// small whatever its average.
  final double? jitter;
  final PickStability stability;

  double get timeoutRate => samples == 0 ? 0 : timeouts / samples;
}

const _minSamples = 6;

PickStats pickStats(List<PickSample> samples) {
  final delays = [
    for (final sample in samples)
      if (sample.ok) sample.delay,
  ];
  final timeouts = samples.length - delays.length;
  final average = delays.isEmpty
      ? null
      : delays.reduce((a, b) => a + b) / delays.length;
  double? jitter;
  if (delays.length > 1) {
    var change = 0;
    for (var i = 1; i < delays.length; i++) {
      change += (delays[i] - delays[i - 1]).abs();
    }
    jitter = change / (delays.length - 1);
  }
  return PickStats(
    samples: samples.length,
    timeouts: timeouts,
    average: average,
    jitter: jitter,
    stability: _stability(samples.length, timeouts, average, jitter),
  );
}

PickStability _stability(
  int samples,
  int timeouts,
  double? average,
  double? jitter,
) {
  if (samples < _minSamples) return PickStability.unknown;
  final timeoutRate = timeouts / samples;
  if (average == null || timeoutRate > 0.1) return PickStability.unstable;
  final swing = jitter ?? 0;
  if (swing > max(100, average * 0.5)) return PickStability.unstable;
  if (timeoutRate <= 0.02 && swing <= max(30, average * 0.2)) {
    return PickStability.stable;
  }
  return PickStability.fair;
}

/// Samples per node from [since] on, oldest first; a line that does not parse
/// is one the Core was still writing.
Map<String, List<PickSample>> parsePickHistory(String content, int since) {
  final history = <String, List<PickSample>>{};
  for (final line in const LineSplitter().convert(content)) {
    if (line.isEmpty) continue;
    final Object? json;
    try {
      json = jsonDecode(line);
    } on FormatException {
      continue;
    }
    if (json case {
      't': final int time,
      'n': final String name,
      'd': final int delay,
    } when time >= since) {
      (history[name] ??= []).add(PickSample(time: time, delay: delay));
    }
  }
  for (final samples in history.values) {
    samples.sort((a, b) => a.time.compareTo(b.time));
  }
  return history;
}

Future<Map<String, List<PickSample>>> loadPickHistory(String path, int since) =>
    Isolate.run(() async {
      final file = File(path);
      if (!await file.exists()) return const {};
      return parsePickHistory(await file.readAsString(), since);
    });
