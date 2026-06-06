import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_tv/backend/sql.dart';
import 'package:open_tv/error.dart';
import 'package:open_tv/l10n/strings.dart';
import 'package:open_tv/models/channel.dart';

/// Searchable list of livestream channels. Returns the picked [Channel] via
/// Navigator.pop — used to choose the autostart channel.
class ChannelPicker extends StatefulWidget {
  const ChannelPicker({super.key});

  @override
  State<ChannelPicker> createState() => _ChannelPickerState();
}

class _ChannelPickerState extends State<ChannelPicker> {
  final TextEditingController _ctrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  List<Channel> _all = [];
  List<Channel> _filtered = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _searchFocus.addListener(() {
      if (_searchFocus.hasFocus) {
        SystemChannels.textInput.invokeMethod('TextInput.show');
      }
    });
    _load();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    await Error.tryAsyncNoLoading(() async {
      final sources = await Sql.getEnabledSourcesMinimal();
      final list = await Sql.getLivestreams(sources.map((x) => x.id).toList());
      if (!mounted) return;
      setState(() {
        _all = list;
        _filtered = list;
        _loading = false;
      });
    }, context);
    if (mounted && _loading) setState(() => _loading = false);
  }

  void _search(String q) {
    final query = q.trim().toLowerCase();
    setState(() {
      _filtered = query.isEmpty
          ? _all
          : _all.where((c) => c.name.toLowerCase().contains(query)).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.selectChannel)),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _ctrl,
                focusNode: _searchFocus,
                textInputAction: TextInputAction.search,
                onChanged: _search,
                decoration: InputDecoration(
                  hintText: s.searchChannels,
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      itemCount: _filtered.length,
                      itemBuilder: (_, i) {
                        final c = _filtered[i];
                        return ListTile(
                          autofocus: i == 0,
                          leading: const Icon(Icons.tv),
                          title: Text(c.name),
                          subtitle: c.group != null ? Text(c.group!) : null,
                          onTap: () => Navigator.of(context).pop(c),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
