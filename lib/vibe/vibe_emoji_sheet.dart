// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:fluffychat/vibe/vibe_animated_emoji.dart';
import 'package:fluffychat/vibe/vibe_haptics.dart';
import 'package:fluffychat/vibe/vibe_motion.dart';
import 'package:fluffychat/vibe/vibe_settings_style.dart';
import 'package:flutter/material.dart';

const Color _blurple = Color(0xFF5865F2);

/// Vibe's emoji picker for reactions: Vibe colours, a search box at the top,
/// a row of animated favourites, then every emoji by category.
abstract class VibeEmojiSheet {
  static const _popular = ['❤️', '👍', '😂', '🔥', '😮', '😢', '🎉', '🙏'];

  static Future<String?> pick(BuildContext context) {
    return showVibeSheet<String>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: VibeSettingsStyle.page(context),
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => const RepaintBoundary(child: _Sheet()),
    );
  }
}

class _Sheet extends StatefulWidget {
  const _Sheet();

  @override
  State<_Sheet> createState() => _SheetState();
}

class _SheetState extends State<_Sheet> {
  final _search = TextEditingController();
  final _focus = FocusNode();
  final _utils = EmojiPickerUtils();
  List<Emoji> _results = const [];
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _onSearch(String q) async {
    final query = q.trim();
    setState(() => _query = query);
    if (query.isEmpty) {
      setState(() => _results = const []);
      return;
    }
    final found = await _utils.searchEmoji(query, defaultEmojiSet);
    if (!mounted || _query != query) return;
    setState(() => _results = found);
  }

  void _pick(String emoji) {
    VibeHaptics.selection();
    Navigator.of(context).pop(emoji);
  }

  @override
  Widget build(BuildContext context) {
    final page = VibeSettingsStyle.page(context);
    final card = VibeSettingsStyle.card(context);
    final t1 = VibeSettingsStyle.text(context);
    final t2 = VibeSettingsStyle.text2(context);
    final height = MediaQuery.sizeOf(context).height * 0.62;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;

    final searchBox = Container(
      height: 44,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Icon(Icons.search, size: 22, color: t2),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _search,
              focusNode: _focus,
              onChanged: _onSearch,
              textInputAction: TextInputAction.search,
              cursorColor: _blurple,
              style: TextStyle(color: t1, fontSize: 16),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: 'Search emoji',
                hintStyle: TextStyle(color: t2, fontSize: 16),
              ),
            ),
          ),
          if (_query.isNotEmpty)
            GestureDetector(
              onTap: () {
                _search.clear();
                _onSearch('');
              },
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(Icons.close, size: 20, color: t2),
              ),
            ),
        ],
      ),
    );

    final popular = SizedBox(
      height: 52,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (final e in VibeEmojiSheet._popular)
            InkResponse(
              radius: 26,
              onTap: () => _pick(e),
              child: VibeAnimatedEmoji(e, size: 34),
            ),
        ],
      ),
    );

    final Widget body;
    if (_query.isNotEmpty) {
      body = _results.isEmpty
          ? Center(
              child: Text(
                'No emoji found for “$_query”',
                style: TextStyle(color: t2),
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 8,
              ),
              itemCount: _results.length,
              itemBuilder: (_, i) => InkResponse(
                onTap: () => _pick(_results[i].emoji),
                child: Center(
                  child: Text(
                    _results[i].emoji,
                    style: const TextStyle(fontSize: 28),
                  ),
                ),
              ),
            );
    } else {
      body = EmojiPicker(
        onEmojiSelected: (_, e) => _pick(e.emoji),
        config: Config(
          height: null,
          locale: Localizations.localeOf(context),
          emojiViewConfig: EmojiViewConfig(
            backgroundColor: page,
            columns: 8,
            emojiSizeMax: 30,
            gridPadding: const EdgeInsets.symmetric(horizontal: 6),
            noRecents: Center(
              child: Text(
                'Emoji you use show up here',
                style: TextStyle(color: t2),
              ),
            ),
          ),
          categoryViewConfig: CategoryViewConfig(
            initCategory: Category.SMILEYS,
            backgroundColor: page,
            indicatorColor: _blurple,
            iconColor: t2.withAlpha(150),
            iconColorSelected: _blurple,
            backspaceColor: t2,
            dividerColor: VibeSettingsStyle.line(context),
          ),
          skinToneConfig: SkinToneConfig(
            dialogBackgroundColor: card,
            indicatorColor: t2,
          ),
          bottomActionBarConfig: const BottomActionBarConfig(enabled: false),
          searchViewConfig: SearchViewConfig(
            backgroundColor: page,
            buttonIconColor: t2,
          ),
        ),
      );
    }

    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.only(bottom: keyboard),
      child: SizedBox(
        height: height,
        child: Column(
          children: [
            searchBox,
            if (_query.isEmpty) popular,
            // The big emoji grid is built once the pane has slid up.
            Expanded(child: VibeSettled(child: body)),
          ],
        ),
      ),
    );
  }
}
