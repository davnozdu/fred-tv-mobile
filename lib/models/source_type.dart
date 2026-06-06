enum SourceType { xtream, m3uUrl, m3u, hlsProxy }

extension SourceTypeExtension on SourceType {
  String get label {
    switch (this) {
      case SourceType.m3u:
        return "M3U";
      case SourceType.m3uUrl:
        return "M3U Url";
      case SourceType.xtream:
        return "Xtream";
      case SourceType.hlsProxy:
        return "HLS-PROXY";
    }
  }
}
