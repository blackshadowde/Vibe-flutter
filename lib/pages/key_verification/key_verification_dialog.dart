// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:ui';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/vibe/vibe_security_ui.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';

class KeyVerificationDialog extends StatefulWidget {
  Future<bool?> show(BuildContext context) => showAdaptiveDialog<bool>(
    context: context,
    builder: (context) => this,
    barrierDismissible: false,
  );

  final KeyVerification request;

  const KeyVerificationDialog({super.key, required this.request});

  @override
  KeyVerificationPageState createState() => KeyVerificationPageState();
}

class KeyVerificationPageState extends State<KeyVerificationDialog> {
  void Function()? originalOnUpdate;
  late final List<dynamic> sasEmoji;

  @override
  void initState() {
    originalOnUpdate = widget.request.onUpdate;
    widget.request.onUpdate = () {
      originalOnUpdate?.call();
      setState(() {});
    };
    widget.request.client.getProfileFromUserId(widget.request.userId).then((p) {
      profile = p;
      setState(() {});
    });
    rootBundle.loadString('assets/sas-emoji.json').then((e) {
      sasEmoji = json.decode(e);
      setState(() {});
    });
    super.initState();
  }

  @override
  void dispose() {
    widget.request.onUpdate =
        originalOnUpdate; // don't want to get updates anymore
    if (![
      KeyVerificationState.error,
      KeyVerificationState.done,
    ].contains(widget.request.state)) {
      widget.request.cancel('m.user');
    }
    textEditingController?.dispose();
    super.dispose();
  }

  Profile? profile;

  Future<void> checkInput(String input) async {
    if (input.isEmpty) return;

    final valid = await showFutureLoadingDialog(
      context: context,
      future: () async {
        // make sure the loading spinner shows before we test the keys
        await Future.delayed(const Duration(milliseconds: 100));
        var valid = false;
        try {
          await widget.request.openSSSS(keyOrPassphrase: input);
          valid = true;
        } catch (_) {
          valid = false;
        }
        return valid;
      },
    );
    if (valid.error != null) {
      if (!mounted) return;
      await showOkAlertDialog(
        useRootNavigator: false,
        context: context,
        title: L10n.of(context).incorrectPassphraseOrKey,
      );
    }
  }

  TextEditingController? textEditingController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    User? user;
    final directChatId = widget.request.client.getDirectChatFromUserId(
      widget.request.userId,
    );
    if (directChatId != null) {
      user = widget.request.client
          .getRoomById(directChatId)!
          .unsafeGetUserFromMemoryOrFallback(widget.request.userId);
    }
    final displayName =
        user?.calcDisplayname() ?? widget.request.userId.localpart!;

    var title = L10n.of(context).verifyTitle;
    String? subtitle;
    Widget hero = const VibeHeroIcon(Icons.shield_outlined, size: 64);
    Widget? body;
    final buttons = <Widget>[];

