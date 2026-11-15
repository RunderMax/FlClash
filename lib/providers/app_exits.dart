import 'dart:async';

import 'package:fl_clash/common/app_exits.dart';
import 'package:fl_clash/common/app_routes.dart';
import 'package:fl_clash/common/common.dart';
import 'package:path/path.dart' show join;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'app.dart';

part 'generated/app_exits.g.dart';

/// The Core saves its record half a minute after a routed app goes online.
const _reloadAfter = Duration(seconds: 40);

@riverpod
class AppExits extends _$AppExits {
  Timer? _reload;

  @override
  Future<Map<String, List<AppExit>>> build() async {
    ref.onDispose(() => _reload?.cancel());
    ref.listen(requestsProvider, (_, requests) {
      if (_reload != null || requests.length == 0) {
        return;
      }
      if (requests[requests.length - 1].rule == processNameRule) {
        _reload = Timer(_reloadAfter, () {
          _reload = null;
          ref.invalidateSelf();
        });
      }
    });
    return loadAppExits(join(await appPath.homeDirPath, appExitsFile));
  }
}
