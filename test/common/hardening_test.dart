import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

Future<List<String>> _rulesOf(PatchClashConfig patch) async {
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
  final config = loadYaml(result.yaml) as YamlMap;
  return [...(config['rules'] as YamlList).cast<String>()];
}

void main() {
  test('the hardening rules go ahead of the profile rules', () async {
    final rules = await _rulesOf(
      const PatchClashConfig(slothBlockQuic: true, slothBlockAds: true),
    );

    expect(rules.last, 'MATCH,DIRECT');
    expect(rules.first, contains('DST-PORT,443'));
    expect(rules, contains('GEOSITE,category-ads-all,REJECT'));
  });

  test('nothing is added while the switches are off', () async {
    expect(await _rulesOf(const PatchClashConfig()), ['MATCH,DIRECT']);
  });
}
