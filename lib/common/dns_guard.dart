import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';

const _dnsGuardKeys = {
  DnsOverrideKey.enhancedMode,
  DnsOverrideKey.nameserver,
  DnsOverrideKey.proxyServerNameserver,
  DnsOverrideKey.respectRules,
};

/// Addresses rather than host names, so reaching a resolver never needs a
/// lookup of its own.
const _dnsGuardNameservers = [
  'https://1.1.1.1/dns-query',
  'https://8.8.8.8/dns-query',
];

/// The core answers for the nodes' own host names directly, as a lookup that
/// had to go through a node could never reach one.
const _dnsGuardProxyServerNameservers = [
  'https://223.5.5.5/dns-query',
  'https://1.1.1.1/dns-query',
];

/// The core refuses respect-rules without a proxy-server-nameserver, so a
/// profile takes it only from the guard, which always sets both.
Set<DnsOverrideKey> profileDnsOverrideKeys(Set<DnsOverrideKey> keys) =>
    keys.containsAll({
      DnsOverrideKey.respectRules,
      DnsOverrideKey.proxyServerNameserver,
    })
    ? {...DnsOverrideKey.normalProfileKeys, DnsOverrideKey.respectRules}
    : DnsOverrideKey.normalProfileKeys;

extension DnsGuardExt on PatchClashConfig {
  bool get dnsGuard =>
      dnsOverrideKeys.contains(DnsOverrideKey.respectRules) && dns.respectRules;

  /// Turning it off hands DNS back to the profile rather than to the values
  /// the switch replaced.
  PatchClashConfig withDnsGuard(bool enabled) => enabled
      ? copyWith(
          dns: dns.copyWith(
            enhancedMode: DnsMode.fakeIp,
            nameserver: _dnsGuardNameservers,
            proxyServerNameserver: _dnsGuardProxyServerNameservers,
            respectRules: true,
          ),
          dnsOverrideKeys: {...dnsOverrideKeys, ..._dnsGuardKeys},
        )
      : copyWith(
          dns: dns.copyWith(respectRules: false),
          dnsOverrideKeys: dnsOverrideKeys.difference(_dnsGuardKeys),
        );
}
