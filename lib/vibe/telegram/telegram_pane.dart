// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:fluffychat/utils/string_color.dart';
import 'package:fluffychat/vibe/telegram/telegram_chat_page.dart';
import 'package:fluffychat/vibe/telegram/vibe_telegram.dart';
import 'package:fluffychat/vibe/vibe_motion.dart';
import 'package:flutter/material.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

const Color _blurple = Color(0xFF5865F2);

/// The middle pane when the Telegram icon in the rail is selected: the
/// login steps, or the list of Telegram chats.
class TelegramPane extends StatefulWidget {
  const TelegramPane({super.key});

  @override
  State<TelegramPane> createState() => _TelegramPaneState();
}

class _TelegramPaneState extends State<TelegramPane> {
  final _tg = VibeTelegram.instance;
  final _filter = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tg.addListener(_changed);
    _tg.start();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tg.removeListener(_changed);
    _filter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Widget body;
    if (!VibeTelegram.configured) {
      body = const _Notice(
        icon: Icons.key_off_outlined,
        title: 'Telegram isn\'t set up in this build',
        text:
            'Add the TG_API_ID and TG_API_HASH secrets to the Vibe-flutter '
            'repository on GitHub, then build Vibe again.',
      );
    } else if (!_tg.checked) {
      body = const Center(child: CircularProgressIndicator.adaptive());
    } else if (_tg.version == null) {
      body = const _Notice(
        icon: Icons.extension_off_outlined,
        title: 'Telegram isn\'t included in this build',
        text:
            'Run the "Build TDLib" workflow once on GitHub, then build Vibe '
            'again.',
      );
    } else if (_tg.ready) {
      body = _ChatList(filter: _filter, onFilter: () => setState(() {}));
    } else if (_tg.auth.isEmpty ||
        _tg.auth == 'authorizationStateWaitTdlibParameters' ||
        _tg.auth == 'authorizationStateClosing' ||
        _tg.auth == 'authorizationStateClosed' ||
        _tg.auth == 'authorizationStateLoggingOut') {
      body = const Center(child: CircularProgressIndicator.adaptive());
    } else {
      body = _Login(state: _tg.auth, data: _tg.authState);
    }
    return Material(
      color: theme.colorScheme.surface,
      child: SafeArea(bottom: false, child: body),
    );
  }
}

