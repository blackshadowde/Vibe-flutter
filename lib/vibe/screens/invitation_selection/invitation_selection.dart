// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'package:vibe/l10n/l10n.dart';
import 'package:vibe/widgets/future_loading_dialog.dart';
import 'package:vibe/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import 'package:vibe/utils/localized_exception_extension.dart';
import 'package:vibe/widgets/avatar.dart';
import 'package:vibe/widgets/layouts/max_width_body.dart';
import 'package:vibe/widgets/adaptive_dialogs/user_dialog.dart';

class InvitationSelection extends StatefulWidget {
  final String roomId;
  const InvitationSelection({super.key, required this.roomId});

  @override
  _InvitationSelectionState createState() =>
      _InvitationSelectionState();
}

class _InvitationSelectionState extends State<InvitationSelection> {
  TextEditingController controller = TextEditingController();
  late String currentSearchTerm;
  bool loading = false;
  List<Profile> foundProfiles = [];
  Timer? coolDown;

  String? get roomId => widget.roomId;

  Future<List<User>> getContacts(BuildContext context) async {
    final client = Matrix.of(context).client;
    final room = client.getRoomById(roomId!)!;

    final participants = (room.summary.mJoinedMemberCount ?? 0) > 100
        ? room.getParticipants()
        : await room.requestParticipants();
    participants.removeWhere(
      (u) => ![Membership.join, Membership.invite].contains(u.membership),
    );
    final contacts = client.rooms
        .where((r) => r.isDirectChat)
        .map((r) => r.unsafeGetUserFromMemoryOrFallback(r.directChatMatrixID!))
        .toList();
    contacts.sort(
      (a, b) => a.calcDisplayname().toLowerCase().compareTo(
        b.calcDisplayname().toLowerCase(),
      ),
    );
    return contacts;
  }

  Future<void> inviteAction(
    BuildContext context,
    String id,
    String displayname,
  ) async {
    final l10n = L10n.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final room = Matrix.of(context).client.getRoomById(roomId!)!;

    final success = await showFutureLoadingDialog(
      context: context,
      future: () => room.invite(id),
    );
    if (success.error == null) {
      if (!context.mounted) return;
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text(l10n.contactHasBeenInvitedToTheGroup)),
      );
    }
  }

  void searchUserWithCoolDown(String text) {
    coolDown?.cancel();
    coolDown = Timer(
      const Duration(milliseconds: 500),
      () => searchUser(context, text),
    );
  }

  Future<void> searchUser(BuildContext context, String text) async {
    coolDown?.cancel();
    if (text.isEmpty) {
      setState(() => foundProfiles = []);
    }
    currentSearchTerm = text;
    if (currentSearchTerm.isEmpty) return;
    if (loading) return;
    setState(() => loading = true);
    final matrix = Matrix.of(context);
    SearchUserDirectoryResponse response;
    try {
      response = await matrix.client.searchUserDirectory(text, limit: 10);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text((e).toLocalizedString(context))));
      return;
    } finally {
      setState(() => loading = false);
    }
    setState(() {
      foundProfiles = List<Profile>.from(response.results);
      if (text.isValidMatrixIdStrict() &&
          foundProfiles.indexWhere((profile) => text == profile.userId) == -1) {
        setState(
          () => foundProfiles = [
            Profile.fromJson({'user_id': text}),
          ],
        );
      }
    });
  }

  @override
  void dispose() {
    controller.dispose();
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

    final groupName = room.name.isEmpty ? L10n.of(context).group : room.name;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: const Center(child: BackButton()),
        titleSpacing: 0,
        title: Text(L10n.of(context).inviteContact),
      ),
      body: MaxWidthBody(
        innerPadding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                textInputAction: TextInputAction.search,
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
                  hintText: L10n.of(context).inviteContactToGroup(groupName),
                  prefixIcon: loading
                      ? const Padding(
                          padding: EdgeInsets.symmetric(
                            vertical: 10.0,
                            horizontal: 12,
                          ),
                          child: SizedBox.square(
                            dimension: 24,
                            child: CircularProgressIndicator.adaptive(
                              strokeWidth: 2,
                            ),
                          ),
                        )
                      : const Icon(Icons.search_outlined),
                ),
                onChanged: searchUserWithCoolDown,
              ),
            ),
            StreamBuilder<Object>(
              stream: room.client.onRoomState.stream.where(
                (update) => update.roomId == room.id,
              ),
              builder: (context, snapshot) {
                final participants = room
                    .getParticipants()
                    .map((user) => user.id)
                    .toSet();
                return foundProfiles.isNotEmpty
                    ? ListView.builder(
                        physics: const NeverScrollableScrollPhysics(),
                        shrinkWrap: true,
                        itemCount: foundProfiles.length,
                        itemBuilder: (BuildContext context, int i) =>
                            _InviteContactListTile(
                              profile: foundProfiles[i],
                              isMember: participants.contains(
                                foundProfiles[i].userId,
                              ),
                              onTap: () => inviteAction(
                                context,
                                foundProfiles[i].userId,
                                foundProfiles[i].displayName ??
                                    foundProfiles[i]
                                        .userId
                                        .localpart ??
                                    L10n.of(context).user,
                              ),
                            ),
                      )
                    : FutureBuilder<List<User>>(
                        future: getContacts(context),
                        builder: (BuildContext context, snapshot) {
                          if (!snapshot.hasData) {
                            return const Center(
                              child: CircularProgressIndicator.adaptive(
                                strokeWidth: 2,
                              ),
                            );
                          }
                          final contacts = snapshot.data!;
                          return ListView.builder(
                            physics: const NeverScrollableScrollPhysics(),
                            shrinkWrap: true,
                            itemCount: contacts.length,
                            itemBuilder: (BuildContext context, int i) =>
                                _InviteContactListTile(
                                  user: contacts[i],
                                  profile: Profile(
                                    avatarUrl: contacts[i].avatarUrl,
                                    displayName:
                                        contacts[i].displayName ??
                                        contacts[i].id.localpart ??
                                        L10n.of(context).user,
                                    userId: contacts[i].id,
                                  ),
                                  isMember: participants.contains(
                                    contacts[i].id,
                                  ),
                                  onTap: () => inviteAction(
                                    context,
                                    contacts[i].id,
                                    contacts[i].displayName ??
                                        contacts[i].id.localpart ??
                                        L10n.of(context).user,
                                  ),
                                ),
                          );
                        },
                      );
              },
            ),
          ],
        ),
      ),
    );
  }
}


class _InviteContactListTile extends StatelessWidget {
  final Profile profile;
  final User? user;
  final bool isMember;
  final void Function() onTap;

  const _InviteContactListTile({
    required this.profile,
    this.user,
    required this.isMember,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);

    return ListTile(
      leading: Avatar(
        mxContent: profile.avatarUrl,
        name: profile.displayName,
        presenceUserId: profile.userId,
        onTap: () => UserDialog.show(context: context, profile: profile),
      ),
      title: Text(
        profile.displayName ?? profile.userId.localpart ?? l10n.user,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        profile.userId,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: theme.colorScheme.secondary),
      ),
      trailing: TextButton(
        onPressed: isMember ? null : onTap,
        child: Text(isMember ? l10n.participant : l10n.invite),
      ),
    );
  }
}
