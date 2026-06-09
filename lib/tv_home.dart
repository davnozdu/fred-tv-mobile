import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_tv/backend/launch_bridge.dart';
import 'package:open_tv/backend/settings_service.dart';
import 'package:open_tv/backend/sql.dart';
import 'package:open_tv/home.dart';
import 'package:open_tv/menu_tile.dart';
import 'package:open_tv/models/autostart_action.dart';
import 'package:open_tv/models/channel.dart';
import 'package:open_tv/models/filters.dart';
import 'package:open_tv/models/home_manager.dart';
import 'package:open_tv/models/settings.dart';
import 'package:open_tv/models/view_type.dart';
import 'package:open_tv/player.dart';
import 'package:open_tv/settings_view.dart';
import 'package:open_tv/tv_categories.dart';
import 'package:open_tv/tv_guide.dart';
import 'package:open_tv/l10n/strings.dart';

class TvHome extends StatefulWidget {
  const TvHome({super.key});

  @override
  State<TvHome> createState() => _TvHomeState();
}

class _TvHomeState extends State<TvHome> {
  bool _autoOpened = false;
  DateTime? _lastBackAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoOpen());
  }

  // Decides what to play on launch: resume an interrupted stream, or run the
  // autostart action after a real device boot. Otherwise stays on the menu.
  Future<void> _autoOpen() async {
    if (_autoOpened) return;
    _autoOpened = true;
    try {
      final settings = await SettingsService.getSettings();
      // 1) Resume an interrupted stream (box powered off while watching).
      if (settings.resumePlayback) {
        final idStr = await Sql.getSetting('activeChannelId');
        if (idStr != null) {
          final ch = await Sql.getChannelById(int.parse(idStr));
          if (ch != null && ch.url != null) {
            _play(settings, ch);
            return;
          }
        }
      }
      // 2) Autostart action — only when actually launched from device boot.
      final fromBoot = await LaunchBridge.launchedFromBoot();
      if (!fromBoot || !settings.autostartOnBoot) return;
      switch (settings.autostartAction) {
        case AutostartAction.menu:
          break;
        case AutostartAction.lastChannel:
          final ch = await Sql.getLastWatchedChannel();
          if (ch != null) _play(settings, ch);
          break;
        case AutostartAction.category:
          final gid = settings.autostartCategoryId;
          if (gid != null) {
            final list = await Sql.getCategoryLivestreams(gid);
            if (list.isNotEmpty) _play(settings, list.first, list, 0);
          }
          break;
        case AutostartAction.channel:
          final cid = settings.autostartChannelId;
          if (cid != null) {
            final ch = await Sql.getChannelById(cid);
            if (ch != null && ch.url != null) _play(settings, ch);
          }
          break;
      }
    } catch (_) {}
  }

  void _play(Settings settings, Channel ch,
      [List<Channel>? playlist, int index = 0]) {
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Player(
          channel: ch,
          settings: settings,
          playlist: playlist,
          playlistIndex: index,
        ),
      ),
    );
  }

  void _navigateHome(BuildContext context, Filters filters) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) =>
            Home(home: HomeManager(filters: filters), hasTouchScreen: false),
      ),
    );
  }

  void _navChannels(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => const TvCategories()));
  }

  void _navGuide(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => const TvGuide()));
  }

  void _navSettings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => SettingsView(showNavBar: false)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        final now = DateTime.now();
        final last = _lastBackAt;
        // The Back key fires twice on this box (key shortcut + platform back);
        // ignore the duplicate that arrives within ~150ms of the first.
        if (last != null && now.difference(last) < const Duration(milliseconds: 150)) {
          return;
        }
        if (last != null && now.difference(last) < const Duration(seconds: 2)) {
          SystemNavigator.pop(); // genuine second press → exit
          return;
        }
        _lastBackAt = now;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(S.of(context).pressAgainToExit),
            duration: const Duration(seconds: 2),
          ),
        );
      },
      child: Scaffold(
        body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Wrap(
              alignment: WrapAlignment.center,
              children: [
                MenuTile(
                  autofocus: true,
                  icon: Icons.tv,
                  label: s.channels,
                  color: const LinearGradient(
                    colors: [Colors.blueGrey, Colors.blue],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  onTap: () => _navChannels(context),
                ),
                MenuTile(
                  icon: Icons.grid_view,
                  label: s.guide,
                  color: const LinearGradient(
                    colors: [Colors.indigo, Colors.deepPurple],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  onTap: () => _navGuide(context),
                ),
                MenuTile(
                  icon: Icons.star,
                  label: s.favorites,
                  color: LinearGradient(
                    colors: [Colors.orange.shade700, Colors.amber.shade400],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  onTap: () => _navigateHome(
                    context,
                    Filters(viewType: ViewType.favorites),
                  ),
                ),
                MenuTile(
                  icon: Icons.history,
                  label: s.history,
                  color: LinearGradient(
                    colors: [Colors.teal.shade700, Colors.green.shade400],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  onTap: () => _navigateHome(
                    context,
                    Filters(viewType: ViewType.history),
                  ),
                ),
                MenuTile(
                  icon: Icons.settings,
                  label: s.settings,
                  color: LinearGradient(
                    colors: [
                      Colors.blueGrey.shade800,
                      Colors.blueGrey.shade600,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  onTap: () => _navSettings(context),
                ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }
}
