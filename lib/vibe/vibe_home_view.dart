// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/pages/chat_list/chat_list.dart';
import 'package:fluffychat/utils/stream_extension.dart';
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

class _VibeHomeViewState extends State<VibeHomeView>
    with SingleTickerProviderStateMixin {
  String? selectedId;
  String? _lastOpenedId;

  late final AnimationController _swipe = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );
  bool _dragging = false;
  bool _locked = false;
  double _width = 400;
  DateTime _startedAt = DateTime.now();
  GoRouter? _router;
  List<Room> _rooms = const [];

  @override
  void dispose() {
    _swipe.dispose();
    if (VibeSwipe.anim == _swipe) {
      VibeSwipe.anim = null;
      VibeSwipe.reset();
    }
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

  void _dragUpdate(DragUpdateDetails d) {
    if (_locked) return;
    if (!_dragging) {
      if (d.delta.dx >= 0) return;
      final id = _targetId();
      if (id == null) return;
      _dragging = true;
      _router = GoRouter.of(context);
      _width = MediaQuery.sizeOf(context).width;
      _lastOpenedId = id;
      _swipe.stop();
      _swipe.value = 0;
      VibeSwipe.anim = _swipe;
      VibeSwipe.targetRoute = null;
      VibeSwipe.pending = true;
      VibeSwipe.active.value = true;
      _startedAt = DateTime.now();
      _router!.go('/rooms/$id');
    }
    _swipe.value = (_swipe.value - d.delta.dx / _width).clamp(0.0, 1.0);
  }

  Future<void> _dragEnd(DragEndDetails d) async {
    if (!_dragging) return;
    _dragging = false;
    _locked = true;
    final v = d.primaryVelocity ?? 0; // negative = towards the left
    final commit = v < -500 || (_swipe.value > 0.35 && v < 500);
    final sim = SpringSimulation(
      SpringDescription.withDampingRatio(mass: 1, stiffness: 420, ratio: 1),
      _swipe.value,
      commit ? 1.0 : 0.0,
      -v / _width,
    );
    await _swipe.animateWith(sim);
    if (!commit) _router?.go('/rooms');
    // keep control until the route's own animation has finished
    final wait = const Duration(milliseconds: 480) -
        DateTime.now().difference(_startedAt);
    if (!wait.isNegative) await Future<void>.delayed(wait);
    VibeSwipe.reset();
    _locked = false;
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
          final rooms = client.rooms
              .where(
                (r) =>
                    !r.isSpace &&
                    (r.membership == Membership.join ||
                        r.membership == Membership.invite),
              )
              .toList();
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
                                  controller.onChatTap(selected!);
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
