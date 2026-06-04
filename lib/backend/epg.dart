import 'dart:convert';

import 'package:http/http.dart' as http;

final _channelBlockRegex = RegExp(
  r'<channel\b[^>]*>(.*?)</channel>',
  dotAll: true,
);
final _displayNameRegex = RegExp(
  r'<display-name[^>]*>(.*?)</display-name>',
  dotAll: true,
);
final _iconRegex = RegExp(r'<icon[^>]*\bsrc="([^"]*)"');
final _tagRegex = RegExp(r'<[^>]+>');
final _nonAlphaNumRegex = RegExp(r'[^0-9a-zа-яё]');

/// Normalizes a channel name so playlist names and EPG display-names can be
/// matched regardless of case, quality markers and punctuation.
/// Keeps only latin/cyrillic letters and digits.
String normalizeChannelName(String name) {
  final lower = name.toLowerCase().replaceAll('&amp;', '&');
  return lower.replaceAll(_nonAlphaNumRegex, '');
}

// Simple in-memory cache so refreshing several sources in a row doesn't
// re-download the (large) EPG every time.
Map<String, String>? _cachedLogos;
String? _cachedUrl;
DateTime? _cachedAt;
const _cacheTtl = Duration(minutes: 10);

/// Downloads an XMLTV EPG and builds a map of normalized channel name -> logo url.
/// Only the `<channel>` section is read; downloading stops once `<programme>`
/// entries begin, so we never pull the (much larger) program data.
Future<Map<String, String>> fetchEpgLogos(String epgUrl) async {
  if (_cachedLogos != null &&
      _cachedUrl == epgUrl &&
      _cachedAt != null &&
      DateTime.now().difference(_cachedAt!) < _cacheTtl) {
    return _cachedLogos!;
  }
  final client = http.Client();
  try {
    final request = http.Request('GET', Uri.parse(epgUrl));
    final response = await client.send(request);
    if (response.statusCode != 200) {
      throw Exception('Failed to download EPG: ${response.statusCode}');
    }
    final buffer = StringBuffer();
    await for (final line in response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      buffer.writeln(line);
      // All <channel> entries come before any <programme>; stop reading there.
      if (line.contains('<programme')) break;
    }
    final logos = _parseLogos(buffer.toString());
    _cachedLogos = logos;
    _cachedUrl = epgUrl;
    _cachedAt = DateTime.now();
    return logos;
  } finally {
    client.close();
  }
}

Map<String, String> _parseLogos(String xml) {
  final map = <String, String>{};
  for (final block in _channelBlockRegex.allMatches(xml)) {
    final content = block.group(1)!;
    final icon = _iconRegex.firstMatch(content)?.group(1);
    if (icon == null || icon.isEmpty) continue;
    for (final dn in _displayNameRegex.allMatches(content)) {
      final raw = (dn.group(1) ?? '').replaceAll(_tagRegex, '');
      final key = normalizeChannelName(raw);
      if (key.isNotEmpty) map.putIfAbsent(key, () => icon);
    }
  }
  return map;
}
