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
  test('asks the core for the fastest group of the chosen nodes', () async {
    final config = await _configOf(
      const PatchClashConfig(
        slothFastest: true,
        slothFastestProxies: ['a', 'b'],
      ),
    );

    final request = config[slothFastestKey] as YamlMap;
    expect(request['name'], slothFastestGroup);
    expect(request['proxies'], ['a', 'b']);
  });

  test('asks for nothing while switched off or with no nodes', () async {
    final off = await _configOf(
      const PatchClashConfig(slothFastestProxies: ['a']),
    );
    final empty = await _configOf(const PatchClashConfig(slothFastest: true));

    expect(off.containsKey(slothFastestKey), isFalse);
    expect(empty.containsKey(slothFastestKey), isFalse);
  });
}
