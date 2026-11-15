import 'package:fl_clash/common/app_routes.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

Future<YamlMap> _configOf(PatchClashConfig patch) async {
  final result = await makeRealProfileTask(
    MakeRealProfileState(
      profilesPath: '/profiles',
      profileId: 1,
      rawConfig: {
        'rules': ['MATCH,DIRECT'],
      },
      realPatchConfig: patch,
      overrides: const ProfileOverrides(),
      appendSystemDns: false,
      proxyGroups: const [],
      rules: const [],
      addedRules: const [],
      defaultUA: 'FlClash-Test',
    ),
  );
  return loadYaml(result.yaml) as YamlMap;
}

void main() {
  group('appRoutesFor', () {
    const routed = PatchClashConfig(
      slothAppRoutes: {'com.example.video': 'Media'},
    );

    test('looks processes up only for the rules once an app is routed', () {
      expect(
        routed.appRoutesFor(android: true).findProcessMode,
        FindProcessMode.strict,
      );
    });

    test('keeps a mode that already looks processes up', () {
      final always = routed.copyWith(findProcessMode: FindProcessMode.always);

      expect(
        always.appRoutesFor(android: true).findProcessMode,
        FindProcessMode.always,
      );
    });

    test('leaves lookups off with no app routed', () {
      expect(
        const PatchClashConfig().appRoutesFor(android: true).findProcessMode,
        FindProcessMode.off,
      );
    });

    test('hands no Android package to a desktop Core', () {
      final desktop = routed.appRoutesFor(android: false);

      expect(desktop.slothAppRoutes, isEmpty);
      expect(desktop.findProcessMode, FindProcessMode.off);
    });
  });

  group('withAppRoute', () {
    const config = PatchClashConfig(
      slothAppRoutes: {'com.example.a': 'Media', 'com.example.b': 'DIRECT'},
    );

    test('changes a route in its place', () {
      expect(
        config.withAppRoute('com.example.a', appRouteBlock).slothAppRoutes,
        {'com.example.a': appRouteBlock, 'com.example.b': 'DIRECT'},
      );
      expect(
        config
            .withAppRoute('com.example.a', appRouteBlock)
            .slothAppRoutes
            .keys
            .first,
        'com.example.a',
      );
    });

    test('adds a route last and removes one without a target', () {
      expect(
        config.withAppRoute('com.example.c', 'JP-01').slothAppRoutes.keys,
        ['com.example.a', 'com.example.b', 'com.example.c'],
      );
      expect(config.withAppRoute('com.example.a', null).slothAppRoutes, {
        'com.example.b': 'DIRECT',
      });
    });
  });

  group('the profile task', () {
    test('asks the core to route apps after the rules kept first', () async {
      final config = await _configOf(
        const PatchClashConfig(
          slothBlockQuic: true,
          slothAppRoutes: {'com.example.video': 'Media'},
        ),
      );

      final request = config[slothAppRoutesKey] as YamlMap;
      expect(request['at'], 2);
      expect(request['routes'], {'com.example.video': 'Media'});
      expect((config['rules'] as YamlList).length, 3);
    });

    test('asks for nothing with no app routed', () async {
      final config = await _configOf(const PatchClashConfig());

      expect(config.containsKey(slothAppRoutesKey), isFalse);
    });
  });
}
