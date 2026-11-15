import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

Future<YamlMap> _configOf(PatchClashConfig patch) async {
  final result = await makeRealProfileTask(
    MakeRealProfileState(
      profilesPath: '/profiles',
      profileId: 1,
      rawConfig: {},
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
  test('asks the core for a select group of the picked nodes', () async {
    final config = await _configOf(
      const PatchClashConfig(slothPicks: ['b', 'a']),
    );

    final request = config[slothPicksKey] as YamlMap;
    expect(request['name'], slothPicksGroup);
    expect(request['type'], 'select');
    expect(request['proxies'], ['b', 'a']);
    expect(request['record'], 180);
  });

  test('records nothing once the record is switched off', () async {
    final config = await _configOf(
      const PatchClashConfig(slothPicks: ['a'], slothPickRecord: false),
    );

    expect((config[slothPicksKey] as YamlMap)['record'], 0);
  });

  test('asks for nothing without picks', () async {
    final config = await _configOf(const PatchClashConfig());

    expect(config.containsKey(slothPicksKey), isFalse);
  });
}
