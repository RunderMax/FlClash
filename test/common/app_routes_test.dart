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
        routed.appRoutesFor(listsApps: true).findProcessMode,
        FindProcessMode.strict,
      );
    });

    test('keeps a mode that already looks processes up', () {
      final always = routed.copyWith(findProcessMode: FindProcessMode.always);

      expect(
        always.appRoutesFor(listsApps: true).findProcessMode,
        FindProcessMode.always,
      );
    });

    test('leaves lookups off with no app routed', () {
      expect(
        const PatchClashConfig().appRoutesFor(listsApps: true).findProcessMode,
        FindProcessMode.off,
      );
    });

    test('hands no app to a Core the app cannot name apps for', () {
      final desktop = routed
          .copyWith(slothAppPureOnly: ['com.example.chat'])
          .appRoutesFor(listsApps: false);

      expect(desktop.slothAppRoutes, isEmpty);
      expect(desktop.slothAppPureOnly, isEmpty);
      expect(desktop.findProcessMode, FindProcessMode.off);
    });

    test('looks processes up for an app that is only guarded', () {
      const guarded = PatchClashConfig(slothAppPureOnly: ['com.example.chat']);

      expect(
        guarded.appRoutesFor(listsApps: true).findProcessMode,
        FindProcessMode.strict,
      );
    });
  });

  group('an app of its own picks', () {
    const app = 'com.example.video';

    test('takes its picks group and gives it back with no picks', () {
      final picked = const PatchClashConfig().withAppPicks(app, ['JP', 'US']);

      expect(picked.slothAppRoutes, {app: appPicksGroupOf(app)});
      expect(picked.usesOwnPicks(app), isTrue);

      final cleared = picked.withAppPicks(app, const []);
      expect(cleared.slothAppRoutes, isEmpty);
      expect(cleared.slothAppPicks, isEmpty);
    });

    test('keeps its picks while it goes another way', () {
      final elsewhere = const PatchClashConfig()
          .withAppPicks(app, ['JP'])
          .withAppRoute(app, 'DIRECT');

      expect(elsewhere.slothAppPicks, {
        app: ['JP'],
      });
      expect(elsewhere.appPicksRequest, isEmpty);
      expect(elsewhere.withAppPicks(app, const []).slothAppRoutes, {
        app: 'DIRECT',
      });
    });

    test('asks the Core for each group with its switch', () {
      final config = const PatchClashConfig()
          .withAppPicks(app, ['JP', 'US'])
          .withAppAuto(app, true);

      expect(config.appPicksRequest, {
        app: {
          'proxies': ['JP', 'US'],
          'auto': true,
        },
      });
      expect(config.withAppAuto(app, false).slothAppAuto, isEmpty);
    });

    test('lists the apps only guarded after the routed ones', () {
      final config =
          const PatchClashConfig(slothAppRoutes: {'com.example.b': 'DIRECT'})
              .withAppPureOnly('com.example.a', true)
              .withAppPureOnly('com.example.b', true);

      expect(config.appRouteApps, ['com.example.b', 'com.example.a']);
      expect(config.withAppPureOnly('com.example.a', false).slothAppPureOnly, [
        'com.example.b',
      ]);
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

    test('asks for a SLOTHIVE service by its proxy user', () async {
      final config = await _configOf(
        const PatchClashConfig().withAppRoute(
          SlothiveService.chatGpt.key,
          'US',
        ),
      );

      final request = config[slothAppRoutesKey] as YamlMap;
      expect(request['sites'], {
        SlothiveService.chatGpt.key: ['IN-USER,slothive-chatgpt'],
      });
    });

    test('asks for nothing with no app routed', () async {
      final config = await _configOf(const PatchClashConfig());

      expect(config.containsKey(slothAppRoutesKey), isFalse);
      expect(config.containsKey(slothGuardKey), isFalse);
    });

    test('asks for an app its picks group, auto or not', () async {
      final config = await _configOf(
        const PatchClashConfig()
            .withAppPicks('com.example.video', ['JP'])
            .withAppAuto('com.example.video', true),
      );

      final request = config[slothAppRoutesKey] as YamlMap;
      expect(request['picks'], {
        'com.example.video': {
          'proxies': ['JP'],
          'auto': true,
        },
      });
    });

    test('asks for the guard with either switch on', () async {
      final config = await _configOf(
        const PatchClashConfig(
          slothPureOnly: true,
          slothAppPureOnly: ['com.example.chat'],
        ),
      );

      expect(config[slothGuardKey], {
        'all': true,
        'apps': ['com.example.chat'],
      });
    });

    test('makes the picks group pick by itself when it is automatic', () async {
      final config = await _configOf(
        const PatchClashConfig(slothPicks: ['JP'], slothPickAuto: true),
      );

      expect((config[slothPicksKey] as YamlMap)['type'], 'url-test');
    });
  });

  group('an app routed by its folder', () {
    const folders = {
      'Google Chrome': '/Applications/Google Chrome.app/',
      'Idle': '/Applications/Idle.app/',
      'Guarded': r'C:\Program Files\Guarded\',
    };

    test('sends the folders of the apps routed or guarded only', () async {
      final config = await _configOf(
        const PatchClashConfig(
          slothAppRoutes: {'Google Chrome': 'DIRECT'},
          slothAppPureOnly: ['Guarded'],
          slothAppFolders: folders,
        ),
      );

      expect(config[slothAppFoldersKey], {
        'Google Chrome': '/Applications/Google Chrome.app/',
        'Guarded': r'C:\Program Files\Guarded\',
      });
    });

    test('sends none when no app with a folder is in use', () async {
      final config = await _configOf(
        const PatchClashConfig(slothAppFolders: folders),
      );

      expect(config.containsKey(slothAppFoldersKey), isFalse);
    });

    test('names the app whose folder holds a program, case aside', () {
      expect(
        folderAppOf(
          folders,
          '/applications/google chrome.app/Contents/Frameworks/Helper',
        ),
        'Google Chrome',
      );
      expect(
        folderAppOf(folders, r'c:\program files\guarded\bin\worker.exe'),
        'Guarded',
      );
      expect(folderAppOf(folders, '/Applications/Google Chrome.app'), isNull);
      expect(folderAppOf(folders, ''), isNull);
    });

    test('an app inside another app\'s folder is itself', () {
      expect(
        folderAppOf(const {
          'Suite': r'C:\Apps\Suite\',
          'Tool': r'C:\Apps\Suite\Tool\',
        }, r'C:\Apps\Suite\Tool\tool.exe'),
        'Tool',
      );
    });
  });
}
