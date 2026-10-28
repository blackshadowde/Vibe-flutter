// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:vibe/l10n/l10n.dart';
import 'package:vibe/vibe/screens/new_private_chat/qr_scanner_modal.dart';
import 'package:vibe/utils/adaptive_bottom_sheet.dart';
import 'package:vibe/utils/vibe_share.dart';
import 'package:vibe/utils/platform_infos.dart';
import 'package:vibe/utils/url_launcher.dart';
import 'package:vibe/widgets/matrix.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:matrix/matrix.dart';
import 'package:vibe/widgets/adaptive_dialogs/user_dialog.dart';
import 'package:vibe/config/app_config.dart';
import 'package:vibe/config/themes.dart';
import 'package:vibe/utils/localized_exception_extension.dart';
import 'package:vibe/widgets/avatar.dart';
import 'package:vibe/widgets/layouts/max_width_body.dart';
import 'package:go_router/go_router.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:vibe/widgets/qr_code_viewer.dart';

class NewPrivateChat extends StatefulWidget {
  final String? deeplink;
  const NewPrivateChat({super.key, required this.deeplink});

  @override
  _NewPrivateChatState createState() => _NewPrivateChatState();
}

class _NewPrivateChatState extends State<NewPrivateChat> {
  final TextEditingController controller = TextEditingController();
  final FocusNode textFieldFocus = FocusNode();

  Future<List<Profile>>? searchResponse;

  Timer? _searchCoolDown;

  static const Duration _coolDown = Duration(milliseconds: 500);