    Widget avatarHero({bool spinner = false}) => Stack(
      alignment: Alignment.center,
      children: [
        Avatar(
          mxContent: user?.avatarUrl,
          name: displayName,
          size: 72,
          client: widget.request.client,
        ),
        if (spinner)
          SizedBox.square(
            dimension: 84,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: cs.primary,
            ),
          ),
      ],
    );

    switch (widget.request.state) {
      case KeyVerificationState.showQRSuccess:
      case KeyVerificationState.confirmQRScan:
        throw 'Not implemented';
      case KeyVerificationState.askSSSS:
        // prompt the user for their ssss passphrase / key
        textEditingController = TextEditingController();
        hero = const VibeHeroIcon(Icons.vpn_key_outlined, size: 64);
        subtitle = L10n.of(context).askSSSSSign;
        body = TextField(
          controller: textEditingController,
          autofocus: false,
          autocorrect: false,
          onSubmitted: checkInput,
          minLines: 1,
          maxLines: 1,
          obscureText: true,
          decoration: vibeFieldDecoration(
            context,
            hint: L10n.of(context).passphraseOrKey,
          ),
        );
        buttons.add(
          VibeButton(
            label: L10n.of(context).submit,
            onPressed: () => checkInput(textEditingController!.text),
          ),
        );
        buttons.add(
          VibeButton(
            label: L10n.of(context).skip,
            tonal: true,
            onPressed: () => widget.request.openSSSS(skip: true),
          ),
        );
        break;
      case KeyVerificationState.askAccept:
        title = L10n.of(context).newVerificationRequest;
        subtitle = L10n.of(context).askVerificationRequest(displayName);
        hero = avatarHero();
        buttons.add(
          VibeButton(
            label: L10n.of(context).accept,
            onPressed: () => widget.request.acceptVerification(),
          ),
        );
        buttons.add(
          VibeButton(
            label: L10n.of(context).reject,
            tonal: true,
            destructive: true,
            onPressed: () => widget.request.rejectVerification().then((_) {
              if (!context.mounted) return;
              Navigator.of(context, rootNavigator: false).pop(false);
            }),
          ),
        );
        break;
      case KeyVerificationState.askChoice:
      case KeyVerificationState.waitingAccept:
        hero = avatarHero(spinner: true);
        subtitle = L10n.of(context).waitingPartnerAcceptRequest;
        buttons.add(
          VibeButton(
            label: L10n.of(context).cancel,
            tonal: true,
            onPressed: () => widget.request.cancel(),
          ),
        );
        break;
      case KeyVerificationState.askSas:
        hero = avatarHero();
        if (widget.request.sasTypes.contains('emoji')) {
          title = L10n.of(context).compareEmojiMatch;
          final emojis = widget.request.sasEmojis;
          Widget row(Iterable<KeyVerificationEmoji> items) => Row(
            children: [
              for (final e in items) Expanded(child: _Emoji(e, sasEmoji)),
            ],
          );
          body = VibeCard(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
            child: Column(
              children: [
                row(emojis.take(4)),
                const SizedBox(height: 10),
                row(emojis.skip(4)),
              ],
            ),
          );
        } else {
          title = L10n.of(context).compareNumbersMatch;
          final numbers = widget.request.sasNumbers;
          final numbstr = '${numbers.first}-${numbers[1]}-${numbers[2]}';
          body = VibeCard(
            padding: const EdgeInsets.symmetric(vertical: 22),
            child: Center(
              child: Text(
                numbstr,
                style: const TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 4,
                ),
              ),
            ),
          );
        }
        buttons.add(
          VibeButton(
            label: L10n.of(context).theyMatch,
            onPressed: () => widget.request.acceptSas(),
          ),
        );
        buttons.add(
          VibeButton(
            label: L10n.of(context).theyDontMatch,
            tonal: true,
            destructive: true,
            onPressed: () => widget.request.rejectSas(),
          ),
        );
        break;
      case KeyVerificationState.waitingSas:
        hero = avatarHero(spinner: true);
        subtitle = widget.request.sasTypes.contains('emoji')
            ? L10n.of(context).waitingPartnerEmoji
            : L10n.of(context).waitingPartnerNumbers;
        break;
      case KeyVerificationState.done:
        title = L10n.of(context).verifySuccess;
        hero = const VibeHeroIcon(Icons.verified_user, size: 64);
        buttons.add(
          VibeButton(
            label: L10n.of(context).close,
            onPressed: () =>
                Navigator.of(context, rootNavigator: false).pop(true),
          ),
        );
        break;
      case KeyVerificationState.error:
        title = 'Verification failed';
        subtitle =
            'Error ${widget.request.canceledCode}: ${widget.request.canceledReason}';
        hero = Container(
          width: 92,
          height: 92,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: cs.error.withAlpha(36),
          ),
          child: Icon(Icons.close, size: 44, color: cs.error),
        );
        buttons.add(
          VibeButton(
            label: L10n.of(context).close,
            tonal: true,
            onPressed: () =>
                Navigator.of(context, rootNavigator: false).pop(false),
          ),
        );
        break;
    }

    return Dialog(
      backgroundColor: cs.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: hero),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.35,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
              if (body != null) ...[const SizedBox(height: 18), body],
              if (buttons.isNotEmpty) ...[
                const SizedBox(height: 20),
                for (var i = 0; i < buttons.length; i++) ...[
                  if (i > 0) const SizedBox(height: 8),
                  buttons[i],
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Emoji extends StatelessWidget {
  final KeyVerificationEmoji emoji;
  final List<dynamic>? sasEmoji;

  const _Emoji(this.emoji, this.sasEmoji);

  String getLocalizedName() {
    final sasEmoji = this.sasEmoji;
    if (sasEmoji == null) {
      // asset is still being loaded
      return emoji.name;
    }
    final translations = Map<String, String?>.from(
      sasEmoji[emoji.number]['translated_descriptions'],
    );
    translations['en'] = emoji.name;
    for (final locale in PlatformDispatcher.instance.locales) {
      final wantLocaleParts = locale.toString().split('_');
      final wantLanguage = wantLocaleParts.removeAt(0);
      for (final haveLocale in translations.keys) {
        final haveLocaleParts = haveLocale.split('_');
        final haveLanguage = haveLocaleParts.removeAt(0);
        if (haveLanguage == wantLanguage &&
            (Set.from(haveLocaleParts)..removeAll(wantLocaleParts)).isEmpty &&
            (translations[haveLocale]?.isNotEmpty ?? false)) {
          return translations[haveLocale]!;
        }
      }
    }
    return emoji.name;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: .min,
      children: <Widget>[
        Text(emoji.emoji, style: const TextStyle(fontSize: 34)),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2.0),
          child: Text(
            getLocalizedName(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
