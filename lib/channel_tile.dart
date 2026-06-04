import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_tv/backend/settings_service.dart';
import 'package:open_tv/backend/sql.dart';
import 'package:open_tv/backend/xtream.dart';
import 'package:open_tv/memory.dart';
import 'package:open_tv/models/channel.dart';
import 'package:open_tv/error.dart';
import 'package:open_tv/models/media_type.dart';
import 'package:open_tv/models/node.dart';
import 'package:open_tv/models/node_type.dart';
import 'package:open_tv/player.dart';

class ChannelTile extends StatefulWidget {
  final Channel channel;
  final BuildContext parentContext;
  final Function(Node node) setNode;
  final VoidCallback? onFocusNavbar;
  final bool autofocus;
  const ChannelTile({
    super.key,
    required this.channel,
    required this.setNode,
    required this.parentContext,
    this.onFocusNavbar,
    this.autofocus = false,
  });

  @override
  State<ChannelTile> createState() => _ChannelTileState();
}

class _ChannelTileState extends State<ChannelTile> {
  final FocusNode _focusNode = FocusNode();
  @override
  void initState() {
    super.initState();
    _focusNode.onKeyEvent = (node, event) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.arrowRight) {
        if (!FocusScope.of(
          context,
        ).focusInDirection(TraversalDirection.right)) {
          widget.onFocusNavbar?.call();
        }
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };
    _focusNode.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> favorite() async {
    if (widget.channel.mediaType == MediaType.group) return;
    await Error.tryAsyncNoLoading(() async {
      final newValue = !widget.channel.favorite;
      await Sql.favoriteChannel(widget.channel.id!, newValue);
      setState(() {
        widget.channel.favorite = newValue;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newValue ? "Added to favorites" : "Removed from favorites",
          ),
          duration: const Duration(milliseconds: 500),
        ),
      );
    }, context);
  }

  Future<void> showContextMenu() async {
    if (widget.channel.mediaType == MediaType.group) return;
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black.withValues(alpha: 0.92),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    widget.channel.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              ListTile(
                autofocus: true,
                leading: const Icon(Icons.play_arrow, color: Colors.white),
                title: const Text(
                  "Play",
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  play();
                },
              ),
              ListTile(
                leading: Icon(
                  widget.channel.favorite ? Icons.star : Icons.star_border,
                  color: Colors.amber,
                ),
                title: Text(
                  widget.channel.favorite
                      ? "Remove from Favorites"
                      : "Add to Favorites",
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  favorite();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> play() async {
    if (widget.channel.mediaType == MediaType.group ||
        widget.channel.mediaType == MediaType.serie) {
      if (widget.channel.mediaType == MediaType.serie &&
          !refreshedSeries.contains(widget.channel.id)) {
        await Error.tryAsync(
          () async {
            await getEpisodes(widget.channel);
            refreshedSeries.add(widget.channel.id!);
          },
          widget.parentContext,
          null,
          true,
          false,
        );
      }
      widget.setNode(
        Node(
          id: widget.channel.mediaType == MediaType.group
              ? widget.channel.id!
              : int.parse(widget.channel.url!),
          name: widget.channel.name,
          type: fromMediaType(widget.channel.mediaType),
        ),
      );
    } else {
      var settings = await SettingsService.getSettings();
      Sql.addToHistory(widget.channel.id!);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => Player(channel: widget.channel, settings: settings),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: _focusNode.hasFocus ? 8.0 : 2.0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: InkWell(
        focusNode: _focusNode,
        autofocus: widget.autofocus,
        onLongPress: showContextMenu,
        onTap: () async => await play(),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Container(
                padding: const EdgeInsets.all(8.0),
                child: Center(
                  child: widget.channel.image != null
                      ? CachedNetworkImage(
                          imageUrl: widget.channel.image!,
                          memCacheHeight: 300,
                          memCacheWidth: 300,
                          fit: BoxFit.contain,
                          errorWidget: (_, __, ___) => const Icon(
                            Icons.tv,
                            size: 45,
                            color: Colors.grey,
                          ),
                        )
                      : const Icon(Icons.tv, size: 45, color: Colors.grey),
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    widget.channel.name,
                    textAlign: TextAlign.left,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: Theme.of(
                        context,
                      ).textTheme.titleMedium?.fontSize!,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
            if (widget.channel.favorite)
              Padding(
                padding: EdgeInsets.only(right: 8.0),
                child: Center(
                  child: const Icon(Icons.star, size: 25, color: Colors.amber),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
