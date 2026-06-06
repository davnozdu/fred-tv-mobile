import 'package:flutter/material.dart';
import 'package:open_tv/backend/settings_service.dart';
import 'package:open_tv/backend/sql.dart';
import 'package:open_tv/category_colors.dart';
import 'package:open_tv/category_icons.dart';
import 'package:open_tv/error.dart';
import 'package:open_tv/home.dart';
import 'package:open_tv/menu_tile.dart';
import 'package:open_tv/models/channel.dart';
import 'package:open_tv/models/filters.dart';
import 'package:open_tv/models/home_manager.dart';
import 'package:open_tv/models/settings.dart';
import 'package:open_tv/models/view_type.dart';
import 'package:open_tv/pin_dialog.dart';
import 'package:open_tv/l10n/strings.dart';

/// "Channels" screen for TV: shows an "All" tile plus one tile per playlist
/// category (group). Tapping "All" opens every channel, tapping a category
/// opens only that category's channels.
class TvCategories extends StatefulWidget {
  const TvCategories({super.key});

  @override
  State<TvCategories> createState() => _TvCategoriesState();
}

class _TvCategoriesState extends State<TvCategories> {
  List<Channel> groups = [];
  List<int> sourceIds = [];
  Settings _settings = Settings();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await Error.tryAsyncNoLoading(() async {
      final sources = await Sql.getEnabledSourcesMinimal();
      sourceIds = sources.map((x) => x.id).toList();
      _settings = await SettingsService.getSettings();
      final mediaTypes = _settings.getMediaTypes();
      final List<Channel> all = [];
      var page = 1;
      while (true) {
        final batch = await Sql.search(
          Filters(
            viewType: ViewType.categories,
            sourceIds: sourceIds,
            mediaTypes: mediaTypes,
            page: page,
          ),
        );
        all.addAll(batch);
        if (batch.length < 36) break;
        page++;
      }
      // Drop categories the user chose to hide.
      all.removeWhere((g) => _settings.hiddenCategories.contains(g.name));
      if (mounted) {
        setState(() => groups = all);
      }
    }, context);
  }

  // Opens a category, asking for the PIN first if it is parental-locked.
  Future<void> _openCategory(Channel group) async {
    final pin = _settings.categoryPins[group.name];
    if (pin != null && pin.isNotEmpty) {
      final ok = await verifyPinDialog(
        context,
        pin,
        title: S.of(context).enterPinToOpen,
      );
      if (!ok) return;
    }
    _navigateHome(
      Filters(
        viewType: ViewType.all,
        sourceIds: sourceIds,
        groupId: group.id,
      ),
    );
  }

  void _navigateHome(Filters filters) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) =>
            Home(home: HomeManager(filters: filters), hasTouchScreen: false),
      ),
    );
  }

  List<Widget> _tiles() {
    final tiles = <Widget>[
      MenuTile(
        autofocus: true,
        icon: Icons.list,
        label: S.of(context).all,
        color: const LinearGradient(
          colors: [Colors.blueGrey, Colors.blue],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        onTap: () =>
            _navigateHome(Filters(viewType: ViewType.all, sourceIds: sourceIds)),
      ),
    ];
    for (final group in groups) {
      final locked = _settings.categoryPins[group.name]?.isNotEmpty ?? false;
      // Locked categories show a padlock; otherwise the matched category icon.
      final asset = locked ? null : categoryIconAsset(group.name);
      tiles.add(
        MenuTile(
          icon: locked ? Icons.lock : Icons.folder,
          imageAsset: asset,
          label: group.name,
          color: categoryGradient(group.name),
          onTap: () => _openCategory(group),
        ),
      );
    }
    return tiles;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Wrap(alignment: WrapAlignment.center, children: _tiles()),
          ),
        ),
      ),
    );
  }
}
