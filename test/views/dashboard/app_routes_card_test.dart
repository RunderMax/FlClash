import 'package:fl_clash/common/app_routes.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/dashboard/layout.dart';
import 'package:fl_clash/views/dashboard/widgets/app_routes.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
    globalState.container = container;
    container.listen(groupsProvider, (_, _) {});
    container.listen(packagesProvider, (_, _) {});
    container.listen(patchClashConfigProvider, (_, _) {});
  });

  tearDown(() => container.dispose());

  Map<String, String> routes() =>
      container.read(patchClashConfigProvider).slothAppRoutes;

  void route(Map<String, String> routes) => container
      .read(patchClashConfigProvider.notifier)
      .update((state) => state.copyWith(slothAppRoutes: routes));

  Future<void> pumpCard(WidgetTester tester) async {
    const size = Size(400, 900);
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
}
