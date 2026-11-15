import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';

const appRouteDirect = 'DIRECT';
const appRouteBlock = 'REJECT';

extension AppRoutesExt on PatchClashConfig {
  /// Off never looks up which app a connection is from, as the rules need.
  PatchClashConfig appRoutesFor({required bool android}) {
    if (slothAppRoutes.isEmpty) {
      return this;
    }
    if (!android) {
      return copyWith(slothAppRoutes: const {});
    }
    return findProcessMode == FindProcessMode.off
        ? copyWith(findProcessMode: FindProcessMode.strict)
        : this;
  }

  PatchClashConfig withAppRoute(String packageName, String? target) {
    final routes = {...slothAppRoutes};
    if (target == null) {
      routes.remove(packageName);
    } else {
      routes[packageName] = target;
    }
    return copyWith(slothAppRoutes: routes);
  }
}
