// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:vibe/l10n/l10n.dart';
import 'package:vibe/utils/file_selector.dart';
import 'package:vibe/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart' as sdk;
import 'package:matrix/matrix.dart';
import 'package:vibe/config/themes.dart';
import 'package:vibe/utils/localized_exception_extension.dart';
import 'package:vibe/widgets/avatar.dart';
import 'package:vibe/widgets/layouts/max_width_body.dart';

class NewGroup extends StatefulWidget {
  final CreateGroupType createGroupType;
  final String? spaceId;
  const NewGroup({
    this.createGroupType = CreateGroupType.group,
    this.spaceId,
    super.key,
  });

  @override
  _NewGroupState createState() => _NewGroupState();
}

class _NewGroupState extends State<NewGroup> {
  TextEditingController nameController = TextEditingController();

  bool publicGroup = false;
  bool groupCanBeFound = false;

  Uint8List? avatar;

  Uri? avatarUrl;

  Object? error;

  bool loading = false;

  CreateGroupType get createGroupType =>
      _createGroupType ?? widget.createGroupType;

  CreateGroupType? _createGroupType;

  void setCreateGroupType(Set<CreateGroupType> b) =>
      setState(() => _createGroupType = b.single);

  void setPublicGroup(bool b) =>
      setState(() => publicGroup = groupCanBeFound = b);

  void setGroupCanBeFound(bool b) => setState(() => groupCanBeFound = b);

  Future<void> selectPhoto() async {
    final photo = await selectFiles(
      context,
      type: FileType.image,
      allowMultiple: false,
    );
    final bytes = await photo.singleOrNull?.readAsBytes();

    setState(() {
      avatarUrl = null;
      avatar = bytes;
    });
  }

  Future<void> _createGroup() async {
    if (!mounted) return;
    final client = Matrix.of(context).client;

    final roomId = await client.createGroupChat(
      visibility: groupCanBeFound
          ? sdk.Visibility.public
          : sdk.Visibility.private,
      preset: publicGroup
          ? sdk.CreateRoomPreset.publicChat
          : sdk.CreateRoomPreset.privateChat,
      groupName: nameController.text.isNotEmpty ? nameController.text : null,
      initialState: [
        if (avatar != null)
          sdk.StateEvent(
            type: sdk.EventTypes.RoomAvatar,
            content: {'url': avatarUrl.toString()},
          ),
      ],
    );
    await _addToSpace(roomId);
    if (!mounted) return;

    context.go('/rooms/$roomId/invite');
  }

  Future<void> _createSpace() async {
    if (!mounted) return;
    final spaceId = await Matrix.of(context).client.createRoom(
      preset: publicGroup
          ? sdk.CreateRoomPreset.publicChat
          : sdk.CreateRoomPreset.privateChat,
      creationContent: {'type': RoomCreationTypes.mSpace},
      visibility: publicGroup ? sdk.Visibility.public : null,
      roomAliasName: publicGroup
          ? nameController.text.trim().toLowerCase().replaceAll(' ', '_')
          : null,
      name: nameController.text.trim(),
      powerLevelContentOverride: {'events_default': 100},
      initialState: [
        if (avatar != null)
          sdk.StateEvent(
            type: sdk.EventTypes.RoomAvatar,
            content: {'url': avatarUrl.toString()},
          ),
      ],
    );
    await _addToSpace(spaceId);
    if (!mounted) return;
    context.pop<String>(spaceId);
  }

  Future<void> _addToSpace(String roomId) async {
    final spaceId = widget.spaceId;
    if (spaceId != null) {
      final activeSpace = Matrix.of(context).client.getRoomById(spaceId);
      if (activeSpace == null) {
        throw Exception('Can not add group to space: Space not found $spaceId');
      }
      await activeSpace.postLoad();
      await activeSpace.setSpaceChild(roomId);
    }
  }

  Future<void> submitAction([_]) async {
    final client = Matrix.of(context).client;

    try {
      if (nameController.text.trim().isEmpty &&
          createGroupType == CreateGroupType.space) {
        setState(() => error = L10n.of(context).pleaseFillOut);
        return;
      }

      setState(() {
        loading = true;
        error = null;
      });

      final avatar = this.avatar;
      avatarUrl ??= avatar == null ? null : await client.uploadContent(avatar);

      if (!mounted) return;

      switch (createGroupType) {
        case CreateGroupType.group:
          await _createGroup();
        case CreateGroupType.space:
          await _createSpace();
      }
    } catch (e, s) {
      sdk.Logs().d('Unable to create group', e, s);
      setState(() {
        error = e;
        loading = false;
      });
    }
  }

