import 'package:fl_clash/common/app_exits.dart';
import 'package:fl_clash/common/app_routes.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/app_exits.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/dashboard/layout.dart';
import 'package:fl_clash/views/dashboard/widgets/app_routes.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:prism_ui/prism_ui.dart';

import '../../helpers/host_scaffold.dart';
import '../../helpers/test_app.dart';

Package _package(String name, String label) => Package(
  packageName: name,
  label: label,
  system: false,
  internet: true,
  lastUpdateTime: 0,
  launchable: true,
);

final _packages = [
  _package('com.example.video', 'Video'),
  _package('com.example.chat', 'Chat'),
  _package('com.example.web', 'Web'),
  _package('com.example.mail', 'Mail'),
  _package('com.example.maps', 'Maps'),
];

const _groups = [
  Group(
    type: GroupType.Selector,
    name: 'Media',
    hidden: false,
    now: 'JP-01',
    all: [
      Proxy(name: 'JP-01', type: 'ss'),
      Proxy(name: 'US-01', type: 'ss'),
    ],
  ),
];

class _MockCore extends Mock implements CoreHandlerInterface {}

class _Exits extends AppExits {
  _Exits(this.exits);

  final Map<String, List<AppExit>> exits;

  @override
  Future<Map<String, List<AppExit>>> build() async => exits;
}

AppExit _exit(String node, String ip, int minutesAgo) {
  final at = DateTime.now().subtract(Duration(minutes: minutesAgo));
  return AppExit(node: node, ip: ip, country: 'JP', first: at, last: at);
}

