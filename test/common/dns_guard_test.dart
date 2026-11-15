import 'package:fl_clash/common/dns_guard.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the guard routes lookups through the proxy and hands them back', () {
    const config = PatchClashConfig(dnsOverrideKeys: {DnsOverrideKey.ipv6});
    final guarded = config.withDnsGuard(true);
    expect(guarded.dnsGuard, isTrue);
    expect(guarded.dns.respectRules, isTrue);
    expect(guarded.dns.proxyServerNameserver, isNotEmpty);
    expect(
      guarded.dnsOverrideKeys,
      containsAll({DnsOverrideKey.respectRules, DnsOverrideKey.ipv6}),
    );
    expect(
      profileDnsOverrideKeys(guarded.dnsOverrideKeys),
      containsAll(guarded.dnsOverrideKeys.difference({DnsOverrideKey.ipv6})),
    );
    expect(
      profileDnsOverrideKeys({DnsOverrideKey.respectRules}),
      isNot(contains(DnsOverrideKey.respectRules)),
    );

    final released = guarded.withDnsGuard(false);
    expect(released.dnsGuard, isFalse);
    expect(released.dnsOverrideKeys, {DnsOverrideKey.ipv6});
  });
}
