import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Disk cache for channel logos. The default cache only keeps ~200 files and
/// expires them after a month; playlists routinely have many more channels, so
/// scrolling kept re-downloading logos. This keeps far more for longer, so
/// logos load instantly from disk (and survive app restarts).
class LogoCache {
  static const _key = 'smotrimLogos';

  static final CacheManager instance = CacheManager(
    Config(
      _key,
      stalePeriod: const Duration(days: 60),
      maxNrOfCacheObjects: 800,
    ),
  );
}
