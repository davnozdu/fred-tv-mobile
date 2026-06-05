import 'package:flutter/foundation.dart';

Set<int> refreshedSeries = {};

/// Normalized channel name -> programme currently airing (from EPG).
/// Updated in the background; channel tiles listen to it for a "now playing" line.
final ValueNotifier<Map<String, String>> nowPlaying = ValueNotifier({});
DateTime? nowPlayingAt;
