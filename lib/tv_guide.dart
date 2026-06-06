import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_tv/backend/epg.dart';
import 'package:open_tv/backend/settings_service.dart';
import 'package:open_tv/backend/sql.dart';
import 'package:open_tv/error.dart';
import 'package:open_tv/models/channel.dart';
import 'package:open_tv/models/settings.dart';
import 'package:open_tv/player.dart';
import 'package:open_tv/l10n/strings.dart';

class _GuideRow {
  final Channel channel;
  final List<EpgProgram> programs;
  _GuideRow(this.channel, this.programs);
}

abstract class _Item {}

class _HeaderItem extends _Item {
  final String name;
  _HeaderItem(this.name);
}

class _RowItem extends _Item {
  final _GuideRow row;
  _RowItem(this.row);
}

/// Plex-style TV guide grid: channels grouped by category as rows, time across
/// the top, programmes as blocks. D-pad navigates cells; OK plays (live/archive).
class TvGuide extends StatefulWidget {
  const TvGuide({super.key});

  @override
  State<TvGuide> createState() => _TvGuideState();
}

class _TvGuideState extends State<TvGuide> {
  static const double pxPerMin = 6;
  static const double rowHeight = 64;
  static const double labelWidth = 160;
  static const double headerHeight = 28;

  final ScrollController _h = ScrollController();
  final ScrollController _vBody = ScrollController();
  final ScrollController _vLeft = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final FocusNode _searchFocus = FocusNode();
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounce;

  List<_GuideRow> _allRows = [];
  List<_Item> _items = [];
  List<int> _navRows = []; // indices in _items that are channel rows
  int _sel = 0; // index into _navRows
  int _col = 0;
  bool _loading = true;
  Settings _settings = Settings();

  late DateTime _windowStart;
  late DateTime _windowEnd;

  double get _totalWidth =>
      _windowEnd.difference(_windowStart).inMinutes * pxPerMin;

  _GuideRow? get _curRow {
    if (_navRows.isEmpty || _sel < 0 || _sel >= _navRows.length) return null;
    final item = _items[_navRows[_sel]];
    return item is _RowItem ? item.row : null;
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final flooredMin = now.minute < 30 ? 0 : 30;
    _windowStart = DateTime(now.year, now.month, now.day, now.hour, flooredMin)
        .subtract(const Duration(hours: 1));
    _windowEnd = _windowStart.add(const Duration(hours: 30));
    _vBody.addListener(() {
      if (_vLeft.hasClients && _vLeft.offset != _vBody.offset) {
        _vLeft.jumpTo(_vBody.offset);
      }
    });
    _searchFocus.onKeyEvent = (node, event) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.arrowDown) {
        _focusNode.requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _h.dispose();
    _vBody.dispose();
    _vLeft.dispose();
    _focusNode.dispose();
    _searchFocus.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    await Error.tryAsyncNoLoading(() async {
      _settings = await SettingsService.getSettings();
      final sources = await Sql.getEnabledSourcesMinimal();
      final channels = await Sql.getLivestreams(
        sources.map((x) => x.id).toList(),
      );
      final epgUrl = _settings.extendedArchive
          ? archiveEpgUrl
          : _settings.epgUrl.trim();
      final programsByName = await fetchAllPrograms(epgUrl);
      final rows = <_GuideRow>[];
      for (final c in channels) {
        final progs =
            programsByName[normalizeChannelNameLoose(c.name)] ?? const [];
        rows.add(_GuideRow(c, progs));
      }
      rows.sort((a, b) {
        final g = (a.channel.group ?? '').compareTo(b.channel.group ?? '');
        return g != 0 ? g : a.channel.name.compareTo(b.channel.name);
      });
      if (mounted) {
        setState(() {
          _allRows = rows;
          _buildItems("");
          _loading = false;
          _focusInitial();
        });
      }
    }, context);
    if (mounted && _loading) setState(() => _loading = false);
  }

