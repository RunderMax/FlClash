import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/pick_history.dart';
import 'package:fl_clash/views/dashboard/style.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' show join;

import 'card.dart';

enum _Range { day, week }

const _week = Duration(days: 7);

extension on _Range {
  Duration get span => switch (this) {
    _Range.day => const Duration(days: 1),
    _Range.week => _week,
  };
}

String _stabilityLabel(BuildContext context, PickStability stability) {
  final appLocalizations = context.appLocalizations;
  return switch (stability) {
    PickStability.stable => appLocalizations.pickStable,
    PickStability.fair => appLocalizations.pickFair,
    PickStability.unstable => appLocalizations.pickUnstable,
    PickStability.unknown => appLocalizations.pickNotEnough,
  };
}

DashboardChipTone _stabilityTone(PickStability stability) =>
    switch (stability) {
      PickStability.stable => DashboardChipTone.ok,
      PickStability.unstable => DashboardChipTone.warn,
      PickStability.fair || PickStability.unknown => DashboardChipTone.idle,
    };

class PickHistorySheet extends StatefulWidget {
  const PickHistorySheet({super.key, required this.names});

  final List<String> names;

  @override
  State<PickHistorySheet> createState() => _PickHistorySheetState();
}

class _PickHistorySheetState extends State<PickHistorySheet> {
  _Range _range = _Range.day;
  Map<String, List<PickSample>>? _history;
  late final int _now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final path = join(await appPath.homeDirPath, pickHistoryFile);
    final history = await loadPickHistory(path, _now - _week.inSeconds);
    if (mounted) setState(() => _history = history);
  }

  List<PickSample> _samplesOf(String name) {
    final since = _now - _range.span.inSeconds;
    return [
      for (final sample in _history?[name] ?? const <PickSample>[])
        if (sample.time >= since) sample,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final history = _history;
    final names = widget.names;
    return Scaffold(
      title: appLocalizations.pickHistory,
      body: history == null
          ? const Center(child: ActivityIndicator())
          : PrismListView(
              padding: const EdgeInsets.symmetric(horizontal: 16).copyWith(
                top: context.contentTopPadding,
                bottom: 20 + context.bottomInset,
              ),
              itemCount: names.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 8,
                      children: [
                        _RangePicker(
                          range: _range,
                          onChanged: (range) => setState(() => _range = range),
                        ),
                        if (history.isEmpty)
                          Text(
                            appLocalizations.pickHistoryEmpty,
                            style: AppTextStyle.footnote
                                .of(context)
                                .copyWith(
                                  color: context.colorScheme.onSurfaceVariant,
                                ),
                          ),
                      ],
                    ),
                  );
                }
                final name = names[index - 1];
                return ItemPositionProvider(
                  position: ItemPosition.get(index - 1, names.length),
                  child: _HistoryTile(
                    name: name,
                    samples: _samplesOf(name),
                    since: _now - _range.span.inSeconds,
                    until: _now,
                  ),
                );
              },
            ),
    );
  }
}

class _RangePicker extends StatelessWidget {
  const _RangePicker({required this.range, required this.onChanged});

  final _Range range;
  final ValueChanged<_Range> onChanged;

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    String label(_Range item) => switch (item) {
      _Range.day => appLocalizations.pickHistoryDay,
      _Range.week => appLocalizations.pickHistoryWeek,
    };
    return DashboardConnectedGroup(
      children: [
        for (final (index, item) in _Range.values.indexed)
          Expanded(
            child: DashboardConnectedButton(
              selected: item == range,
              first: index == 0,
              last: index == _Range.values.length - 1,
              outer: AppCorner.md,
              inner: AppCorner.sm,
              background: DashboardColors.of(context).tone,
              semanticLabel: label(item),
              onTap: () => onChanged(item),
              builder: (foreground) => SizedBox(
                height: 36,
                child: Center(
                  child: Text(
                    label(item),
                    style: AppTextStyle.footnote
                        .of(context, emphasized: true)
                        .copyWith(color: foreground),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({
    required this.name,
    required this.samples,
    required this.since,
    required this.until,
  });

  final String name;
  final List<PickSample> samples;
  final int since;
  final int until;

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final colorScheme = context.colorScheme;
    final stats = pickStats(samples);
    final average = stats.average;
    final jitter = stats.jitter;
    return DecorationListItem(
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: DashboardChip(
        label: _stabilityLabel(context, stats.stability),
        tone: _stabilityTone(stats.stability),
        dot: true,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          Text(
            appLocalizations.pickHistoryStats(
              average == null ? '-' : average.round().toString(),
              stats.timeouts,
              jitter == null ? '-' : jitter.round().toString(),
            ),
            style: AppTextStyle.caption1
                .of(context)
                .toTabular
                .copyWith(color: colorScheme.onSurfaceVariant),
          ),
          SizedBox(
            height: 64,
            child: CustomPaint(
              painter: _HistoryChartPainter(
                samples: samples,
                since: since,
                until: until,
                line: colorScheme.primary,
                timeout: colorScheme.error,
                grid: colorScheme.outlineVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Delays over time, broken where tests are missing, with timeouts as ticks
/// along the bottom.
class _HistoryChartPainter extends CustomPainter {
  _HistoryChartPainter({
    required this.samples,
    required this.since,
    required this.until,
    required this.line,
    required this.timeout,
    required this.grid,
  });

  final List<PickSample> samples;
  final int since;
  final int until;
  final Color line;
  final Color timeout;
  final Color grid;

  static final _gap = pickHistoryInterval.inSeconds * 2;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, size.height),
      Paint()
        ..color = grid
        ..strokeWidth = 1,
    );
    if (samples.isEmpty || until <= since) return;
    final top = samples.fold<int>(0, (top, sample) {
      return sample.delay > top ? sample.delay : top;
    });
    final scale = top <= 0 ? 1.0 : top * 1.1;
    double x(int time) => (time - since) / (until - since) * size.width;
    double y(int delay) => size.height - delay / scale * (size.height - 4);
    final path = Path();
    PickSample? previous;
    for (final sample in samples) {
      if (!sample.ok) {
        previous = null;
        continue;
      }
      final point = Offset(x(sample.time), y(sample.delay));
      if (previous == null || sample.time - previous.time > _gap) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
      previous = sample;
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeJoin = StrokeJoin.round,
    );
    final tick = Paint()
      ..color = timeout
      ..strokeWidth = 2;
    for (final sample in samples) {
      if (sample.ok) continue;
      final dx = x(sample.time);
      canvas.drawLine(
        Offset(dx, size.height),
        Offset(dx, size.height - 8),
        tick,
      );
    }
  }

  @override
  bool shouldRepaint(_HistoryChartPainter oldDelegate) =>
      oldDelegate.samples != samples ||
      oldDelegate.since != since ||
      oldDelegate.until != until ||
      oldDelegate.line != line ||
      oldDelegate.timeout != timeout ||
      oldDelegate.grid != grid;
}
