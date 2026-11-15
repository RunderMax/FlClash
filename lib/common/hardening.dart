import 'package:fl_clash/models/models.dart';

/// QUIC hides the host name the rules match on, and STUN is how a page learns
/// an address outside the proxy; dropped, both fall back to what the proxy
/// carries.
const _quicStunRules = [
  'AND,((NETWORK,UDP),(DST-PORT,443)),REJECT-DROP',
  'AND,((NETWORK,UDP),(DST-PORT,3478/19302)),REJECT-DROP',
];

/// The site list ships with the app, so the rule never waits on a download.
const _adRules = ['GEOSITE,category-ads-all,REJECT'];

/// Placed ahead of every profile rule, so a profile cannot route around them.
List<String> hardeningRules(PatchClashConfig config) => [
  if (config.slothBlockQuic) ..._quicStunRules,
  if (config.slothBlockAds) ..._adRules,
];