  void _buildItems(String query) {
    final q = query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? _allRows
        : _allRows
              .where((r) => r.channel.name.toLowerCase().contains(q))
              .toList();
    final items = <_Item>[];
    String? lastGroup;
    for (final r in filtered) {
      final g = (r.channel.group ?? '').trim();
      if (g != lastGroup) {
        items.add(_HeaderItem(g.isEmpty ? "" : g));
        lastGroup = g;
      }
      items.add(_RowItem(r));
    }
    _items = items;
    _navRows = [
      for (var i = 0; i < _items.length; i++)
        if (_items[i] is _RowItem) i,
    ];
    _sel = 0;
    _col = 0;
  }

  void _focusInitial() {
    final row = _curRow;
    if (row == null) return;
    final now = DateTime.now();
    var idx = row.programs.indexWhere(
      (p) => !p.start.isAfter(now) && p.stop.isAfter(now),
    );
    if (idx < 0) idx = 0;
    _col = idx;
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToFocused());
  }

  void _scrollToFocused() {
    if (_navRows.isEmpty) return;
    const animate = Duration(milliseconds: 200);
    final itemIndex = _navRows[_sel];
    if (_vBody.hasClients) {
      final maxV = _vBody.position.maxScrollExtent;
      final vTarget = (itemIndex * rowHeight - 2 * rowHeight)
          .clamp(0.0, maxV)
          .toDouble();
      _vBody.animateTo(vTarget, duration: animate, curve: Curves.easeOut);
    }
    final progs = _curRow?.programs ?? const [];
    if (_h.hasClients && _col >= 0 && _col < progs.length) {
      final maxH = _h.position.maxScrollExtent;
      final x = progs[_col].start.difference(_windowStart).inMinutes * pxPerMin;
      final hTarget = (x - labelWidth).clamp(0.0, maxH).toDouble();
      _h.animateTo(hTarget, duration: animate, curve: Curves.easeOut);
    }
  }

  int _clampCol(int col) {
    final len = _curRow?.programs.length ?? 0;
    if (len == 0) return 0;
    if (col < 0) return 0;
    if (col > len - 1) return len - 1;
    return col;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (_navRows.isEmpty) return KeyEventResult.ignored;
    final k = event.logicalKey;
    if (k == LogicalKeyboardKey.arrowDown) {
      if (_sel < _navRows.length - 1) {
        setState(() {
          _sel++;
          _col = _clampCol(_col);
        });
        _scrollToFocused();
      }
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp) {
      if (_sel > 0) {
        setState(() {
          _sel--;
          _col = _clampCol(_col);
        });
        _scrollToFocused();
      } else {
        _searchFocus.requestFocus(); // top row -> search box
      }
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowRight) {
      if (_col < (_curRow?.programs.length ?? 0) - 1) {
        setState(() => _col++);
        _scrollToFocused();
      }
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowLeft) {
      if (_col > 0) {
        setState(() => _col--);
        _scrollToFocused();
      }
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.select ||
        k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.mediaPlayPause) {
      _openFocused();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _openFocused() {
    final row = _curRow;
    if (row == null || _col < 0 || _col >= row.programs.length) return;
    final p = row.programs[_col];
    final now = DateTime.now();
    if (p.start.isAfter(now)) return; // future
    final isLive = !p.start.isAfter(now) && p.stop.isAfter(now);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Player(
          channel: row.channel,
          settings: _settings,
          archiveStart: isLive ? null : p.start,
        ),
      ),
    );
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      setState(() => _buildItems(value));
      if (_vBody.hasClients) _vBody.jumpTo(0);
      if (_h.hasClients) _h.jumpTo(0);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            _searchBar(),
            Expanded(
              child: Focus(
                focusNode: _focusNode,
                autofocus: true,
                onKeyEvent: _onKey,
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      )
                    : _items.isEmpty
                    ? const Center(
                        child: Text(
                          S.of(context).noGuideData,
                          style: TextStyle(color: Colors.white70),
                        ),
                      )
                    : _buildGrid(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: TextField(
        controller: _searchCtrl,
        focusNode: _searchFocus,
        style: const TextStyle(color: Colors.white),
        onChanged: _onSearch,
        decoration: InputDecoration(
          isDense: true,
          hintText: S.of(context).searchChannels,
          hintStyle: const TextStyle(color: Colors.white38),
          prefixIcon: const Icon(Icons.search, color: Colors.white54),
          filled: true,
          fillColor: Colors.white10,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildGrid() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: labelWidth,
          child: Column(
            children: [
              SizedBox(height: headerHeight, child: Container(color: Colors.black)),
              Expanded(
                child: ListView.builder(
                  controller: _vLeft,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _items.length,
                  itemExtent: rowHeight,
                  itemBuilder: (_, i) => _leftCell(i),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            controller: _h,
            physics: const NeverScrollableScrollPhysics(),
            child: SizedBox(
              width: _totalWidth,
              child: Column(
                children: [
                  SizedBox(height: headerHeight, child: _timeHeader()),
                  Expanded(
                    child: Stack(
                      children: [
                        ListView.builder(
                          controller: _vBody,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _items.length,
                          itemExtent: rowHeight,
                          itemBuilder: (_, i) => _bodyCell(i),
                        ),
                        _nowLine(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _leftCell(int i) {
    final item = _items[i];
    if (item is _HeaderItem) {
      return Container(
        color: Colors.white12,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.centerLeft,
        child: Text(
          item.name.isEmpty ? S.of(context).other : item.name,
          style: const TextStyle(
            color: Colors.amber,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }
    final focused = _navRows.isNotEmpty && i == _navRows[_sel];
    return Container(
      decoration: BoxDecoration(
        color: focused ? Colors.white12 : Colors.transparent,
        border: const Border(
          bottom: BorderSide(color: Colors.white10),
          right: BorderSide(color: Colors.white24),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.centerLeft,
      child: Text(
        (item as _RowItem).row.channel.name,
        style: const TextStyle(color: Colors.white, fontSize: 13),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _bodyCell(int i) {
    final item = _items[i];
    if (item is _HeaderItem) {
      return SizedBox(
        width: _totalWidth,
        height: rowHeight,
        child: Container(color: Colors.white10),
      );
    }
    final row = (item as _RowItem).row;
    final isFocusedRow = _navRows.isNotEmpty && i == _navRows[_sel];
    final children = <Widget>[];
    for (var j = 0; j < row.programs.length; j++) {
      final p = row.programs[j];
      final left = p.start.difference(_windowStart).inMinutes * pxPerMin;
      var width = p.stop.difference(p.start).inMinutes * pxPerMin;
      if (width < 24) width = 24;
      final focused = isFocusedRow && j == _col;
      children.add(
        Positioned(
          left: left,
          top: 3,
          bottom: 3,
          width: width,
          child: Container(
            decoration: BoxDecoration(
              color: focused ? Colors.blue : Colors.white10,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: focused ? Colors.white : Colors.white24,
                width: focused ? 2 : 1,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            alignment: Alignment.centerLeft,
            child: Text(
              p.title.isEmpty ? "—" : p.title,
              style: const TextStyle(color: Colors.white, fontSize: 12),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      );
    }
    return SizedBox(
      width: _totalWidth,
      height: rowHeight,
      child: Stack(children: children),
    );
  }

  Widget _timeHeader() {
    final marks = <Widget>[];
    var t = _windowStart;
    while (t.isBefore(_windowEnd)) {
      final left = t.difference(_windowStart).inMinutes * pxPerMin;
      final msk = epgLocal(t.toUtc()); // show Moscow time (matches the EPG)
      marks.add(
        Positioned(
          left: left,
          top: 4,
          child: Text(
            "${msk.hour.toString().padLeft(2, '0')}:${msk.minute.toString().padLeft(2, '0')}",
            style: const TextStyle(color: Colors.white60, fontSize: 12),
          ),
        ),
      );
      t = t.add(const Duration(minutes: 30));
    }
    return Stack(children: marks);
  }

  Widget _nowLine() {
    final now = DateTime.now();
    if (now.isBefore(_windowStart) || now.isAfter(_windowEnd)) {
      return const SizedBox.shrink();
    }
    final left = now.difference(_windowStart).inMinutes * pxPerMin;
    return Positioned(
      left: left,
      top: 0,
      bottom: 0,
      child: Container(width: 2, color: Colors.redAccent),
    );
  }
}
