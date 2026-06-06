import 'package:flutter/material.dart';
import 'package:open_tv/backend/settings_service.dart';
import 'package:open_tv/backend/sql.dart';
import 'package:open_tv/backend/utils.dart';
import 'package:open_tv/bottom_nav.dart';
import 'package:open_tv/confirm_delete.dart';
import 'package:open_tv/models/filters.dart';
import 'package:open_tv/select_dialog.dart';
import 'package:open_tv/edit_dialog.dart';
import 'package:open_tv/home.dart';
import 'package:open_tv/loading.dart';
import 'package:open_tv/models/home_manager.dart';
import 'package:open_tv/models/id_data.dart';
import 'package:open_tv/models/settings.dart';
import 'package:open_tv/models/source.dart';
import 'package:open_tv/models/source_type.dart';
import 'package:open_tv/models/view_type.dart';
import 'package:open_tv/backend/updater.dart';
import 'package:open_tv/error.dart';
import 'package:open_tv/l10n/strings.dart';
import 'package:open_tv/main.dart';
import 'package:open_tv/setup.dart';

class SettingsView extends StatefulWidget {
  final bool showNavBar;

  const SettingsView({super.key, this.showNavBar = true});

  @override
  State<SettingsView> createState() => _SettingsState();
}

class _SettingsState extends State<SettingsView> {
  Settings settings = Settings();
  List<Source> sources = [];
  bool loading = true;
  @override
  void initState() {
    super.initState();
    initAsync();
  }

  Future<void> initAsync() async {
    var results = await Future.wait([
      SettingsService.getSettings(),
      Sql.getSources(),
    ]);
    setState(() {
      settings = results[0] as Settings;
      sources = results[1] as List<Source>;
      loading = false;
    });
  }

