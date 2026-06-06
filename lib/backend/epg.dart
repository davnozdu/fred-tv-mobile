import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_tv/memory.dart';
import 'package:path_provider/path_provider.dart';

/// Default EPG with a week of past programmes (gzipped) — used for the archive
/// list. Logos stay on epg.one (better name coverage); this one is only pulled
/// on demand when opening the archive menu.
const archiveEpgUrl = 'https://iptvx.one/epg/epg_lite.xml.gz';

/// EPG/broadcast timezone (Moscow, no DST). Programme times are shown in this
/// zone so they match the actual Russian TV schedule regardless of device tz.
const epgDisplayOffset = Duration(hours: 3);
DateTime epgLocal(DateTime utc) => utc.toUtc().add(epgDisplayOffset);

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

const _qualTokens = {
  'hd', 'uhd', 'fhd', '4k', '2k', 'sd', 'hevc', 'h265', 'h264',
  'fps', 'orig', 'original', 'backup', 'raw', '50', '60',
};
const _countryTokens = {
  'uk', 'us', 'usa', 'fr', 'de', 'nl', 'pl', 'ua', 'ru', 'it', 'es', 'tr',
  'ge', 'az', 'by', 'kz', 'am', 'il', 'uz', 'tj', 'md', 'ro', 'pt', 'gb',
  'at', 'ch', 'be', 'se', 'no', 'fi', 'dk', 'cz', 'sk', 'hu', 'gr', 'rs',
  'hr', 'bg', 'ee', 'lv', 'lt',
};
final _parensRegex = RegExp(r'\([^)]*\)');
final _shiftRegex = RegExp(r'\+\d+');
final _splitRegex = RegExp(r'[^0-9a-zа-яё]+');

