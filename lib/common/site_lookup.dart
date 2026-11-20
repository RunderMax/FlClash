import 'dart:io';
import 'dart:isolate';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Domains so many sites load that routing one would move them all.
const sharedDomains = {
  'apple.com',
  'cdnjs.com',
  'cloudflare.com',
  'cloudflareinsights.com',
  'doubleclick.net',
  'facebook.com',
  'facebook.net',
  'github.com',
  'githubusercontent.com',
  'google-analytics.com',
  'google.com',
  'googleapis.com',
  'googlesyndication.com',
  'googletagmanager.com',
  'gstatic.com',
  'jsdelivr.net',
  'microsoft.com',
  'schema.org',
  'twitter.com',
  'unpkg.com',
  'w3.org',
  'x.com',
  'youtube.com',
  'ytimg.com',
};

const _secondLevels = {
  'ac',
  'co',
  'com',
  'edu',
  'go',
  'gov',
  'ne',
  'net',
  'or',
  'org',
};

/// The part of [host] a site owns, so that every subdomain goes with it.
String registrableDomain(String host) {
  final labels = host.toLowerCase().split('.')
    ..removeWhere((label) => label.isEmpty);
  if (labels.length <= 2) return labels.join('.');
  final take =
      labels.last.length == 2 &&
          _secondLevels.contains(labels[labels.length - 2])
      ? 3
      : 2;
  return labels.sublist(labels.length - take).join('.');
}

/// The host in what someone typed, or null where it names no site.
String? hostOf(String query) {
  final text = query.trim().toLowerCase();
  if (!text.contains('.') || text.contains(' ')) return null;
  final uri = Uri.tryParse(text.contains('://') ? text : 'https://$text');
  final host = uri?.host ?? '';
  final valid = RegExp(r'^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9-]+)+$');
  return valid.hasMatch(host) ? host.replaceFirst(RegExp(r'^www\.'), '') : null;
}

/// GeoSite.dat as category to the domains it routes whole, its plain and
/// regex entries left out.
Future<Map<String, List<String>>> readGeosite(String file) async {
  final bytes = await File(file).readAsBytes();
  return Isolate.run(() => parseGeosite(bytes));
}

@visibleForTesting
Map<String, List<String>> parseGeosite(Uint8List bytes) {
  final book = <String, List<String>>{};
  for (final (field, site) in _fields(bytes, 0, bytes.length)) {
    if (field != 1 || site == null) continue;
    String? code;
    final domains = <String>[];
    for (final (siteField, value) in _fields(bytes, site.$1, site.$2)) {
      if (value == null) continue;
      if (siteField == 1) code = _string(bytes, value);
      if (siteField != 2) continue;
      var type = 0;
      String? domain;
      for (final (domainField, part) in _fields(bytes, value.$1, value.$2)) {
        if (domainField == 1 && part == null) type = _lastVarint;
        if (domainField == 2 && part != null) domain = _string(bytes, part);
      }
      if (domain != null && (type == 2 || type == 3)) domains.add(domain);
    }
    if (code != null) book[code.toLowerCase()] = domains;
  }
  return book;
}

int _lastVarint = 0;

/// The fields of the message in [start, end): a length-delimited one with its
/// span, any other with none, its varint left in [_lastVarint].
Iterable<(int, (int, int)?)> _fields(Uint8List b, int start, int end) sync* {
  var i = start;
  int varint() {
    var result = 0;
    var shift = 0;
    while (i < end) {
      final byte = b[i++];
      result |= (byte & 0x7f) << shift;
      if (byte < 0x80) break;
      shift += 7;
    }
    return result;
  }

  while (i < end) {
    final key = varint();
    final wire = key & 7;
    switch (wire) {
      case 0:
        _lastVarint = varint();
        yield (key >> 3, null);
      case 2:
        final length = varint();
        final span = (i, i + length);
        i += length;
        yield (key >> 3, span);
      case 1:
        i += 8;
      case 5:
        i += 4;
      default:
        return;
    }
  }
}

String _string(Uint8List b, (int, int) span) =>
    String.fromCharCodes(b.sublist(span.$1, span.$2));

/// The categories [query] names, by name or by one of their domains, the most
/// specific first.
List<String> findCategories(Map<String, List<String>> book, String query) {
  final text = query.trim().toLowerCase();
  final host = hostOf(text);
  final found = <String>{};
  if (book.containsKey(text)) found.add(text);
  if (host == null && RegExp(r'^[a-z0-9-]{3,}$').hasMatch(text)) {
    for (final code in book.keys) {
      if (code.contains(text) && !code.contains('!')) found.add(code);
    }
  }
  if (host != null) {
    for (final MapEntry(key: code, value: domains) in book.entries) {
      if (code.contains('!') ||
          code.startsWith('tld-') ||
          domains.length > 3000) {
        continue;
      }
      if (domains.any((d) => host == d || host.endsWith('.$d'))) {
        found.add(code);
      }
    }
  }
  return found.toList()..sort((a, b) {
    if (a == text) return -1;
    if (b == text) return 1;
    return book[a]!.length.compareTo(book[b]!.length);
  });
}

/// The sites [host]'s front page loads from, its own first.
Future<List<String>> pageDomains(Dio dio, String host) async {
  final response = await dio.get<String>(
    'https://$host',
    options: Options(
      responseType: ResponseType.plain,
      receiveTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 10),
    ),
  );
  final own = registrableDomain(response.realUri.host);
  final found = <String>{registrableDomain(host), own};
  final link = RegExp(
    r'(?:https?:)?//([a-z0-9][a-z0-9.-]*\.[a-z]{2,})',
    caseSensitive: false,
  );
  for (final match in link.allMatches(response.data ?? '')) {
    found.add(registrableDomain(match.group(1)!));
  }
  return found.toList();
}