  void updateView(ViewType view) {
    if (view != ViewType.settings) {
      Navigator.pushAndRemoveUntil(
        context,
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => Home(
            home: HomeManager(filters: Filters(viewType: view)),
          ),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          transitionsBuilder: (context, animation, secondaryAnimation, child) =>
              child,
        ),
        (route) => false,
      );
    }
  }

  Future<void> showEditDialog(BuildContext context, final Source source) async {
    await showDialog(
      barrierDismissible: true,
      context: context,
      builder: (builder) =>
          EditDialog(source: source, afterSave: reloadSources),
    );
  }

  String _viewLabel(BuildContext context, ViewType v) {
    final s = S.of(context);
    switch (v) {
      case ViewType.all:
        return s.all;
      case ViewType.categories:
        return s.categories;
      case ViewType.favorites:
        return s.favorites;
      case ViewType.history:
        return s.history;
      default:
        return s.all;
    }
  }

  Future<void> _showDefaultViewDialog(BuildContext context) async {
    showDialog(
      barrierDismissible: true,
      context: context,
      builder: (BuildContext context) {
        return SelectDialog(
          title: S.of(context).defaultView,
          data: ViewType.values
              .take(4)
              .map((x) => IdData(id: x.index, data: _viewLabel(context, x)))
              .toList(),
          action: (view) {
            setState(() {
              settings.defaultView = ViewType.values[view];
              updateSettings();
            });
            Navigator.of(context).pop();
          },
        );
      },
    );
  }

  Future<void> toggleSource(Source source) async {
    await Error.tryAsyncNoLoading(
      () async => await Sql.setSourceEnabled(!source.enabled, source.id!),
      context,
    );
    await reloadSources();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(S.of(context).sourceToggled(!source.enabled)),
        duration: const Duration(milliseconds: 500),
      ),
    );
  }

  Widget getSource(Source source) {
    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 5,
      ), // Spacing around the tile
      elevation: 5,
      child: ListTile(
        leading: Icon(source.enabled ? Icons.tv : Icons.tv_off),
        horizontalTitleGap: 25,
        onLongPress: () => toggleSource(source),
        contentPadding: const EdgeInsets.only(left: 20),
        title: Text(source.name),
        subtitle: Text(source.sourceType.label),
        trailing: Row(
          mainAxisSize:
              MainAxisSize.min, // Ensures the row takes up minimal space
          children: [
            Offstage(
              offstage: source.sourceType == SourceType.m3u,
              child: IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () async {
                  await Error.tryAsync(
                    () async {
                      await Utils.refreshSource(source);
                    },
                    context,
                    S.of(context).sourceRefreshed,
                  );
                },
              ),
            ),
            Offstage(
              offstage: source.sourceType == SourceType.m3u,
              child: IconButton(
                icon: const Icon(Icons.edit),
                onPressed: () async => await showEditDialog(context, source),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () async => await showConfirmDeleteDialog(source),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> showConfirmDeleteDialog(Source source) async {
    await showDialog(
      barrierDismissible: true,
      context: context,
      builder: (builder) => ConfirmDelete(
        type: S.of(context).sourceType,
        name: source.name,
        confirm: () async {
          await Error.tryAsync(
            () async => await Sql.deleteSource(source.id!),
            context,
            S.of(context).sourceDeleted,
          );
          await reloadSources();
          if (sources.isEmpty) {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (context) => const Setup()),
              (route) => false,
            );
          }
        },
      ),
    );
  }

  Future<void> reloadSources() async {
    await Error.tryAsyncNoLoading(
      () async => sources = await Sql.getSources(),
      context,
    );
    setState(() {
      sources;
    });
  }

  Future<void> updateSettings() async {
    await Error.tryAsyncNoLoading(
      () async => await SettingsService.updateSettings(settings),
      context,
    );
  }

  Future<void> _showBufferDialog(BuildContext context) async {
    final loc = S.of(context);
    const options = [0, 5, 15, 30, 60];
    showDialog(
      barrierDismissible: true,
      context: context,
      builder: (BuildContext context) {
        return SelectDialog(
          title: loc.bufferSize,
          data: options
              .map(
                (s) => IdData(
                  id: s,
                  data: s == 0 ? loc.auto : "$s ${loc.seconds}",
                ),
              )
              .toList(),
          action: (seconds) {
            setState(() {
              settings.bufferSeconds = seconds;
              updateSettings();
            });
            Navigator.of(context).pop();
          },
        );
      },
    );
  }

  Future<void> _showEpgUrlDialog() async {
    final s = S.of(context);
    final controller = TextEditingController(text: settings.epgUrl);
    await showDialog(
      barrierDismissible: true,
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.epgUrl),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            hintText: "http://epg.one/epg.xml",
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(s.cancel),
          ),
          TextButton(
            onPressed: () {
              setState(() => settings.epgUrl = controller.text.trim());
              updateSettings();
              Navigator.of(ctx).pop();
            },
            child: Text(s.save),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      body: Visibility(
        visible: !loading,
        child: Loading(
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsetsDirectional.symmetric(vertical: 10),
              child: ListView(
                children: [
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: Text(
                      s.settings,
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  ListTile(
                    leading: const Icon(Icons.system_update),
                    title: Text(s.checkUpdate),
                    onTap: () => Updater.checkAndPrompt(
                      MyApp.navigatorKey,
                      manual: true,
                    ),
                  ),
                  ListTile(
                    title: Text(s.defaultView),
                    subtitle: Text(_viewLabel(context, settings.defaultView)),
                    onTap: () async => await _showDefaultViewDialog(context),
                  ),
                  ListTile(
                    title: Text(s.forceTvMode),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Switch(
                          value: settings.forceTVMode,
                          onChanged: (bool value) {
                            setState(() {
                              settings.forceTVMode = value;
                            });
                            updateSettings();
                          },
                        ),
                      ],
                    ),
                  ),
                  ListTile(
                    title: Text(s.lowLatency),
                    subtitle: Text(s.lowLatencySub),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Switch(
                          value: settings.lowLatency,
                          onChanged: (bool value) {
                            setState(() {
                              settings.lowLatency = value;
                            });
                            updateSettings();
                          },
                        ),
                      ],
                    ),
                  ),
                  ListTile(
                    enabled: !settings.lowLatency,
                    title: Text(s.bufferSize),
                    subtitle: Text(
                      settings.bufferSeconds <= 0
                          ? s.bufferAutoSub
                          : s.bufferSecondsSub(settings.bufferSeconds),
                    ),
                    onTap: () async => await _showBufferDialog(context),
                  ),
                  ListTile(
                    title: Text(s.extendedArchive),
                    subtitle: Text(s.extendedArchiveSub),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Switch(
                          value: settings.extendedArchive,
                          onChanged: (bool value) {
                            setState(() {
                              settings.extendedArchive = value;
                            });
                            updateSettings();
                          },
                        ),
                      ],
                    ),
                  ),
                  ListTile(
                    title: Text(s.refreshOnStart),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Switch(
                          value: settings.refreshOnStart,
                          onChanged: (bool value) {
                            setState(() {
                              settings.refreshOnStart = value;
                            });
                            updateSettings();
                          },
                        ),
                      ],
                    ),
                  ),
                  ListTile(
                    title: Text(s.showLivestreams),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Switch(
                          value: settings.showLivestreams,
                          onChanged: (bool value) {
                            setState(() {
                              settings.showLivestreams = value;
                            });
                            updateSettings();
                          },
                        ),
                      ],
                    ),
                  ),
                  ListTile(
                    title: Text(s.showMovies),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Switch(
                          value: settings.showMovies,
                          onChanged: (bool value) {
                            setState(() {
                              settings.showMovies = value;
                            });
                            updateSettings();
                          },
                        ),
                      ],
                    ),
                  ),
                  ListTile(
                    title: Text(s.showSeries),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Switch(
                          value: settings.showSeries,
                          onChanged: (bool value) {
                            setState(() {
                              settings.showSeries = value;
                            });
                            updateSettings();
                          },
                        ),
                      ],
                    ),
                  ),
                  ListTile(
                    title: Text(s.fillLogos),
                    subtitle: Text(s.fillLogosSub),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Switch(
                          value: settings.fillLogosFromEpg,
                          onChanged: (bool value) {
                            setState(() {
                              settings.fillLogosFromEpg = value;
                            });
                            updateSettings();
                          },
                        ),
                      ],
                    ),
                  ),
                  ListTile(
                    enabled: settings.fillLogosFromEpg,
                    title: Text(s.epgUrl),
                    subtitle: Text(
                      settings.epgUrl.isEmpty ? s.notSet : settings.epgUrl,
                    ),
                    onTap: () async => await _showEpgUrlDialog(),
                  ),
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 10),
                        child: Text(
                          s.sources,
                          style: const TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          IconButton(
                            onPressed: () async => await Error.tryAsync(
                              () async => await Utils.refreshAllSources(),
                              context,
                              S.of(context).sourcesRefreshed,
                            ),
                            icon: const Icon(Icons.refresh),
                          ),
                          IconButton(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const Setup(showAppBar: true),
                              ),
                            ),
                            icon: const Icon(Icons.add),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ...sources.map(getSource),
                ],
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: widget.showNavBar
          ? BottomNav(
              updateViewMode: updateView,
              startingView: ViewType.settings,
            )
          : null,
    );
  }
}
