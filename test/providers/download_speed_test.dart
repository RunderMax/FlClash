import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/providers/core.dart';
import 'package:fl_clash/providers/download_speed.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:riverpod/riverpod.dart';

class _MockCore extends Mock implements CoreHandlerInterface {}

void main() {
  late _MockCore core;
  late ProviderContainer container;

  setUp(() {
    core = _MockCore();
    container = ProviderContainer(
      overrides: [
        coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
      ],
    );
    addTearDown(container.dispose);
  });

  DownloadSpeedTest tester() =>
      container.read(downloadSpeedTestProvider.notifier);
  DownloadSpeeds speeds() => container.read(downloadSpeedTestProvider);

  test('tests the nodes in turn and keeps what each one reached', () async {
    final asked = <String>[];
    when(() => core.downloadSpeed(any())).thenAnswer((call) async {
      final name = call.positionalArguments.single as String;
      asked.add(name);
      expect(speeds().pending, contains(name));
      return name == 'HK'
          ? (rate: 4096, error: null)
          : (rate: null, error: 'failed');
    });

    expect(await tester().run(['HK', 'JP']), isTrue);

    expect(asked, ['HK', 'JP']);
    expect(speeds().rates, {'HK': 4096, 'JP': null});
    expect(speeds().busy, isFalse);
  });

  test('stops at once on a metered network', () async {
    when(
      () => core.downloadSpeed(any()),
    ).thenAnswer((_) async => (rate: null, error: downloadSpeedMetered));

    expect(await tester().run(['HK', 'JP']), isFalse);

    verify(() => core.downloadSpeed('HK')).called(1);
    verifyNever(() => core.downloadSpeed('JP'));
    expect(speeds().rates, isEmpty);
    expect(speeds().busy, isFalse);
  });

  test('a test that throws counts as failed and the rest go on', () async {
    when(() => core.downloadSpeed('HK')).thenThrow(StateError('gone'));
    when(
      () => core.downloadSpeed('JP'),
    ).thenAnswer((_) async => (rate: 10, error: null));

    expect(await tester().run(['HK', 'JP']), isTrue);

    expect(speeds().rates, {'HK': null, 'JP': 10});
  });
}