void main() {
  late ProviderContainer container;
  late _MockCore core;
  var exits = <String, List<AppExit>>{};

  setUpAll(() {
    registerFallbackValue(
      const TestDelayParams(proxyName: '', testUrl: '', timeout: 0),
    );
    registerFallbackValue(
      const ChangeProxyParams(groupName: '', proxyName: ''),
    );
  });

  setUp(() {
    exits = {};
    core = _MockCore();
    when(() => core.testDelay(any())).thenAnswer((invocation) async {
      final params = invocation.positionalArguments.single as TestDelayParams;
      return Delay(name: params.proxyName, url: params.testUrl, value: 88);
    });
    when(
      () => core.changeProxy(any()),
    ).thenAnswer((_) async => const ChangeProxyResult());
    container = ProviderContainer(
      overrides: [
        appExitsProvider.overrideWith(() => _Exits(exits)),
        coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
      ],
    );
    globalState.container = container;
    container.listen(groupsProvider, (_, _) {});
    container.listen(packagesProvider, (_, _) {});
    container.listen(patchClashConfigProvider, (_, _) {});
    container.listen(requestsProvider, (_, _) {});
  });

  tearDown(() => container.dispose());

  Map<String, String> routes() =>
      container.read(patchClashConfigProvider).slothAppRoutes;

  PatchClashConfig config() => container.read(patchClashConfigProvider);

  void route(Map<String, String> routes) => container
      .read(patchClashConfigProvider.notifier)
      .update((state) => state.copyWith(slothAppRoutes: routes));

  void change(PatchClashConfig Function(PatchClashConfig state) update) =>
      container.read(patchClashConfigProvider.notifier).update(update);

  Future<void> pumpCard(WidgetTester tester) async {
    const size = Size(400, 1400);
    container.read(viewSizeProvider.notifier).value = size;
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TestApp(
          child: HostScaffold(
            body: SizedBox(
              width: 360,
              child: DashboardDensityScope(
                density: DashboardDensity.mobile,
                scale: 1,
                child: AppRoutesCard(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('a card with no app routed says what it is for', (tester) async {
    await pumpCard(tester);

    expect(find.textContaining('YouTube through Japan'), findsOneWidget);
    expect(find.text('Choose apps'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('each routed app shows where it goes, past four only counted', (
    tester,
  ) async {
    container.read(packagesProvider.notifier).value = _packages;
    container.read(groupsProvider.notifier).value = _groups;
    route({
      'com.example.video': 'Media',
      'com.example.chat': appRouteDirect,
      'com.example.web': appRouteBlock,
      'com.example.mail': 'JP-01',
      'com.example.maps': 'US-01',
    });
    await pumpCard(tester);

    expect(find.text('Video'), findsOneWidget);
    expect(find.text('Media'), findsOneWidget);
    expect(find.text('Direct'), findsOneWidget);
    expect(find.text('No network'), findsOneWidget);
    expect(find.text('Maps'), findsNothing);
    expect(find.text('+1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a route to what the profile lost is marked', (tester) async {
    container.read(packagesProvider.notifier).value = _packages;
    container.read(groupsProvider.notifier).value = _groups;
    route({'com.example.video': 'Gone', 'com.example.chat': 'Media'});
    await pumpCard(tester);

    expect(
      find.bySemanticsLabel(RegExp('Video Gone No longer in the profile')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel(RegExp('Chat Media')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Chat Media No longer')), findsNothing);
  });

  testWidgets('a row picks a new way for its app or hands it back to the '
      'rules', (tester) async {
    container.read(packagesProvider.notifier).value = _packages;
    container.read(groupsProvider.notifier).value = _groups;
    route({'com.example.video': 'Media'});
    await pumpCard(tester);

    await tester.tap(find.text('Video'));
    await tester.pumpAndSettle();
    expect(find.text('Follow the rules'), findsOneWidget);
    expect(find.text('JP-01'), findsWidgets);
    expect(find.text('US-01'), findsOneWidget);

    await tester.tap(find.text('US-01'));
    await tester.pumpAndSettle();
    expect(routes(), {'com.example.video': 'US-01'});
    expect(find.text('Follow the rules'), findsNothing);

    await tester.tap(find.text('Video'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Follow the rules'));
    await tester.pumpAndSettle();
    expect(routes(), isEmpty);
    expect(find.textContaining('YouTube through Japan'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the app list routes an app without leaving the list', (
    tester,
  ) async {
    container.read(groupsProvider.notifier).value = _groups;
    await pumpCard(tester);

    await tester.tap(find.text('Choose apps'));
    await tester.pumpAndSettle();
    container.read(packagesProvider.notifier).value = [
      ..._packages,
      const Package(
        packageName: 'com.example.service',
        label: 'Service',
        system: true,
        internet: true,
        lastUpdateTime: 0,
      ),
    ];
    await tester.pumpAndSettle();
    expect(find.text('Chat'), findsOneWidget);
    expect(find.text('Service'), findsNothing);

    await tester.tap(find.text('Chat'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('No network'));
    await tester.pumpAndSettle();

    expect(routes(), {'com.example.chat': appRouteBlock});
    expect(find.text('Chat'), findsWidgets);
    expect(find.text('No network'), findsWidgets);
    expect(find.text('Follow the rules'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an app shows the address it last went out from, and the '
      'others it used', (tester) async {
    container.read(packagesProvider.notifier).value = _packages;
    container.read(groupsProvider.notifier).value = _groups;
    route({'com.example.video': 'Media'});
    exits = {
      'com.example.video': [
        _exit('JP-01', '1.1.1.1', 3),
        _exit('US-01', '2.2.2.2', 90),
      ],
    };
    await pumpCard(tester);
    await tester.pump();

    expect(find.textContaining('1.1.1.1', findRichText: true), findsOneWidget);
    expect(find.textContaining('2.2.2.2', findRichText: true), findsNothing);

    await tester.tap(find.text('Video'));
    await tester.pumpAndSettle();
    expect(find.text('IPs used'), findsOneWidget);
    expect(find.text('Send through'), findsOneWidget);
    expect(find.text('JP-01 · 3 minutes ago'), findsOneWidget);

    await tester.tap(find.text('JP-01 · 3 minutes ago'));
    await tester.pumpAndSettle();
    expect(find.text('2.2.2.2'), findsOneWidget);
    expect(find.textContaining('US-01 · '), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an app whose route got through is marked like a pick, with '
      'the speed of its node', (tester) async {
    container.read(packagesProvider.notifier).value = _packages;
    container.read(groupsProvider.notifier).value = _groups;
    route({'com.example.video': 'JP-01', 'com.example.chat': appRouteDirect});
    container
        .read(requestsProvider.notifier)
        .addRequest(
          TrackerInfo(
            id: '1',
            start: DateTime.now(),
            metadata: const Metadata(),
            chains: const ['JP-01'],
            rule: processNameRule,
            rulePayload: 'com.example.video',
          ),
        );
    await pumpCard(tester);
    await tester.pumpAndSettle();

    expect(find.text('88 ms'), findsOneWidget);
    expect(find.byType(SelectionBadge), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Video JP-01 In use')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Chat Direct In use')), findsNothing);
    verify(() => core.testDelay(any())).called(1);
    expect(tester.takeException(), isNull);

    // The mark waits five minutes to lapse, longer than the test runs.
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('an app of its own picks switches between them on the card', (
    tester,
  ) async {
    const video = 'com.example.video';
    container.read(packagesProvider.notifier).value = _packages;
    container.read(groupsProvider.notifier).value = [
      ..._groups,
      Group(
        type: GroupType.Selector,
        name: appPicksGroupOf(video),
        hidden: true,
        now: 'US-01',
        all: const [
          Proxy(name: 'JP-01', type: 'ss'),
          Proxy(name: 'US-01', type: 'ss'),
        ],
      ),
    ];
    change((state) => state.withAppPicks(video, ['JP-01', 'US-01']));
    await pumpCard(tester);

    expect(find.bySemanticsLabel(RegExp('^Video US-01')), findsOneWidget);
    expect(find.text('JP-01'), findsOneWidget);

    await tester.tap(find.text('Auto'));
    await tester.pump();
    expect(config().slothAppAuto, [video]);
    expect(find.bySemanticsLabel(RegExp('^Video US-01 Auto')), findsOneWidget);

    await tester.tap(find.text('JP-01'));
    await tester.pump();
    expect(config().slothAppAuto, isEmpty);
    final params = verify(() => core.changeProxy(captureAny())).captured.single;
    expect(
      params,
      ChangeProxyParams(groupName: appPicksGroupOf(video), proxyName: 'JP-01'),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('an app the guard stopped says so in place of its speed', (
    tester,
  ) async {
    container.read(packagesProvider.notifier).value = _packages;
    container.read(groupsProvider.notifier).value = _groups;
    route({'com.example.video': 'JP-01'});
    container
        .read(requestsProvider.notifier)
        .addRequest(
          TrackerInfo(
            id: '1',
            start: DateTime.now(),
            metadata: const Metadata(),
            chains: const [slothGuardOutbound],
            rule: processNameRule,
            rulePayload: 'com.example.video',
          ),
        );
    await pumpCard(tester);
    await tester.pumpAndSettle();

    expect(find.text('Blocked'), findsOneWidget);
    expect(find.text('88 ms'), findsNothing);
    expect(
      find.bySemanticsLabel(RegExp('Video JP-01 Blocked')),
      findsOneWidget,
    );
    expect(find.byType(SelectionBadge), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('an app page gives the app its own picks and their switches', (
    tester,
  ) async {
    const video = 'com.example.video';
    container.read(packagesProvider.notifier).value = _packages;
    container.read(groupsProvider.notifier).value = _groups;
    route({video: 'Media'});
    await pumpCard(tester);

    await tester.tap(find.text('Video'));
    await tester.pumpAndSettle();
    expect(find.text('Switch automatically'), findsNothing);
    await tester.tap(find.text('Picks'));
    await tester.pumpAndSettle();
    // The page underneath lists the nodes too.
    await tester.tap(find.text('US-01').last);
    await tester.tap(find.text('JP-01').last);
    await tester.pump();
    await tester.tap(find.byTooltip('Confirm'));
    await tester.pumpAndSettle();

    expect(routes(), {video: appPicksGroupOf(video)});
    expect(config().slothAppPicks, {
      video: ['JP-01', 'US-01'],
    });
    expect(find.text('2 nodes'), findsOneWidget);

    await tester.tap(find.text('Switch automatically'));
    await tester.tap(find.text('Block impure nodes'));
    await tester.pump();
    expect(config().slothAppAuto, [video]);
    expect(config().slothAppPureOnly, [video]);

    change((state) => state.copyWith(slothPureOnly: true));
    await tester.pump();
    expect(
      find.text('Already on for every app in Privacy hardening'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
