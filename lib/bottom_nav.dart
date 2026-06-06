import 'package:flutter/material.dart';
import 'package:open_tv/l10n/strings.dart';
import 'package:open_tv/models/view_type.dart';
import 'package:open_tv/settings_view.dart';

class BottomNav extends StatefulWidget {
  final Function(ViewType) updateViewMode;
  final ViewType startingView;
  final bool blockSettings;
  const BottomNav({
    super.key,
    required this.updateViewMode,
    this.startingView = ViewType.all,
    this.blockSettings = false,
  });

  @override
  State<BottomNav> createState() => _BottomNavState();
}

class _BottomNavState extends State<BottomNav> {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    setState(() {
      _selectedIndex = widget.startingView.index;
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  void onBarTapped(int index) {
    if (widget.blockSettings && index == ViewType.settings.index) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(S.of(context).settingsDisabledRefreshing),
        ),
      );
      return;
    }
    setState(() {
      _selectedIndex = index;
    });
    if (_selectedIndex == ViewType.settings.index) {
      Navigator.pushAndRemoveUntil(
        context,
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const SettingsView(),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          transitionsBuilder: (context, animation, secondaryAnimation, child) =>
              child,
        ),
        (route) => false,
      );
      return;
    }
    widget.updateViewMode(ViewType.values[_selectedIndex]);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceBright,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).colorScheme.surfaceBright,
            width: 1,
          ),
        ),
      ),
      child: NavigationBar(
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.list),
            label: S.of(context).all,
          ),
          NavigationDestination(
            icon: const Icon(Icons.dashboard),
            label: S.of(context).categories,
          ),
          NavigationDestination(
            icon: const Icon(Icons.star),
            label: S.of(context).favorites,
          ),
          NavigationDestination(
            icon: const Icon(Icons.history),
            label: S.of(context).history,
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings),
            label: S.of(context).settings,
          ),
        ],
        selectedIndex: _selectedIndex,
        onDestinationSelected: onBarTapped,
      ),
    );
  }
}