/// Looser normalization for matching against EPGs that lack quality/region
/// display-name variants: strips HD/UHD/4K/+N/(region)/country tokens.
String normalizeChannelNameLoose(String name) {
  var s = name.toLowerCase().replaceAll('&amp;', '&');
  s = s.replaceAll(_parensRegex, '').replaceAll(_shiftRegex, '');
  final out = <String>[];
  for (final t in s.split(_splitRegex)) {
    if (t.isEmpty || _qualTokens.contains(t) || _countryTokens.contains(t)) {
      continue;
    }
    out.add(t);
  }
  return out.join();
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

// Cache for the full guide (all channels' programmes in a time window).
Map<String, List<EpgProgram>>? _allPrograms;
DateTime? _allProgramsAt;

/// Returns programmes for every channel (normalized name -> programmes in a
/// window around now), for the TV guide grid. Parsed in a background isolate.
Future<Map<String, List<EpgProgram>>> fetchAllPrograms(String epgUrl) async {
  final url = epgUrl.trim();
  if (url.isEmpty) return {};
  if (_allPrograms != null &&
      _allProgramsAt != null &&
      DateTime.now().difference(_allProgramsAt!) < const Duration(minutes: 15)) {
    return _allPrograms!;
  }
  final data = await compute(_parseAllPrograms, url);
  final namesById = data['names'] as Map;
  final progsById = data['progs'] as Map;
  final result = <String, List<EpgProgram>>{};
  progsById.forEach((id, list) {
    final programs =
        (list as List)
            .map((m) => _programFromMap(Map<String, dynamic>.from(m as Map)))
            .toList()
          ..sort((a, b) => a.start.compareTo(b.start));
    for (final name in (namesById[id] as List? ?? const [])) {
      result[name as String] = programs;
    }
  });
  _allPrograms = result;
  _allProgramsAt = DateTime.now();
  return result;
}

// Isolate: parse all channels' programmes in [now-6h, now+30h].
Future<Map<String, dynamic>> _parseAllPrograms(String epgUrl) async {
  final client = http.Client();
  try {
    final response = await client.send(http.Request('GET', Uri.parse(epgUrl)));
    if (response.statusCode != 200) {
      throw Exception('Failed to download EPG: ${response.statusCode}');
    }
    Stream<List<int>> bytes = response.stream;
    if (epgUrl.endsWith('.gz')) {
      bytes = bytes.transform(gzip.decoder);
    }
    final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    final lower = nowMs - 6 * 3600 * 1000;
    final upper = nowMs + 30 * 3600 * 1000;
    final idNames = <String, List<String>>{};
    final idProgs = <String, List<Map<String, dynamic>>>{};
    final current = StringBuffer();
    await for (final line in bytes
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      current.writeln(line);
      if (line.contains('</channel>')) {
        final block = current.toString();
        current.clear();
        final id = _channelIdRegex.firstMatch(block)?.group(1);
        if (id != null) {
          final names = <String>[];
          for (final dn in _displayNameRegex.allMatches(block)) {
            final k = normalizeChannelNameLoose(
              (dn.group(1) ?? '').replaceAll(_tagRegex, ''),
            );
            if (k.isNotEmpty) names.add(k);
          }
          if (names.isNotEmpty) idNames[id] = names;
        }
      } else if (line.contains('</programme>')) {
        final block = current.toString();
        current.clear();
        final ch = _progChannelRegex.firstMatch(block)?.group(1);
        if (ch == null || !idNames.containsKey(ch)) continue;
        final sm = _progStartRegex.firstMatch(block);
        final em = _progStopRegex.firstMatch(block);
        if (sm == null || em == null) continue;
        final start = _parseXmltvTime(sm.group(1)!, sm.group(2));
        final stop = _parseXmltvTime(em.group(1)!, em.group(2));
        final sMs = start.millisecondsSinceEpoch;
        final eMs = stop.millisecondsSinceEpoch;
        if (eMs <= lower || sMs >= upper) continue;
        final title = (_titleRegex.firstMatch(block)?.group(1) ?? '')
            .replaceAll(_tagRegex, '')
            .trim();
        (idProgs[ch] ??= []).add({'s': sMs, 'e': eMs, 't': _unescapeXml(title)});
      }
    }
    return {'names': idNames, 'progs': idProgs};
  } finally {
    client.close();
  }
}

/// Refreshes the global "now playing" map (normalized name -> current title)
/// from the logo EPG, in the background. Cached for 15 minutes.
Future<void> refreshNowPlaying(String epgUrl) async {
  final url = epgUrl.trim();
  if (url.isEmpty) return;
  if (nowPlayingAt != null &&
      nowPlaying.value.isNotEmpty &&
      DateTime.now().difference(nowPlayingAt!) < const Duration(minutes: 15)) {
    return;
  }
  try {
    final map = await compute(_parseNowPlaying, url);
    nowPlaying.value = map;
    nowPlayingAt = DateTime.now();
  } catch (_) {}
}

// Runs in a background isolate: returns normalized name -> currently airing title.
Future<Map<String, String>> _parseNowPlaying(String epgUrl) async {
  final client = http.Client();
  try {
    final response = await client.send(http.Request('GET', Uri.parse(epgUrl)));
    if (response.statusCode != 200) {
      throw Exception('Failed to download EPG: ${response.statusCode}');
    }
    Stream<List<int>> bytes = response.stream;
    if (epgUrl.endsWith('.gz')) {
      bytes = bytes.transform(gzip.decoder);
    }
    final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    final idToNames = <String, List<String>>{};
    final idToTitle = <String, String>{};
    final current = StringBuffer();
    await for (final line in bytes
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      current.writeln(line);
      if (line.contains('</channel>')) {
        final block = current.toString();
        current.clear();
        final id = _channelIdRegex.firstMatch(block)?.group(1);
        if (id != null) {
          final names = <String>[];
          // Loose normalization (same as the guide grid) so the catalog marquee
          // and the Guide map a channel to the same EPG entry → same programme.
          for (final dn in _displayNameRegex.allMatches(block)) {
            final k = normalizeChannelNameLoose(
              (dn.group(1) ?? '').replaceAll(_tagRegex, ''),
            );
            if (k.isNotEmpty) names.add(k);
          }
          if (names.isNotEmpty) idToNames[id] = names;
        }
      } else if (line.contains('</programme>')) {
        final block = current.toString();
        current.clear();
        final ch = _progChannelRegex.firstMatch(block)?.group(1);
        if (ch == null ||
            !idToNames.containsKey(ch) ||
            idToTitle.containsKey(ch)) {
          continue;
        }
        final sm = _progStartRegex.firstMatch(block);
        final em = _progStopRegex.firstMatch(block);
        if (sm == null || em == null) continue;
        final start = _parseXmltvTime(sm.group(1)!, sm.group(2));
        final stop = _parseXmltvTime(em.group(1)!, em.group(2));
        if (start.millisecondsSinceEpoch <= nowMs &&
            nowMs < stop.millisecondsSinceEpoch) {
          final title = (_titleRegex.firstMatch(block)?.group(1) ?? '')
              .replaceAll(_tagRegex, '')
              .trim();
          idToTitle[ch] = _unescapeXml(title);
        }
      }
    }
    final result = <String, String>{};
    idToTitle.forEach((id, title) {
      for (final name in idToNames[id] ?? const <String>[]) {
        result[name] = title;
      }
    });
    return result;
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

/// Returns programmes for the channel matching [channelName]. The heavy
/// download + gzip + parse runs in a background isolate (UI stays responsive),
/// with an in-memory and on-disk cache for fast subsequent opens.
Future<List<EpgProgram>> fetchPrograms(
  String epgUrl,
  String channelName,
) async {
  final target = normalizeChannelNameLoose(channelName);
  if (target.isEmpty) return [];
  final cacheKey = "$epgUrl|$target";
  final cachedAt = _programCacheAt[cacheKey];
  if (_programCache.containsKey(cacheKey) &&
      cachedAt != null &&
      DateTime.now().difference(cachedAt) < const Duration(minutes: 10)) {
    return _programCache[cacheKey]!;
  }
  final fromDisk = await _readProgramDisk(cacheKey);
  if (fromDisk != null) {
    _programCache[cacheKey] = fromDisk;
    _programCacheAt[cacheKey] = DateTime.now();
    return fromDisk;
  }
  final raw = await compute(_downloadAndParsePrograms, {
    'url': epgUrl,
    'target': target,
  });
  final programs = raw.map(_programFromMap).toList();
  _programCache[cacheKey] = programs;
  _programCacheAt[cacheKey] = DateTime.now();
  await _writeProgramDisk(cacheKey, raw);
  return programs;
}

EpgProgram _programFromMap(Map<String, dynamic> m) => EpgProgram(
  DateTime.fromMillisecondsSinceEpoch(m['s'] as int, isUtc: true),
  DateTime.fromMillisecondsSinceEpoch(m['e'] as int, isUtc: true),
  m['t'] as String,
);

// Runs in a background isolate (via compute). Returns serializable maps.
Future<List<Map<String, dynamic>>> _downloadAndParsePrograms(
  Map<String, String> args,
) async {
  final epgUrl = args['url']!;
  final target = args['target']!;
  final client = http.Client();
  try {
    final response = await client.send(http.Request('GET', Uri.parse(epgUrl)));
    if (response.statusCode != 200) {
      throw Exception('Failed to download EPG: ${response.statusCode}');
    }
    Stream<List<int>> bytes = response.stream;
    if (epgUrl.endsWith('.gz')) {
      bytes = bytes.transform(gzip.decoder);
    }
    final ids = <String>{};
    final out = <Map<String, dynamic>>[];
    final current = StringBuffer();
    await for (final line in bytes
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      current.writeln(line);
      if (line.contains('</channel>')) {
        final block = current.toString();
        current.clear();
        final id = _channelIdRegex.firstMatch(block)?.group(1);
        if (id != null) {
          for (final dn in _displayNameRegex.allMatches(block)) {
            if (normalizeChannelNameLoose(
                  (dn.group(1) ?? '').replaceAll(_tagRegex, ''),
                ) ==
                target) {
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
        final title = (_titleRegex.firstMatch(block)?.group(1) ?? '')
            .replaceAll(_tagRegex, '')
            .trim();
        out.add({
          's': start.millisecondsSinceEpoch,
          'e': stop.millisecondsSinceEpoch,
          't': _unescapeXml(title),
        });
      }
    }
    return out;
  } finally {
    client.close();
  }
}

Future<File> _programCacheFile(String key) async {
  final dir = await getTemporaryDirectory();
  return File('${dir.path}/epg_prog_${key.hashCode}.json');
}

Future<List<EpgProgram>?> _readProgramDisk(String key) async {
  try {
    final f = await _programCacheFile(key);
    if (!await f.exists()) return null;
    if (DateTime.now().difference(await f.lastModified()) >
        const Duration(hours: 6)) {
      return null;
    }
    final data = jsonDecode(await f.readAsString()) as List;
    return data
        .map((m) => _programFromMap(Map<String, dynamic>.from(m as Map)))
        .toList();
  } catch (_) {
    return null;
  }
}

Future<void> _writeProgramDisk(String key, List<Map<String, dynamic>> raw) async {
  try {
    final f = await _programCacheFile(key);
    await f.writeAsString(jsonEncode(raw));
  } catch (_) {}
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