  @override
  void initState() {
    final spaceId = widget.spaceId;
    if (spaceId != null) {
      final space = Matrix.of(context).client.getRoomById(spaceId);
      publicGroup = space?.joinRules == JoinRules.public;
    }
    super.initState();
  }

  @override
  void dispose() {
    nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final avatar = this.avatar;
    final error = this.error;
    return Scaffold(
      appBar: AppBar(
        leading: Center(
          child: BackButton(
            onPressed: loading ? null : Navigator.of(context).pop,
          ),
        ),
        title: Text(
          createGroupType == CreateGroupType.space
              ? L10n.of(context).newSpace
              : L10n.of(context).createGroup,
        ),
      ),
      body: MaxWidthBody(
        child: Column(
          mainAxisSize: .min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: SegmentedButton<CreateGroupType>(
                selected: {createGroupType},
                onSelectionChanged: setCreateGroupType,
                segments: [
                  ButtonSegment(
                    value: CreateGroupType.group,
                    label: Text(L10n.of(context).group),
                  ),
                  ButtonSegment(
                    value: CreateGroupType.space,
                    label: Text(L10n.of(context).space),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            InkWell(
              borderRadius: BorderRadius.circular(90),
              onTap: loading ? null : selectPhoto,
              child: CircleAvatar(
                radius: Avatar.defaultSize,
                child: avatar == null
                    ? const Icon(Icons.add_a_photo_outlined)
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(90),
                        child: Image.memory(
                          avatar,
                          width: Avatar.defaultSize * 2,
                          height: Avatar.defaultSize * 2,
                          fit: BoxFit.cover,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 32),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: TextField(
                autofocus: true,
                controller: nameController,
                autocorrect: false,
                readOnly: loading,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.people_outlined),
                  labelText: createGroupType == CreateGroupType.space
                      ? L10n.of(context).spaceName
                      : L10n.of(context).groupName,
                ),
              ),
            ),
            const SizedBox(height: 16),
            SwitchListTile.adaptive(
              contentPadding: const EdgeInsets.symmetric(horizontal: 32),
              secondary: const Icon(Icons.public_outlined),
              title: Text(
                createGroupType == CreateGroupType.space
                    ? L10n.of(context).spaceIsPublic
                    : L10n.of(context).groupIsPublic,
              ),
              value: publicGroup,
              onChanged: loading ? null : setPublicGroup,
            ),
            AnimatedSize(
              duration: VibeThemes.animationDuration,
              curve: VibeThemes.animationCurve,
              child: publicGroup
                  ? SwitchListTile.adaptive(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 32,
                      ),
                      secondary: const Icon(Icons.search_outlined),
                      title: Text(L10n.of(context).groupCanBeFoundViaSearch),
                      value: groupCanBeFound,
                      onChanged: loading
                          ? null
                          : setGroupCanBeFound,
                    )
                  : const SizedBox.shrink(),
            ),
            AnimatedSize(
              duration: VibeThemes.animationDuration,
              curve: VibeThemes.animationCurve,
              child: createGroupType == CreateGroupType.space
                  ? const SizedBox.shrink()
                  : SwitchListTile.adaptive(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 32,
                      ),
                      secondary: Icon(
                        Icons.lock_outlined,
                        color: theme.colorScheme.onSurface,
                      ),
                      title: Text(
                        L10n.of(context).enableEncryption,
                        style: TextStyle(color: theme.colorScheme.onSurface),
                      ),
                      value: !publicGroup,
                      onChanged: null,
                    ),
            ),
            AnimatedSize(
              duration: VibeThemes.animationDuration,
              curve: VibeThemes.animationCurve,
              child: createGroupType == CreateGroupType.space
                  ? ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 32,
                      ),
                      trailing: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16.0),
                        child: Icon(Icons.info_outlined),
                      ),
                      subtitle: Text(L10n.of(context).newSpaceDescription),
                    )
                  : const SizedBox.shrink(),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: loading
                      ? null
                      : submitAction,
                  child: loading
                      ? const LinearProgressIndicator()
                      : Text(
                          createGroupType == CreateGroupType.space
                              ? L10n.of(context).createNewSpace
                              : L10n.of(context).createGroupAndInviteUsers,
                        ),
                ),
              ),
            ),
            AnimatedSize(
              duration: VibeThemes.animationDuration,
              curve: VibeThemes.animationCurve,
              child: error == null
                  ? const SizedBox.shrink()
                  : ListTile(
                      leading: Icon(
                        Icons.warning_outlined,
                        color: theme.colorScheme.error,
                      ),
                      title: Text(
                        error.toLocalizedString(context),
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

enum CreateGroupType { group, space }

