import 'package:flutter/material.dart';
import 'package:open_tv/backend/settings_service.dart';
import 'package:open_tv/backend/sql.dart';
import 'package:open_tv/category_colors.dart';
import 'package:open_tv/error.dart';
import 'package:open_tv/l10n/strings.dart';
import 'package:open_tv/models/settings.dart';
import 'package:open_tv/pin_dialog.dart';

/// Lists every playlist category with a hide toggle and a parental-control
/// (PIN) action. Hidden categories disappear from the Channels screen and the
/// Guide; PIN-locked categories require the PIN to open.
class CategorySettings extends StatefulWidget {
  const CategorySettings({super.key});

  @override
  State<CategorySettings> createState() => _CategorySettingsState();
}

class _CategorySettingsState extends State<CategorySettings> {
  Settings _settings = Settings();
  List<String> _categories = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await Error.tryAsyncNoLoading(() async {
      final results = await Future.wait([
        SettingsService.getSettings(),
        Sql.getAllGroupNames(),
      ]);
      if (!mounted) return;
      setState(() {
        _settings = results[0] as Settings;
        _categories = results[1] as List<String>;
        _loading = false;
      });
    }, context);
    if (mounted && _loading) setState(() => _loading = false);
  }

  Future<void> _save() async {
    await SettingsService.updateSettings(_settings);
  }

  void _toggleHidden(String name, bool hidden) {
    setState(() {
      if (hidden) {
        _settings.hiddenCategories.add(name);
      } else {
        _settings.hiddenCategories.remove(name);
      }
    });
    _save();
  }

  Future<void> _setPin(String name) async {
    final pin = await setPinDialog(context);
    if (pin == null) return;
    setState(() => _settings.categoryPins[name] = pin);
    await _save();
    if (mounted) Error.showSuccess(context, S.of(context).pinSet);
  }

  Future<void> _resetPin(String name) async {
    final current = _settings.categoryPins[name];
    if (current == null) return;
    final ok = await verifyPinDialog(context, current);
    if (!ok) return;
    setState(() => _settings.categoryPins.remove(name));
    await _save();
    if (mounted) Error.showSuccess(context, S.of(context).pinRemoved);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.hideCategories)),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _categories.isEmpty
                ? Center(child: Text(s.noCategories))
                : ListView.builder(
                    itemCount: _categories.length,
                    itemBuilder: (_, i) => _row(_categories[i], s),
                  ),
      ),
    );
  }

  Widget _row(String name, S s) {
    final hidden = _settings.hiddenCategories.contains(name);
    final hasPin = _settings.categoryPins[name]?.isNotEmpty ?? false;
    return ListTile(
      leading: Container(
        width: 12,
        height: 40,
        decoration: BoxDecoration(
          gradient: categoryGradient(name),
          borderRadius: BorderRadius.circular(4),
        ),
      ),
      title: Text(name),
      subtitle: hasPin
          ? Row(
              children: [
                const Icon(Icons.lock, size: 14, color: Colors.amber),
                const SizedBox(width: 4),
                Text(s.locked, style: const TextStyle(color: Colors.amber)),
              ],
            )
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(
              hasPin ? Icons.lock : Icons.lock_open,
              color: hasPin ? Colors.amber : null,
            ),
            tooltip: hasPin ? s.resetPin : s.setPin,
            onPressed: () => hasPin ? _resetPin(name) : _setPin(name),
          ),
          Switch(
            // "on" = visible; toggling off hides the category.
            value: !hidden,
            onChanged: (v) => _toggleHidden(name, !v),
          ),
        ],
      ),
    );
  }
}
