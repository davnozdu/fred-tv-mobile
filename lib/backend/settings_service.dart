import 'dart:collection';
import 'dart:convert';

import 'package:open_tv/backend/sql.dart';
import 'package:open_tv/models/settings.dart';
import 'package:open_tv/models/view_type.dart';

const defaultView = "defaultView";
const refreshOnStart = "refreshOnStart";
const showLivestreams = "showLivestreams";
const showMovies = "showMovies";
const showSeries = "showSeries";
const forceTvMode = "forceTVMode";
const lowLatencyProp = "streamCaching";
const fillLogosFromEpgProp = "fillLogosFromEpg";
const epgUrlProp = "epgUrl";
const bufferSecondsProp = "bufferSeconds";
const extendedArchiveProp = "extendedArchive";
const hiddenCategoriesProp = "hiddenCategories";
const categoryPinsProp = "categoryPins";
const inactivityMinutesProp = "inactivityMinutes";

class SettingsService {
  static Future<Settings> getSettings() async {
    var settingsMap = await Sql.getSettings();
    var settings = Settings();
    var view = settingsMap[defaultView];
    var refresh = settingsMap[refreshOnStart];
    var live = settingsMap[showLivestreams];
    var movies = settingsMap[showMovies];
    var series = settingsMap[showSeries];
    var forceTV = settingsMap[forceTvMode];
    var lowLatency = settingsMap[lowLatencyProp];
    var fillLogos = settingsMap[fillLogosFromEpgProp];
    var epg = settingsMap[epgUrlProp];
    var buffer = settingsMap[bufferSecondsProp];
    var extArchive = settingsMap[extendedArchiveProp];
    var hidden = settingsMap[hiddenCategoriesProp];
    var pins = settingsMap[categoryPinsProp];
    var inactivity = settingsMap[inactivityMinutesProp];
    if (view != null) {
      settings.defaultView = ViewType.values[int.parse(view)];
    }
    if (refresh != null) {
      settings.refreshOnStart = int.parse(refresh) == 1;
    }
    if (live != null) {
      settings.showLivestreams = int.parse(live) == 1;
    }
    if (movies != null) {
      settings.showMovies = int.parse(movies) == 1;
    }
    if (series != null) {
      settings.showSeries = int.parse(series) == 1;
    }
    if (forceTV != null) {
      settings.forceTVMode = int.parse(forceTV) == 1;
    }
    if (lowLatency != null) {
      settings.lowLatency = int.parse(lowLatency) == 1;
    }
    if (fillLogos != null) {
      settings.fillLogosFromEpg = int.parse(fillLogos) == 1;
    }
    if (epg != null) {
      settings.epgUrl = epg;
    }
    if (buffer != null) {
      settings.bufferSeconds = int.parse(buffer);
    }
    if (extArchive != null) {
      settings.extendedArchive = int.parse(extArchive) == 1;
    }
    if (hidden != null && hidden.isNotEmpty) {
      try {
        settings.hiddenCategories =
            (jsonDecode(hidden) as List).map((e) => e as String).toSet();
      } catch (_) {}
    }
    if (pins != null && pins.isNotEmpty) {
      try {
        settings.categoryPins = (jsonDecode(pins) as Map)
            .map((k, v) => MapEntry(k as String, v as String));
      } catch (_) {}
    }
    if (inactivity != null) {
      settings.inactivityMinutes = int.parse(inactivity);
    }
    return settings;
  }

  static Future<void> updateSettings(Settings settings) async {
    HashMap<String, String> settingsMap = HashMap();
    settingsMap[defaultView] = settings.defaultView.index.toString();
    settingsMap[refreshOnStart] = (settings.refreshOnStart ? 1 : 0).toString();
    settingsMap[showLivestreams] = (settings.showLivestreams ? 1 : 0)
        .toString();
    settingsMap[showMovies] = (settings.showMovies ? 1 : 0).toString();
    settingsMap[showSeries] = (settings.showSeries ? 1 : 0).toString();
    settingsMap[forceTvMode] = (settings.forceTVMode ? 1 : 0).toString();
    settingsMap[lowLatencyProp] = (settings.lowLatency ? 1 : 0).toString();
    settingsMap[fillLogosFromEpgProp] = (settings.fillLogosFromEpg ? 1 : 0)
        .toString();
    settingsMap[epgUrlProp] = settings.epgUrl;
    settingsMap[bufferSecondsProp] = settings.bufferSeconds.toString();
    settingsMap[extendedArchiveProp] = (settings.extendedArchive ? 1 : 0)
        .toString();
    settingsMap[hiddenCategoriesProp] =
        jsonEncode(settings.hiddenCategories.toList());
    settingsMap[categoryPinsProp] = jsonEncode(settings.categoryPins);
    settingsMap[inactivityMinutesProp] = settings.inactivityMinutes.toString();
    await Sql.updateSettings(settingsMap);
  }
}