  @override
  void initState() {
    super.initState();

    final deeplink = widget.deeplink;
    if (deeplink != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        UrlLauncher(context, deeplink).openMatrixToUrl();
      });
    }
  }

  Future<void> searchUsers([String? input]) async {
    final searchTerm = input ?? controller.text;
    if (searchTerm.isEmpty) {
      _searchCoolDown?.cancel();
      setState(() {
        searchResponse = _searchCoolDown = null;
      });
      return;
    }

    _searchCoolDown?.cancel();
    _searchCoolDown = Timer(_coolDown, () {
      setState(() {
        searchResponse = _searchUser(searchTerm);
      });
    });
  }

  Future<List<Profile>> _searchUser(String searchTerm) async {
    final result = await Matrix.of(
      context,
    ).client.searchUserDirectory(searchTerm);
    final profiles = result.results;

    if (searchTerm.isValidMatrixIdStrict() &&
        searchTerm.sigil == '@' &&
        !profiles.any((profile) => profile.userId == searchTerm)) {
      profiles.add(Profile(userId: searchTerm));
    }

    return profiles;
  }

  void inviteAction() => VibeShare.shareInviteLink(context);

  Future<void> openScannerAction() async {
    final l10n = L10n.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    if (PlatformInfos.isAndroid) {
      final info = await DeviceInfoPlugin().androidInfo;
      if (!mounted) return;
      if (info.version.sdkInt < 21) {
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text(l10n.unsupportedAndroidVersionLong)),
        );
        return;
      }
    }
    if (!mounted) return;
    await showAdaptiveBottomSheet(
      context: context,
      builder: (_) => QrScannerModal(
        onScan: (link) => UrlLauncher(context, link).openMatrixToUrl(),
      ),
    );
  }

  Future<void> copyUserId() async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final l10n = L10n.of(context);
    await Clipboard.setData(
      ClipboardData(text: Matrix.of(context).client.userID!),
    );
    if (!mounted) return;
    scaffoldMessenger.showSnackBar(
      SnackBar(content: Text(l10n.copiedToClipboard)),
    );
  }

  void openUserModal(Profile profile) =>
      UserDialog.show(context: context, profile: profile);

  @override
  void dispose() {
    controller.dispose();
    textFieldFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final searchResponse = this.searchResponse;
    final userId = Matrix.of(context).client.userID!;
    return Scaffold(
      appBar: AppBar(
        scrolledUnderElevation: 0,
        leading: const Center(child: BackButton()),
        title: Text(L10n.of(context).newChat),
        backgroundColor: theme.scaffoldBackgroundColor,
        actions: [
          TextButton(
            onPressed: UrlLauncher(
              context,
              AppConfig.startChatTutorial,
            ).launchUrl,
            child: Text(L10n.of(context).help),
          ),
        ],
      ),
      body: MaxWidthBody(
        withScrolling: false,
        innerPadding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 8.0,
              ),
              child: TextField(
                controller: controller,
                onChanged: searchUsers,
                decoration: InputDecoration(
                  hintText: L10n.of(context).searchForUsers,
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
                  prefixIcon: searchResponse == null
                      ? const Icon(Icons.search_outlined)
                      : FutureBuilder(
                          future: searchResponse,
                          builder: (context, snapshot) {
                            if (snapshot.connectionState !=
                                ConnectionState.done) {
                              return const Padding(
                                padding: EdgeInsets.all(10.0),
                                child: SizedBox.square(
                                  dimension: 24,
                                  child: CircularProgressIndicator.adaptive(
                                    strokeWidth: 1,
                                  ),
                                ),
                              );
                            }
                            return const Icon(Icons.search_outlined);
                          },
                        ),
                  suffixIcon: controller.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear_outlined),
                          onPressed: () {
                            controller.clear();
                            searchUsers();
                          },
                        ),
                ),
              ),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: VibeThemes.animationDuration,
                child: searchResponse == null
                    ? ListView(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18.0,
                            ),
                            child: SelectableText.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: L10n.of(context).yourGlobalUserIdIs,
                                  ),
                                  TextSpan(
                                    text: Matrix.of(context).client.userID,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              style: TextStyle(
                                color: theme.colorScheme.onSurface,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          ListTile(
                            leading: CircleAvatar(
                              backgroundColor:
                                  theme.colorScheme.secondaryContainer,
                              foregroundColor:
                                  theme.colorScheme.onSecondaryContainer,
                              child: Icon(Icons.adaptive.share_outlined),
                            ),
                            title: Text(L10n.of(context).shareInviteLink),
                            onTap: inviteAction,
                          ),
                          ListTile(
                            leading: CircleAvatar(
                              backgroundColor:
                                  theme.colorScheme.tertiaryContainer,
                              foregroundColor:
                                  theme.colorScheme.onTertiaryContainer,
                              child: const Icon(Icons.group_add_outlined),
                            ),
                            title: Text(L10n.of(context).createGroup),
                            onTap: () => context.go('/rooms/newgroup'),
                          ),
                          if (PlatformInfos.isMobile)
                            ListTile(
                              leading: CircleAvatar(
                                backgroundColor:
                                    theme.colorScheme.primaryContainer,
                                foregroundColor:
                                    theme.colorScheme.onPrimaryContainer,
                                child: const Icon(
                                  Icons.qr_code_scanner_outlined,
                                ),
                              ),
                              title: Text(L10n.of(context).scanQrCode),
                              onTap: openScannerAction,
                            ),
                          Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 64.0,
                                vertical: 24.0,
                              ),
                              child: Material(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    AppConfig.borderRadius,
                                  ),
                                  side: BorderSide(
                                    width: 3,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                                color: Colors.transparent,
                                clipBehavior: Clip.hardEdge,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(
                                    AppConfig.borderRadius,
                                  ),
                                  onTap: () =>
                                      showQrCodeViewer(context, userId),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 200,
                                      ),
                                      child: PrettyQrView.data(
                                        data: 'https://matrix.to/#/$userId',
                                        decoration: PrettyQrDecoration(
                                          shape: PrettyQrSmoothSymbol(
                                            roundFactor: 1,
                                            color: theme.colorScheme.primary,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                    : FutureBuilder(
                        future: searchResponse,
                        builder: (context, snapshot) {
                          final result = snapshot.data;
                          final error = snapshot.error;
                          if (error != null) {
                            return Column(
                              mainAxisAlignment: .center,
                              children: [
                                Text(
                                  error.toLocalizedString(context),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: theme.colorScheme.error,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                OutlinedButton.icon(
                                  onPressed: searchUsers,
                                  icon: const Icon(Icons.refresh_outlined),
                                  label: Text(L10n.of(context).tryAgain),
                                ),
                              ],
                            );
                          }
                          if (result == null) {
                            return const Center(
                              child: CircularProgressIndicator.adaptive(),
                            );
                          }
                          if (result.isEmpty) {
                            return Column(
                              mainAxisAlignment: .center,
                              children: [
                                const Icon(Icons.search_outlined, size: 86),
                                Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Text(
                                    L10n.of(context).noUsersFoundWithQuery(
                                      controller.text,
                                    ),
                                    style: TextStyle(
                                      color: theme.colorScheme.primary,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],
                            );
                          }
                          return ListView.builder(
                            itemCount: result.length,
                            itemBuilder: (context, i) {
                              final contact = result[i];
                              final displayname =
                                  contact.displayName ??
                                  contact.userId.localpart ??
                                  contact.userId;
                              return ListTile(
                                leading: Avatar(
                                  name: displayname,
                                  mxContent: contact.avatarUrl,
                                  presenceUserId: contact.userId,
                                ),
                                title: Text(displayname),
                                subtitle: Text(contact.userId),
                                onTap: () => openUserModal(contact),
                              );
                            },
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

