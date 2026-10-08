// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/date_time_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/event_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/vibe/vibe_media_viewer.dart';
import 'package:fluffychat/vibe/vibe_starred.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/mxc_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';
import 'package:url_launcher/url_launcher.dart';

final RegExp _urlRegex = RegExp(r'https?://\S+');

/// Middle pane for one DM: profile card + Starred / Media / Links / Files.
class VibeDmDetail extends StatelessWidget {
  final Room room;
  final VoidCallback onBack;
  final VoidCallback onOpenChat;

  const VibeDmDetail({
    required this.room,
    required this.onBack,
    required this.onOpenChat,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = room.getLocalizedDisplayname(MatrixLocals(L10n.of(context)));
    final invited = room.membership == Membership.invite;
    return Material(
      color: theme.colorScheme.surface,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Header: ← Home      name
            SizedBox(
              height: 52,
              child: Row(
                children: [
                  InkWell(
                    onTap: onBack,
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.arrow_back,
                            size: 20,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Home',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      name,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                      ),
                    ),
                  ),
                  const SizedBox(width: 84),
                ],
              ),
            ),
            Divider(height: 1, color: theme.dividerColor),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 110),
                children: [
                  // Profile card
                  Material(
                    color: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22),
                      side: BorderSide(color: theme.dividerColor),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: invited ? null : onOpenChat,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Avatar(
                              mxContent: room.avatar,
                              name: name,
                              size: 60,
                              client: room.client,
                              presenceUserId: room.directChatMatrixID,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 19,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Icon(
                                        room.encrypted
                                            ? Icons.lock_outline
                                            : Icons.lock_open,
                                        size: 16,
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        room.encrypted
                                            ? 'End-to-End Encrypted'
                                            : 'Not encrypted',
                                        style: TextStyle(
                                          color: theme
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (!invited) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      'Tap to open chat screen →',
                                      style: TextStyle(
                                        color: theme.colorScheme.primary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (invited) _ApprovalBanner(room: room, name: name),
                  if (!invited) ...[
                    const SizedBox(height: 8),
                    _StarredSection(room: room),
                    _PagedSection(
                      room: room,
                      icon: Icons.image_outlined,
                      color: Colors.indigoAccent,
                      label: 'MEDIA',
                      emptyText: 'No media shared in this chat.',
                      searchFunc: (e) => {
                        MessageTypes.Image,
                        MessageTypes.Video,
                      }.contains(e.messageType),
                      bodyBuilder: (context, events) => _MediaGrid(events),
                    ),
                    _PagedSection(
                      room: room,
                      icon: Icons.link,
                      color: Colors.indigoAccent,
                      label: 'LINKS',
                      emptyText: 'No links shared in this chat.',
                      searchFunc: (e) =>
                          e.type == EventTypes.Message &&
                          _urlRegex.hasMatch(e.body),
                      bodyBuilder: (context, events) => _LinkList(events),
                    ),
                    _PagedSection(
                      room: room,
                      icon: Icons.description_outlined,
                      color: const Color(0xFFB5BAC1),
                      label: 'FILES',
                      emptyText: 'No files shared in this chat.',
                      searchFunc: (e) =>
                          e.messageType == MessageTypes.File ||
                          (e.messageType == MessageTypes.Audio &&
                              !e.content.containsKey(
                                'org.matrix.msc3245.voice',
                              )),
                      bodyBuilder: (context, events) => _FileList(events),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ApprovalBanner extends StatelessWidget {
  final Room room;
  final String name;
  const _ApprovalBanner({required this.room, required this.name});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Material(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'APPROVAL REQUEST',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.6,
                  color: const Color(0xFFB5BAC1),
                ),
              ),
              const SizedBox(height: 6),
              Text('$name wants to start a chat with you.'),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        try {
                          await room.leave();
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('$e')),
                            );
                          }
                        }
                      },
                      child: const Text('Reject'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () async {
                        try {
                          await room.join();
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('$e')),
                            );
                          }
                        }
                      },
                      child: const Text('Accept'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Collapsible section with header (icon, label, count) and a contained,
/// scrollable body.
class _Section extends StatefulWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String count;
  final Widget child;

  const _Section({
    required this.icon,
    required this.color,
    required this.label,
    required this.count,
    required this.child,
  });

  @override
  State<_Section> createState() => _SectionState();
}

class _SectionState extends State<_Section> {
  bool open = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => open = !open),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
            child: Row(
              children: [
                Icon(widget.icon, color: widget.color, size: 22),
                const SizedBox(width: 12),
                Text(
                  widget.label,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    widget.count,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Spacer(),
                Icon(
                  open ? Icons.expand_more : Icons.chevron_right,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: widget.child,
          ),
        Divider(height: 1, color: theme.dividerColor),
      ],
    );
  }
}

class _Scroller extends StatelessWidget {
  final Widget child;
  const _Scroller({required this.child});

  @override
  Widget build(BuildContext context) =>
      ConstrainedBox(constraints: const BoxConstraints(maxHeight: 240), child: child);
}

class _Empty extends StatelessWidget {
  final String text;
  const _Empty(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    child: Text(
      text,
      style: TextStyle(
        fontStyle: FontStyle.italic,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

class _PagedSection extends StatefulWidget {
  final Room room;
  final IconData icon;
  final Color color;
  final String label;
  final String emptyText;
  final bool Function(Event) searchFunc;
  final Widget Function(BuildContext, List<Event>) bodyBuilder;

  const _PagedSection({
    required this.room,
    required this.icon,
    required this.color,
    required this.label,
    required this.emptyText,
    required this.searchFunc,
    required this.bodyBuilder,
  });

  @override
  State<_PagedSection> createState() => _PagedSectionState();
}

class _PagedSectionState extends State<_PagedSection> {
  final List<Event> events = [];
  String? nextBatch;
  bool endReached = false;
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    _more();
  }

  Future<void> _more() async {
    if (isLoading || endReached) return;
    setState(() => isLoading = true);
    try {
      final result = await widget.room.searchEvents(
        searchFunc: widget.searchFunc,
        nextBatch: nextBatch,
      );
      if (!mounted) return;
      setState(() {
        isLoading = false;
        events.addAll(result.events);
        nextBatch = result.nextBatch;
        endReached = result.nextBatch == null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        isLoading = false;
        endReached = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = '${events.length}${endReached ? '' : '+'}';
    return _Section(
      icon: widget.icon,
      color: widget.color,
      label: widget.label,
      count: count,
      child: events.isEmpty
          ? (isLoading
                ? const Padding(
                    padding: EdgeInsets.all(8),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : _Empty(widget.emptyText))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                widget.bodyBuilder(context, events),
                if (!endReached)
                  TextButton(
                    onPressed: isLoading ? null : _more,
                    child: Text(isLoading ? 'Loading…' : 'Load more'),
                  ),
              ],
            ),
    );
  }
}

class _MediaGrid extends StatelessWidget {
  final List<Event> events;
  const _MediaGrid(this.events);

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(12);
    // One horizontal strip that scrolls on its own, so Links and Files
    // stay close no matter how many photos there are.
    return SizedBox(
      height: 132,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        itemCount: events.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final event = events[i];
          final video = event.messageType == MessageTypes.Video;
          return GestureDetector(
            onTap: () => VibeMediaViewer.open(context, events, i),
            child: ClipRRect(
                borderRadius: radius,
                child: SizedBox(
                  width: 124,
                  height: 124,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      MxcImage(
                        event: event,
                        width: 124,
                        height: 124,
                        fit: BoxFit.cover,
                        isThumbnail: true,
                      ),
                      if (video)
                        const Center(
                          child: Icon(
                            Icons.play_circle_fill,
                            color: Colors.white,
                            size: 34,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          );
        },
      ),
    );
  }
}

class _LinkList extends StatelessWidget {
  final List<Event> events;
  const _LinkList(this.events);

  @override
  Widget build(BuildContext context) {
    final links = <(Event, String)>[];
    for (final e in events) {
      for (final m in _urlRegex.allMatches(e.body)) {
        links.add((e, m.group(0)!));
      }
    }
    return _Scroller(
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: links.length,
        itemBuilder: (context, i) {
          final (event, url) = links[i];
          return ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            leading: Icon(
              Icons.link,
              color: Theme.of(context).colorScheme.primary,
            ),
            title: Text(url, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text(event.originServerTs.localizedTime(context)),
            onTap: () =>
                launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
          );
        },
      ),
    );
  }
}

class _FileList extends StatelessWidget {
  final List<Event> events;
  const _FileList(this.events);

  @override
  Widget build(BuildContext context) {
    return _Scroller(
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: events.length,
        itemBuilder: (context, i) {
          final event = events[i];
          final filename =
              event.content.tryGet<String>('filename') ??
              event.content.tryGet<String>('body') ??
              'File';
          return ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            leading: const Icon(Icons.file_present_outlined),
            title: Text(filename, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              '${event.sizeString ?? ''} · ${event.originServerTs.localizedTime(context)}',
            ),
            onTap: () => event.saveFile(context),
          );
        },
      ),
    );
  }
}

class _StarredSection extends StatelessWidget {
  final Room room;
  const _StarredSection({required this.room});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: VibeStarred.revision,
      builder: (context, _, _) {
        final ids = VibeStarred.ids(room.id);
        return _Section(
          icon: Icons.star,
          color: const Color(0xFFB5BAC1),
          label: 'STARRED',
          count: '${ids.length}',
          child: ids.isEmpty
              ? const _Empty('No starred messages in this chat.')
              : _Scroller(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: ids.length,
                    itemBuilder: (context, i) {
                      final id = ids[i];
                      return FutureBuilder<Event?>(
                        future: room.getEventById(id),
                        builder: (context, snapshot) {
                          final event = snapshot.data;
                          if (event == null) {
                            return const ListTile(dense: true, title: Text('…'));
                          }
                          final sender = event.senderFromMemoryOrFallback;
                          final name = sender.calcDisplayname(
                            i18n: MatrixLocals(L10n.of(context)),
                          );
                          return ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.only(left: 8),
                            title: Text(
                              '$name · ${event.originServerTs.localizedTimeShort(context)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            subtitle: Text(
                              event.body,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: IconButton(
                              icon: const Icon(
                                Icons.star,
                                color: const Color(0xFFB5BAC1),
                                size: 20,
                              ),
                              onPressed: () => VibeStarred.toggle(room.id, id),
                            ),
                            onTap: () =>
                                context.go('/rooms/${room.id}?event=$id'),
                          );
                        },
                      );
                    },
                  ),
                ),
        );
      },
    );
  }
}
