import 'package:fl_clash/common/pick_history.dart';
import 'package:flutter_test/flutter_test.dart';

List<PickSample> _samples(List<int> delays) => [
  for (final (index, delay) in delays.indexed)
    PickSample(time: index * 300, delay: delay),
];

void main() {
  test('reads samples per node from a time on, skipping a torn line', () {
    const content =
        '{"t":100,"n":"a","d":90}\n'
        '{"t":400,"n":"a","d":0}\n'
        '{"t":400,"n":"b","d":120}\n'
        '{"t":700,"n":"a","d":';
    final history = parsePickHistory(content, 300);

    expect(history.keys, unorderedEquals(['a', 'b']));
    expect(history['a']!.single.delay, 0);
    expect(history['b']!.single.time, 400);
  });

  test('a steady node with no timeouts is stable', () {
    final stats = pickStats(_samples([100, 104, 98, 101, 103, 99, 100]));

    expect(stats.stability, PickStability.stable);
    expect(stats.timeouts, 0);
    expect(stats.average, closeTo(100.7, 0.1));
  });

  test('frequent timeouts or wild swings make a node unstable', () {
    expect(
      pickStats(_samples([100, 0, 100, 0, 100, 100, 100])).stability,
      PickStability.unstable,
    );
    expect(
      pickStats(_samples([80, 400, 90, 500, 70, 450, 85])).stability,
      PickStability.unstable,
    );
  });

  test('too few samples say nothing yet', () {
    expect(pickStats(_samples([100, 100])).stability, PickStability.unknown);
  });
}
