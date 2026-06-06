import 'package:flutter/material.dart';
import 'package:open_tv/home.dart';
import 'package:open_tv/menu_tile.dart';
import 'package:open_tv/models/filters.dart';
import 'package:open_tv/models/home_manager.dart';
import 'package:open_tv/models/view_type.dart';
import 'package:open_tv/settings_view.dart';
import 'package:open_tv/tv_categories.dart';
import 'package:open_tv/tv_guide.dart';
import 'package:open_tv/l10n/strings.dart';

class TvHome extends StatelessWidget {
  const TvHome({super.key});

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
    return Scaffold(
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
    );
  }
}
