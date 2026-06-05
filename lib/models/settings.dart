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
  });

  List<MediaType> getMediaTypes() {
    return [
      if (showLivestreams) MediaType.livestream,
      if (showMovies) MediaType.movie,
      if (showSeries) MediaType.serie,
    ];
  }
}
