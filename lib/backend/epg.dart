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

/// A single EPG programme (times in UTC).
class EpgProgram {
  final DateTime start;
  final DateTime stop;
  final String title;
  const EpgProgram(this.start, this.stop, this.title);
}

final _channelIdRegex = RegExp(r'<channel id="([^"]+)"');
final _progChannelRegex = RegExp(r'channel="([^"]+)"');
final _progStartRegex = RegExp(r'start="(\d{14})\s*([+\-]\d{4})?"');
final _progStopRegex = RegExp(r'stop="(\d{14})\s*([+\-]\d{4})?"');
final _titleRegex = RegExp(r'<title[^>]*>(.*?)</title>', dotAll: true);

// Per-channel programme cache (short TTL — schedules change slowly).
final Map<String, List<EpgProgram>> _programCache = {};
final Map<String, DateTime> _programCacheAt = {};

/// Streams the XMLTV EPG and returns programmes for the channel whose
/// display-name matches [channelName]. Times are UTC.
Future<List<EpgProgram>> fetchPrograms(
  String epgUrl,
  String channelName,
) async {
  final target = normalizeChannelName(channelName);
  if (target.isEmpty) return [];
  final cacheKey = "$epgUrl|$target";
  final cachedAt = _programCacheAt[cacheKey];
  if (_programCache.containsKey(cacheKey) &&
      cachedAt != null &&
      DateTime.now().difference(cachedAt) < const Duration(minutes: 10)) {
    return _programCache[cacheKey]!;
  }
  final client = http.Client();
  try {
    final response = await client.send(http.Request('GET', Uri.parse(epgUrl)));
    if (response.statusCode != 200) {
      throw Exception('Failed to download EPG: ${response.statusCode}');
    }
    final ids = <String>{};
    final programs = <EpgProgram>[];
    final current = StringBuffer();
    await for (final line in response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      current.writeln(line);
      if (line.contains('</channel>')) {
        final block = current.toString();
        current.clear();
        final id = _channelIdRegex.firstMatch(block)?.group(1);
        if (id != null) {
          for (final dn in _displayNameRegex.allMatches(block)) {
            final key = normalizeChannelName(
              (dn.group(1) ?? '').replaceAll(_tagRegex, ''),
            );
            if (key == target) {
              ids.add(id);
              break;
            }
          }
        }
      } else if (line.contains('</programme>')) {
        final block = current.toString();
        current.clear();
        if (ids.isEmpty) continue;
        final ch = _progChannelRegex.firstMatch(block)?.group(1);
        if (ch == null || !ids.contains(ch)) continue;
        final sm = _progStartRegex.firstMatch(block);
        final em = _progStopRegex.firstMatch(block);
        if (sm == null || em == null) continue;
        final start = _parseXmltvTime(sm.group(1)!, sm.group(2));
        final stop = _parseXmltvTime(em.group(1)!, em.group(2));
        var title = (_titleRegex.firstMatch(block)?.group(1) ?? '')
            .replaceAll(_tagRegex, '')
            .trim();
        programs.add(EpgProgram(start, stop, _unescapeXml(title)));
      }
    }
    _programCache[cacheKey] = programs;
    _programCacheAt[cacheKey] = DateTime.now();
    return programs;
  } finally {
    client.close();
  }
}

DateTime _parseXmltvTime(String digits, String? tz) {
  var dt = DateTime.utc(
    int.parse(digits.substring(0, 4)),
    int.parse(digits.substring(4, 6)),
    int.parse(digits.substring(6, 8)),
    int.parse(digits.substring(8, 10)),
    int.parse(digits.substring(10, 12)),
    int.parse(digits.substring(12, 14)),
  );
  if (tz != null && tz.length == 5) {
    final sign = tz[0] == '-' ? -1 : 1;
    final offMinutes =
        int.parse(tz.substring(1, 3)) * 60 + int.parse(tz.substring(3, 5));
    dt = dt.subtract(Duration(minutes: sign * offMinutes));
  }
  return dt;
}

String _unescapeXml(String s) => s
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&#39;', "'");

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