class _Notice extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;
  const _Notice({required this.icon, required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: cs.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Login: phone number (or QR from another device) → code → 2-step password.
// ---------------------------------------------------------------------------

class _Login extends StatefulWidget {
  final String state;
  final Map<String, dynamic> data;
  const _Login({required this.state, required this.data});

  @override
  State<_Login> createState() => _LoginState();
}

class _LoginState extends State<_Login> {
  final _input = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void didUpdateWidget(_Login old) {
    super.didUpdateWidget(old);
    if (old.state != widget.state) {
      _input.clear();
      _error = null;
    }
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final tg = VibeTelegram.instance;
    final cs = Theme.of(context).colorScheme;
    String title;
    String hint = '';
    String help = '';
    TextInputType keyboard = TextInputType.text;
    bool obscure = false;
    Future<void> Function()? submit;
    Widget? extra;

    switch (widget.state) {
      case 'authorizationStateWaitPhoneNumber':
        title = 'Log in to Telegram';
        hint = '+91 98765 43210';
        help = 'Your phone number with the country code.';
        keyboard = TextInputType.phone;
        submit = () => tg.sendPhone(_input.text.replaceAll(' ', ''));
        extra = TextButton.icon(
          onPressed: _busy ? null : () => _run(tg.requestQr),
          icon: const Icon(Icons.qr_code_2),
          label: const Text('Log in with a QR code instead'),
        );
      case 'authorizationStateWaitCode':
        final info = (widget.data['code_info'] as Map?) ?? const {};
        final type = (info['type'] as Map?)?['@type'] as String? ?? '';
        title = 'Enter the code';
        hint = 'Code';
        help = type == 'authenticationCodeTypeTelegramMessage'
            ? 'Telegram sent the code to your Telegram app on another device.'
            : 'Telegram sent a code to ${info['phone_number'] ?? 'your phone'}.';
        keyboard = TextInputType.number;
        submit = () => tg.sendCode(_input.text.trim());
      case 'authorizationStateWaitPassword':
        final pwHint = widget.data['password_hint'] as String? ?? '';
        title = 'Two-step verification';
        hint = 'Password';
        help = pwHint.isEmpty
            ? 'Your account has a password. Enter it to continue.'
            : 'Password hint: $pwHint';
        obscure = true;
        submit = () => tg.sendPassword(_input.text);
      case 'authorizationStateWaitOtherDeviceConfirmation':
        final link = widget.data['link'] as String? ?? '';
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'Scan with Telegram',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'On a phone where you\'re logged in to Telegram: Settings → '
              'Devices → Link Desktop Device, then scan this code.',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            Center(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: SizedBox(
                  width: 220,
                  height: 220,
                  child: PrettyQrView.data(
                    data: link,
                    decoration: PrettyQrDecoration(
                      shape: PrettyQrSmoothSymbol(
                        roundFactor: 1,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      case 'authorizationStateWaitRegistration':
        return const _Notice(
          icon: Icons.person_add_disabled_outlined,
          title: 'No Telegram account yet',
          text:
              'Create your account in the Telegram app first, then log in '
              'here.',
        );
      case 'authorizationStateWaitEmailAddress':
      case 'authorizationStateWaitEmailCode':
      case 'authorizationStateWaitPremiumPurchase':
        return const _Notice(
          icon: Icons.mark_email_unread_outlined,
          title: 'Finish this step in Telegram',
          text:
              'Telegram is asking for something Vibe can\'t do yet (an email '
              'or a purchase). Log in with the QR code instead, or finish it '
              'in the Telegram app and try again.',
        );
      default:
        return const Center(child: CircularProgressIndicator.adaptive());
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
      children: [
        Center(
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: const Color(0xFF2AABEE),
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Icon(Icons.send_rounded, color: Colors.white, size: 36),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          help,
          textAlign: TextAlign.center,
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _input,
          autofocus: true,
          keyboardType: keyboard,
          obscureText: obscure,
          onSubmitted: (_) => _busy ? null : _run(submit!),
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: cs.surfaceContainerLowest,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(_error!, style: TextStyle(color: cs.error)),
          ),
        const SizedBox(height: 16),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: _blurple,
            minimumSize: const Size.fromHeight(48),
          ),
          onPressed: _busy ? null : () => _run(submit!),
          child: _busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Next'),
        ),
        if (extra != null) ...[const SizedBox(height: 8), extra],
        const SizedBox(height: 24),
        Text(
          'Telegram inside Vibe is an early preview. Telegram chats are '
          'stored on Telegram\'s servers, like in the Telegram app.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Chat list
// ---------------------------------------------------------------------------

class TgAvatar extends StatelessWidget {
  final String name;
  final Map<String, dynamic>? file;
  final double size;
  const TgAvatar({required this.name, this.file, this.size = 44, super.key});

  @override
  Widget build(BuildContext context) {
    final path = VibeTelegram.instance.pathOf(file);
    final letters = name.trim().isEmpty
        ? '?'
        : name.trim().characters.first.toUpperCase();
    final cs = name.colorScheme;
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: path != null
            ? Image.file(File(path), fit: BoxFit.cover, gaplessPlayback: true)
            : ColoredBox(
                color: cs.primaryContainer,
                child: Center(
                  child: Text(
                    letters,
                    style: TextStyle(
                      fontSize: size * 0.42,
                      color: cs.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

class _ChatList extends StatelessWidget {
  final TextEditingController filter;
  final VoidCallback onFilter;
  const _ChatList({required this.filter, required this.onFilter});

  @override
  Widget build(BuildContext context) {
    final tg = VibeTelegram.instance;
    final theme = Theme.of(context);
    final q = filter.text.trim().toLowerCase();
    final chats = tg.sortedChats
        .where((c) => q.isEmpty || c.title.toLowerCase().contains(q))
        .toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: TextField(
            controller: filter,
            onChanged: (_) => onFilter(),
            decoration: InputDecoration(
              hintText: 'Find a Telegram chat',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerLowest,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'TELEGRAM — ${chats.length}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              PopupMenuButton<String>(
                icon: Icon(
                  Icons.more_horiz,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                onSelected: (v) async {
                  if (v != 'logout') return;
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (c) => AlertDialog(
                      title: const Text('Log out of Telegram?'),
                      content: const Text(
                        'Telegram chats will be removed from this phone. '
                        'Your Vibe chats stay.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(c, false),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(c, true),
                          child: const Text('Log out'),
                        ),
                      ],
                    ),
                  );
                  if (ok == true) await tg.logOut();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'logout',
                    child: Text('Log out of Telegram'),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n.metrics.pixels > n.metrics.maxScrollExtent - 400) {
                tg.loadMoreChats();
              }
              return false;
            },
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 110),
              itemCount: chats.length,
              itemBuilder: (context, i) => VibePressable(
                scale: 0.97,
                child: _ChatTile(chat: chats[i]),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ChatTile extends StatelessWidget {
  final TgChat chat;
  const _ChatTile({required this.chat});

  @override
  Widget build(BuildContext context) {
    final tg = VibeTelegram.instance;
    final cs = Theme.of(context).colorScheme;
    final last = chat.lastMessage;
    var preview = VibeTelegram.preview(last);
    if (last != null && last['is_outgoing'] == true) {
      preview = 'You: $preview';
    } else if (last != null && chat.userId == null && !chat.isChannel) {
      final who = tg.senderName(last);
      if (who.isNotEmpty) preview = '${who.split(' ').first}: $preview';
    }
    final unread = chat.unread > 0;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => TelegramChatPage.open(context, chat),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Row(
          children: [
            TgAvatar(name: chat.title, file: chat.photo),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (chat.pinned)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Icon(
                            Icons.push_pin,
                            size: 13,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      Expanded(
                        child: Text(
                          chat.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: unread ? FontWeight.bold : FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    preview.replaceAll('\n', ' '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      color: unread ? cs.onSurface : cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (unread)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: cs.error,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  chat.unread > 999 ? '999+' : '${chat.unread}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: cs.onError,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
