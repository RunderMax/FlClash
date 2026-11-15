import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

Config _load(List<String> cards, List<String> seen) => Config.realFromJson({
  'themeProps': const ThemeProps().toJson(),
  'appSettingProps': {'dashboardWidgets': cards, 'seenDashboardWidgets': seen},
});

void main() {
  final all = [for (final card in DashboardWidget.values) card.name];

  test('a config from before the record keeps its cards and order', () {
    final config = _load(['currentOutbound', 'profiles', 'networkSpeed'], []);

    expect(config.appSettingProps.dashboardWidgets, const [
      DashboardWidget.currentOutbound,
      DashboardWidget.profiles,
      DashboardWidget.networkSpeed,
    ]);
    expect(config.appSettingProps.seenDashboardWidgets, all);
  });

  test('a card the user has seen and removed stays removed', () {
    final config = _load(['currentOutbound', 'networkSpeed'], all);

    expect(config.appSettingProps.dashboardWidgets, const [
      DashboardWidget.currentOutbound,
      DashboardWidget.networkSpeed,
    ]);
  });

  test('an unseen card joins the user order without reshuffling it', () {
    final seen = [...all]..remove(DashboardWidget.privacyCheck.name);
    final config = _load(['profiles', 'currentOutbound', 'networkSpeed'], seen);

    expect(config.appSettingProps.dashboardWidgets, const [
      DashboardWidget.profiles,
      DashboardWidget.currentOutbound,
      DashboardWidget.networkSpeed,
      DashboardWidget.privacyCheck,
    ]);
    expect(config.appSettingProps.seenDashboardWidgets, all);
  });
}
