import 'package:open_tv/models/media_type.dart';
import 'package:open_tv/models/view_type.dart';

class Settings {
  ViewType defaultView;
  bool refreshOnStart;
  bool showLivestreams;
  bool lowLatency;
  bool showMovies;
  bool showSeries;
  bool forceTVMode;
  bool fillLogosFromEpg;
  String epgUrl;
  int bufferSeconds;
  bool extendedArchive;
  // Categories the user chose to hide (by group name).
  Set<String> hiddenCategories;
  // Parental control: group name -> 4-digit PIN.
  Map<String, String> categoryPins;
  // Auto-pause playback after this many minutes of remote inactivity.
  // 0 = never (disabled).
  int inactivityMinutes;
  Settings({
    this.defaultView = ViewType.all,
    this.refreshOnStart = false,
    this.showLivestreams = true,
    this.lowLatency = false,
    this.showMovies = true,
    this.showSeries = true,
    this.forceTVMode = false,
    this.fillLogosFromEpg = true,
    this.epgUrl = 'http://epg.one/epg.xml',
    this.bufferSeconds = 0, // 0 = Auto (adaptive buffer)
    this.extendedArchive = false, // false = 1-day (epg.one), true = 7-day (iptvx)
    Set<String>? hiddenCategories,
    Map<String, String>? categoryPins,
    this.inactivityMinutes = 180, // default: 3 hours
  })  : hiddenCategories = hiddenCategories ?? <String>{},
        categoryPins = categoryPins ?? <String, String>{};

  List<MediaType> getMediaTypes() {
    return [
      if (showLivestreams) MediaType.livestream,
      if (showMovies) MediaType.movie,
      if (showSeries) MediaType.serie,
    ];
  }

  bool isHidden(String? group) =>
      group != null && hiddenCategories.contains(group);

  bool hasPin(String? group) =>
      group != null && (categoryPins[group]?.isNotEmpty ?? false);
}
