import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_tv/backend/epg.dart';
import 'package:open_tv/backend/settings_service.dart';
import 'package:open_tv/backend/sql.dart';
import 'package:open_tv/error.dart';
import 'package:open_tv/models/channel.dart';
import 'package:open_tv/models/settings.dart';
import 'package:open_tv/player.dart';

class _GuideRow {
  final Channel channel;
  final List<EpgProgram> programs;
  _GuideRow(this.channel, this.programs);
}

/// Plex-style TV guide grid: channels as rows, time across the top,
/// programmes as blocks. D-pad navigates cells; OK plays (live/archive).
class TvGuide extends StatefulWidget {
  const TvGuide({super.key});

  @override
  State<TvGuide> createState() => _TvGuideState();
}

class _TvGuideState extends State<TvGuide> {
  static const double pxPerMin = 6;
  static const double rowHeight = 64;
  static const double labelWidth = 150;
  static const double headerHeight = 28;

  final ScrollController _h = ScrollController();
  final ScrollController _vBody = ScrollController();
  final ScrollController _vLeft = ScrollController();
  final FocusNode _focusNode = FocusNode();

  List<_GuideRow> _rows = [];
  bool _loading = true;
  int _row = 0;
  int _col = 0;
  Settings _settings = Settings();

  late DateTime _windowStart;
  late DateTime _windowEnd;

  double get _totalWidth => _windowEnd.difference(_windowStart).inMinutes * pxPerMin;

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
    _load();
  }

  @override
  void dispose() {
    _h.dispose();
    _vBody.dispose();
    _vLeft.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    await Error.tryAsyncNoLoading(() async {
      _settings = await SettingsService.getSettings();
      final sources = await Sql.getEnabledSourcesMinimal();
      final channels = await Sql.getLivestreams(
        sources.map((x) => x.id).toList(),
      );
      final programsByName = await fetchAllPrograms(_settings.epgUrl);
      final rows = <_GuideRow>[];
      for (final c in channels) {
        final progs = programsByName[normalizeChannelName(c.name)] ?? const [];
        rows.add(_GuideRow(c, progs));
      }
      if (mounted) {
        setState(() {
          _rows = rows;
          _loading = false;
          _focusInitial();
        });
      }
    }, context);
    if (mounted && _loading) setState(() => _loading = false);
  }

  // Focus the programme airing now on the first channel.
  void _focusInitial() {
    if (_rows.isEmpty) return;
    final now = DateTime.now();
    final progs = _rows[0].programs;
    var idx = progs.indexWhere(
      (p) => !p.start.isAfter(now) && p.stop.isAfter(now),
    );
    if (idx < 0) idx = 0;
    _row = 0;
    _col = idx;
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToFocused());
  }

  void _scrollToFocused() {
    if (_rows.isEmpty) return;
    const animate = Duration(milliseconds: 200);
    if (_vBody.hasClients) {
      final maxV = _vBody.position.maxScrollExtent;
      final vTarget = (_row * rowHeight - 2 * rowHeight)
          .clamp(0.0, maxV)
          .toDouble();
      _vBody.animateTo(vTarget, duration: animate, curve: Curves.easeOut);
    }
    final progs = _rows[_row].programs;
    if (_h.hasClients && _col >= 0 && _col < progs.length) {
      final maxH = _h.position.maxScrollExtent;
      final x = progs[_col].start.difference(_windowStart).inMinutes * pxPerMin;
      final hTarget = (x - labelWidth).clamp(0.0, maxH).toDouble();
      _h.animateTo(hTarget, duration: animate, curve: Curves.easeOut);
    }
  }

  int _clampCol(int col) {
    final len = _rows[_row].programs.length;
    if (len == 0) return 0;
    if (col < 0) return 0;
    if (col > len - 1) return len - 1;
    return col;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (_rows.isEmpty) return KeyEventResult.ignored;
    final k = event.logicalKey;
    if (k == LogicalKeyboardKey.arrowDown) {
      if (_row < _rows.length - 1) {
        setState(() {
          _row++;
          _col = _clampCol(_col);
        });
        _scrollToFocused();
      }
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp) {
      if (_row > 0) {
        setState(() {
          _row--;
          _col = _clampCol(_col);
        });
        _scrollToFocused();
      }
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowRight) {
      if (_col < _rows[_row].programs.length - 1) {
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
    if (_rows.isEmpty) return;
    final row = _rows[_row];
    if (_col < 0 || _col >= row.programs.length) return;
    final p = row.programs[_col];
    final now = DateTime.now();
    if (p.start.isAfter(now)) return; // future — nothing to play
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Focus(
          focusNode: _focusNode,
          autofocus: true,
          onKeyEvent: _onKey,
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: Colors.white))
              : _rows.isEmpty
              ? const Center(
                  child: Text(
                    "No guide data",
                    style: TextStyle(color: Colors.white70),
                  ),
                )
              : _buildGrid(),
        ),
      ),
    );
  }

  Widget _buildGrid() {
    return Column(
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left: corner + channel labels (synced vertically with body).
              SizedBox(
                width: labelWidth,
                child: Column(
                  children: [
                    SizedBox(
                      height: headerHeight,
                      child: Container(color: Colors.black),
                    ),
                    Expanded(
                      child: ListView.builder(
                        controller: _vLeft,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _rows.length,
                        itemExtent: rowHeight,
                        itemBuilder: (_, i) => _channelLabel(_rows[i].channel, i),
                      ),
                    ),
                  ],
                ),
              ),
              // Right: horizontal scroll of [time header + rows + now line].
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
                                itemCount: _rows.length,
                                itemExtent: rowHeight,
                                itemBuilder: (_, i) => _rowBlocks(i),
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
          ),
        ),
      ],
    );
  }

  Widget _channelLabel(Channel c, int i) {
    final focused = i == _row;
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
        c.name,
        style: const TextStyle(color: Colors.white, fontSize: 13),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _timeHeader() {
    final marks = <Widget>[];
    var t = _windowStart;
    while (t.isBefore(_windowEnd)) {
      final left = t.difference(_windowStart).inMinutes * pxPerMin;
      marks.add(
        Positioned(
          left: left,
          top: 4,
          child: Text(
            "${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}",
            style: const TextStyle(color: Colors.white60, fontSize: 12),
          ),
        ),
      );
      t = t.add(const Duration(minutes: 30));
    }
    return Stack(children: marks);
  }

  Widget _rowBlocks(int i) {
    final row = _rows[i];
    final children = <Widget>[];
    for (var j = 0; j < row.programs.length; j++) {
      final p = row.programs[j];
      final left = p.start.difference(_windowStart).inMinutes * pxPerMin;
      var width = p.stop.difference(p.start).inMinutes * pxPerMin;
      if (width < 24) width = 24;
      final focused = i == _row && j == _col;
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
    return SizedBox(width: _totalWidth, height: rowHeight, child: Stack(children: children));
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
