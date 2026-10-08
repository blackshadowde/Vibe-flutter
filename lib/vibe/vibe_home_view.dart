// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/pages/chat_list/chat_list.dart';
import 'package:fluffychat/utils/stream_extension.dart';
import 'package:fluffychat/vibe/vibe_chat_actions.dart';
import 'package:fluffychat/vibe/vibe_dm_detail.dart';
import 'package:fluffychat/vibe/vibe_dm_pane.dart';
import 'package:fluffychat/vibe/vibe_dm_rail.dart';
import 'package:fluffychat/vibe/vibe_swipe.dart';
import 'package:fluffychat/vibe/vibe_user_bar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

/// Discord-style home: [rail of DM avatars] | [Home list or selected DM].
class VibeHomeView extends StatefulWidget {
  final ChatListController controller;
  const VibeHomeView(this.controller, {super.key});

  @override
  State<VibeHomeView> createState() => _VibeHomeViewState();
}

class _VibeHomeViewState extends State<VibeHomeView> {
  String? selectedId;
  String? _lastOpenedId;

  bool _dragging = false;
  double _progress = 0;
  double _width = 400;
  AnimationController? _ctl;
  NavigatorState? _nav;
  GoRouter? _router;
  List<Room> _rooms = const [];

  @override
  void dispose() {
    VibeSwipe.reset();
    super.dispose();
  }

  String? _targetId() {
    final id = selectedId ?? widget.controller.activeChat ?? _lastOpenedId;
    if (id == null) return null;
    for (final r in _rooms) {
      if (r.id == id && r.membership == Membership.join) return id;
    }
    return null;
  }

  void _onRoute(PageRoute<dynamic> route) {
    final c = route.controller;
    if (c == null) return;
    _ctl = c;
    _nav = route.navigator;
    c.stop();
    c.value = _progress;
    _nav?.didStartUserGesture();
    if (!_dragging) _settle(0);
  }

  void _dragUpdate(DragUpdateDetails d) {
    if (!_dragging) {
      if (_busy || d.delta.dx >= 0) return;
      final id = _targetId();
      if (id == null) return;
      _dragging = true;
      _busy = true;
      _progress = 0;
      _ctl = null;
      _nav = null;
      _router = GoRouter.of(context);
      _width = MediaQuery.sizeOf(context).width;
      _lastOpenedId = id;
      VibeSwipe.pending = true;
      VibeSwipe.onRoute = _onRoute;
      _router!.go('/rooms/$id');
    }
    _progress = (_progress - d.delta.dx / _width).clamp(0.0, 1.0);
    _ctl?.value = _progress;
  }

  bool _busy = false;

  void _dragEnd(DragEndDetails d) {
    if (!_dragging) return;
    _dragging = false;
    _settle(d.primaryVelocity ?? 0);
  }

  /// Finish the gesture: spring the real route animation open or shut.
  Future<void> _settle(double v) async {
    final c = _ctl;
    if (c == null) {
      // the route has not started yet; _onRoute settles it when it does
      Future<void>.delayed(const Duration(seconds: 2), () {
        if (_ctl == null) {
          VibeSwipe.reset();
          _busy = false;
          _router?.go('/rooms');
        }
      });
      return;
    }
    final commit = v < -500 || (c.value > 0.35 && v < 500);
    try {
      await c.animateWith(
        SpringSimulation(
          SpringDescription.withDampingRatio(
            mass: 1,
            stiffness: 420,
            ratio: 1,
          ),
          c.value,
          commit ? 1.0 : 0.0,
          -v / _width,
        ),
      );
    } catch (_) {}
    _nav?.didStopUserGesture();
    if (!commit) _router?.go('/rooms');
    _ctl = null;
    _nav = null;
    _busy = false;
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final client = Matrix.of(context).client;
    return PopScope(
      canPop: selectedId == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => selectedId = null);
      },
      child: StreamBuilder(
        key: ValueKey(client.userID.toString()),
        stream: client.onSync.stream
            .where((s) => s.hasRoomUpdate)
            .rateLimit(const Duration(seconds: 1)),
        builder: (context, _) {
          final rooms = VibeChatActions.pinnedFirst(
            client.rooms
                .where(
                  (r) =>
                      !r.isSpace &&
                      (r.membership == Membership.join ||
                          r.membership == Membership.invite),
                )
                .toList(),
          );
          _rooms = rooms;
          Room? selected;
          for (final r in rooms) {
            if (r.id == selectedId) selected = r;
          }
          final theme = Theme.of(context);
          return GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragUpdate: _dragUpdate,
            onHorizontalDragEnd: _dragEnd,
            onHorizontalDragCancel: () => _dragEnd(DragEndDetails()),
            child: ColoredBox(
            color: theme.colorScheme.surfaceContainerLowest,
            child: Stack(
              children: [
                Row(
                  children: [
                    VibeDmRail(
                      rooms: rooms,
                      selectedId: selected?.id,
                      activeRoomId: controller.activeChat,
                      onSelect: (room) => setState(() => selectedId = room.id),
                      onHome: () => setState(() => selectedId = null),
                      onLongPress: (room) => VibeChatActions.show(
                        context,
                        room,
                        onOpen: () {
                          _lastOpenedId = room.id;
                          controller.onChatTap(room);
                        },
                      ),
                    ),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(24),
                        ),
                        child: selected == null
                            ? VibeDmPane(
                                rooms: rooms,
                                activeRoomId: controller.activeChat,
                                onTap: (room) =>
                                    setState(() => selectedId = room.id),
                                onOpen: (room) {
                                  _lastOpenedId = room.id;
                                  controller.onChatTap(room);
                                },
                              )
                            : VibeDmDetail(
                                key: ValueKey(selected.id),
                                room: selected,
                                onBack: () => setState(() => selectedId = null),
                                onOpenChat: () {
                                  _lastOpenedId = selected!.id;
                                  controller.onChatTap(selected);
                                },
                              ),
                      ),
                    ),
                  ],
                ),
                const Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: VibeUserBar(),
                ),
              ],
            ),
            ),
          );
        },
      ),
    );
  }
}
