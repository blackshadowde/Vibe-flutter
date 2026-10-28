// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import 'package:vibe/widgets/matrix.dart';
import 'package:vibe/l10n/l10n.dart';
import 'package:vibe/utils/localized_exception_extension.dart';
import 'package:go_router/go_router.dart';
import 'package:vibe/widgets/layouts/max_width_body.dart';
import 'package:vibe/vibe/screens/chat_details/participant_list_item.dart';

class ChatMembersPage extends StatefulWidget {
  final String roomId;

  const ChatMembersPage({required this.roomId, super.key});

  @override
  State<ChatMembersPage> createState() => _ChatMembersPageState();
}

class _ChatMembersPageState extends State<ChatMembersPage> {
  List<User>? members;
  List<User>? filteredMembers;
  Object? error;
  Membership membershipFilter = Membership.join;

  final TextEditingController filterController = TextEditingController();

  void setMembershipFilter(Membership membership) {
    membershipFilter = membership;
    setFilter();
  }

  Future<void> setFilter([_]) async {
    final filter = filterController.text.toLowerCase().trim();

    final members = this.members
        ?.where((member) => member.membership == membershipFilter)
        .toList();

    if (filter.isEmpty) {
      setState(() {
        filteredMembers = members
          ?..sort((b, a) => a.powerLevel.level.compareTo(b.powerLevel.level));
      });
      return;
    }
    setState(() {
      filteredMembers =
          members
              ?.where(
                (user) =>
                    user.displayName?.toLowerCase().contains(filter) ??
                    user.id.toLowerCase().contains(filter),
              )
              .toList()
            ?..sort((b, a) => a.powerLevel.level.compareTo(b.powerLevel.level));
    });
  }

  Future<void> refreshMembers([_]) async {
    Logs().d('Load room members from', widget.roomId);
    try {
      setState(() {
        error = null;
      });
      final participants = await Matrix.of(context).client
          .getRoomById(widget.roomId)
          ?.requestParticipants(
            [...Membership.values]..remove(Membership.leave),
          );

      if (!mounted) return;

      setState(() {
        members = participants;
      });
      setFilter();
    } catch (e, s) {
      Logs().d(
        'Unable to request participants. Try again in 3 seconds...',
        e,
        s,
      );
      setState(() {
        error = e;
      });
    }
  }

  StreamSubscription? _updateSub;

  @override
  void initState() {
    super.initState();
    refreshMembers();

    _updateSub = Matrix.of(context).client.onSync.stream
        .where(
          (syncUpdate) =>
              syncUpdate.rooms?.join?[widget.roomId]?.timeline?.events?.any(
                (state) => state.type == EventTypes.RoomMember,
              ) ??
              false,
        )
        .listen(refreshMembers);
  }

  @override
  void dispose() {
    _updateSub?.cancel();
    filterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final room = Matrix.of(
      context,
    ).client.getRoomById(widget.roomId);
    if (room == null) {
      return Scaffold(
        appBar: AppBar(title: Text(L10n.of(context).oopsSomethingWentWrong)),
        body: Center(
          child: Text(L10n.of(context).youAreNoLongerParticipatingInThisChat),
        ),
      );
    }

    final members = filteredMembers;

    final roomCount =
        (room.summary.mJoinedMemberCount ?? 0) +
        (room.summary.mInvitedMemberCount ?? 0);

    final error = this.error;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: const Center(child: BackButton()),
        title: Text(L10n.of(context).countParticipants(roomCount)),
        actions: [
          if (room.canInvite)
            IconButton(
              onPressed: () => context.go('/rooms/${room.id}/invite'),
              icon: const Icon(Icons.person_add_outlined),
            ),
        ],
      ),
      body: MaxWidthBody(
        withScrolling: false,
        innerPadding: const EdgeInsets.symmetric(vertical: 8),
        child: error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisSize: .min,
                    children: [
                      const Icon(Icons.error_outline),
                      Text(error.toLocalizedString(context)),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: refreshMembers,
                        icon: const Icon(Icons.refresh_outlined),
                        label: Text(L10n.of(context).tryAgain),
                      ),
                    ],
                  ),
                ),
              )
            : members == null
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: CircularProgressIndicator.adaptive(),
                ),
              )
            : ListView.builder(
                shrinkWrap: true,
                itemCount: members.length + 1,
                itemBuilder: (context, i) {
                  if (i == 0) {
                    final availableFilters = Membership.values
                        .where(
                          (membership) =>
                              members?.any(
                                (member) => member.membership == membership,
                              ) ??
                              false,
                        )
                        .toList();
                    availableFilters.sort(
                      (a, b) => a == Membership.join ? -1 : 1,
                    );
                    return Column(
                      mainAxisSize: .min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: TextField(
                            controller: filterController,
                            onChanged: setFilter,
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: theme.colorScheme.secondaryContainer,
                              border: OutlineInputBorder(
                                borderSide: BorderSide.none,
                                borderRadius: BorderRadius.circular(99),
                              ),
                              hintStyle: TextStyle(
                                color: theme.colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.normal,
                              ),
                              prefixIcon: const Icon(Icons.search_outlined),
                              hintText: L10n.of(context).search,
                            ),
                          ),
                        ),
                        if (availableFilters.length > 1)
                          SizedBox(
                            height: 64,
                            child: ListView.builder(
                              padding: const EdgeInsets.all(12.0),
                              scrollDirection: Axis.horizontal,
                              itemCount: availableFilters.length,
                              itemBuilder: (context, i) => Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4.0,
                                ),
                                child: FilterChip(
                                  label: Text(switch (availableFilters[i]) {
                                    Membership.ban => L10n.of(context).banned,
                                    Membership.invite =>
                                      L10n.of(context).countInvited(
                                        room.summary.mInvitedMemberCount ??
                                            members
                                                ?.where(
                                                  (member) =>
                                                      member.membership ==
                                                      Membership.invite,
                                                )
                                                .length ??
                                            0,
                                      ),
                                    Membership.join =>
                                      L10n.of(context).countParticipants(
                                        room.summary.mJoinedMemberCount ??
                                            members
                                                ?.where(
                                                  (member) =>
                                                      member.membership ==
                                                      Membership.join,
                                                )
                                                .length ??
                                            0,
                                      ),
                                    Membership.knock => L10n.of(
                                      context,
                                    ).knocking,
                                    Membership.leave => L10n.of(
                                      context,
                                    ).leftTheChat,
                                  }),
                                  selected:
                                      membershipFilter ==
                                      availableFilters[i],
                                  onSelected: (_) => setMembershipFilter(availableFilters[i]),
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  }
                  i--;
                  return ParticipantListItem(members[i]);
                },
              ),
      ),
    );
  }
}

