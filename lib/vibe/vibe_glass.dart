// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/services.dart';
import 'package:vibe/widgets/future_loading_dialog.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:vibe/config/setting_keys.dart';
import 'package:vibe/utils/file_selector.dart';
import 'package:vibe/vibe/vibe_palette.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:matrix/matrix.dart';
import 'package:path_provider/path_provider.dart';

/// A palette in the style of the HyDE themes (Hyprland dotfiles, GPL-3.0;
/// the colour sets are the themes' public palettes).
class VibeGlassPalette {
  final String id;
  final String name;
  final Color accent, onAccent, base, mantle, crust, s0, s1, text, sub, tert;

  /// The HyDE theme with this palette's wallpapers (branch and folder in
  /// github.com/HyDE-Project/hyde-themes), if there is one.
  final String? hydeBranch;
  final String? hydeDir;
  const VibeGlassPalette({
    required this.id,
    required this.name,
    this.hydeBranch,
    this.hydeDir,
    required this.accent,
    required this.onAccent,
    required this.base,
    required this.mantle,
    required this.crust,
    required this.s0,
    required this.s1,
    required this.text,
    required this.sub,
    required this.tert,
  });
}

/// The Glass look: a wallpaper behind everything, blurred once when you
/// pick it (so it costs nothing while you use the app), see-through panels
/// on top, and colours from the picture ("wallbash") or a palette.
/// A chat can have its own wallpaper.
///
/// Only colours and backgrounds change: nothing here wraps or rebuilds the
/// app's core (the Matrix connection), so notifications aren't touched.
abstract class VibeGlass {
  /// Bumped when the wallpaper or palette changes (backgrounds redraw).
  static final version = ValueNotifier<int>(0);

  static const _t = 'Configs/.config/hyde/themes';

  /// A dark palette around one colour (HyDE themes we only know the
  /// accent of).
  static VibeGlassPalette _seeded(
    String id,
    String name,
    Color seed, {
    String? branch,
    String? dir,
  }) {
    final w = _wallbash(seed);
    return VibeGlassPalette(
      id: id,
      name: name,
      hydeBranch: branch,
      hydeDir: dir,
      accent: w.accent,
      onAccent: w.onAccent,
      base: w.base,
      mantle: w.mantle,
      crust: w.crust,
      s0: w.s0,
      s1: w.s1,
      text: w.text,
      sub: w.sub,
      tert: w.tert,
    );
  }

  static final palettes = <VibeGlassPalette>[
    const VibeGlassPalette(
      id: 'catppuccin',
      hydeBranch: 'Catppuccin-Mocha',
      hydeDir: '$_t/Catppuccin Mocha/wallpapers',
      name: 'Catppuccin',
      accent: Color(0xFFCBA6F7),
      onAccent: Color(0xFF1E1E2E),
      base: Color(0xFF1E1E2E),
      mantle: Color(0xFF181825),
      crust: Color(0xFF11111B),
      s0: Color(0xFF313244),
      s1: Color(0xFF45475A),
      text: Color(0xFFCDD6F4),
      sub: Color(0xFFA6ADC8),
      tert: Color(0xFFA6E3A1),
    ),
    const VibeGlassPalette(
      id: 'tokyonight',
      hydeBranch: 'Tokyo-Night',
      hydeDir: '$_t/Tokyo Night/wallpapers',
      name: 'Tokyo Night',
      accent: Color(0xFF7AA2F7),
      onAccent: Color(0xFF1A1B26),
      base: Color(0xFF1A1B26),
      mantle: Color(0xFF16161E),
      crust: Color(0xFF101014),
      s0: Color(0xFF24283B),
      s1: Color(0xFF414868),
      text: Color(0xFFC0CAF5),
      sub: Color(0xFFA9B1D6),
      tert: Color(0xFF9ECE6A),
    ),
    const VibeGlassPalette(
      id: 'rosepine',
      hydeBranch: 'Rose-Pine',
      hydeDir: '$_t/Rosé Pine/wallpapers',
      name: 'Rosé Pine',
      accent: Color(0xFFC4A7E7),
      onAccent: Color(0xFF191724),
      base: Color(0xFF191724),
      mantle: Color(0xFF16141F),
      crust: Color(0xFF110F18),
      s0: Color(0xFF26233A),
      s1: Color(0xFF403D52),
      text: Color(0xFFE0DEF4),
      sub: Color(0xFF908CAA),
      tert: Color(0xFF9CCFD8),
    ),
    const VibeGlassPalette(
      id: 'gruvbox',
      hydeBranch: 'Gruvbox-Retro',
      hydeDir: '$_t/Gruvbox Retro/wallpapers',
      name: 'Gruvbox',
      accent: Color(0xFFFABD2F),
      onAccent: Color(0xFF282828),
      base: Color(0xFF282828),
      mantle: Color(0xFF1D2021),
      crust: Color(0xFF151515),
      s0: Color(0xFF3C3836),
      s1: Color(0xFF504945),
      text: Color(0xFFEBDBB2),
      sub: Color(0xFFBDAE93),
      tert: Color(0xFFB8BB26),
    ),
    const VibeGlassPalette(
      id: 'nord',
      hydeBranch: 'Nordic-Blue',
      hydeDir: '$_t/Nordic Blue/walls',
      name: 'Nord',
      accent: Color(0xFF88C0D0),
      onAccent: Color(0xFF2E3440),
      base: Color(0xFF2E3440),
      mantle: Color(0xFF2A2F3A),
      crust: Color(0xFF232831),
      s0: Color(0xFF3B4252),
      s1: Color(0xFF434C5E),
      text: Color(0xFFECEFF4),
      sub: Color(0xFFD8DEE9),
      tert: Color(0xFFA3BE8C),
    ),
    const VibeGlassPalette(
      id: 'dracula',
      name: 'Dracula',
      accent: Color(0xFFBD93F9),
      onAccent: Color(0xFF282A36),
      base: Color(0xFF282A36),
      mantle: Color(0xFF21222C),
      crust: Color(0xFF191A21),
      s0: Color(0xFF44475A),
      s1: Color(0xFF6272A4),
      text: Color(0xFFF8F8F2),
      sub: Color(0xFFBFC2D4),
      tert: Color(0xFF50FA7B),
    ),
    // the other HyDE themes (accent from each theme's window border)
    _seeded('latte', 'Catppuccin Latte', const Color(0xFF8839EF),
        branch: 'Catppuccin-Latte', dir: '$_t/Catppuccin Latte/wallpapers'),
    _seeded('decay', 'Decay Green', const Color(0xFF90CEAA),
        branch: 'Decay-Green', dir: '$_t/Decay Green/wallpapers'),
    _seeded('edgerunner', 'Edge Runner', const Color(0xFFFADA16),
        branch: 'Edge-Runner', dir: '$_t/Edge Runner/wallpapers'),
    _seeded('frosted', 'Frosted Glass', const Color(0xFF2770C0),
        branch: 'Frosted-Glass', dir: '$_t/Frosted Glass/wallpapers'),
    const VibeGlassPalette(
      id: 'graphite',
      name: 'Graphite Mono',
      hydeBranch: 'Graphite-Mono',
      hydeDir: '$_t/Graphite Mono/wallpapers',
      accent: Color(0xFFD9D9D9),
      onAccent: Color(0xFF1A1A1A),
      base: Color(0xFF1C1C1C),
      mantle: Color(0xFF161616),
      crust: Color(0xFF101010),
      s0: Color(0xFF2A2A2A),
      s1: Color(0xFF3A3A3A),
      text: Color(0xFFEDEDED),
      sub: Color(0xFFA6A6A6),
      tert: Color(0xFFBFBFBF),
    ),
    _seeded('sakura', 'Material Sakura', const Color(0xFFB4637A),
        branch: 'Material-Sakura', dir: '$_t/Material Sakura/wallpapers'),
    _seeded('synthwave', 'Synth Wave', const Color(0xFF03EDF9),
        branch: 'Synth-Wave', dir: '$_t/Synth Wave/wallpapers'),
  ];

  /// 'wallbash' (from the wallpaper) or one of [palettes].
  static String get paletteId => AppSettings.vibeGlassPalette.value;

  /// The palette in use.
  static VibeGlassPalette get palette {
    final id = paletteId;
    for (final p in palettes) {
      if (p.id == id) return p;
    }
    return _wallbash(Color(AppSettings.vibeGlassSeed.value));
  }

  /// Wallbash: a dark palette built around the wallpaper's main colour.
  static VibeGlassPalette _wallbash(Color seed) {
    final s = ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark);
    return VibeGlassPalette(
      id: 'wallbash',
      name: 'From wallpaper',
      accent: s.primary,
      onAccent: s.onPrimary,
      base: s.surface,
      mantle: s.surfaceContainerLow,
      crust: s.surfaceContainerLowest,
      s0: s.surfaceContainerHigh,
      s1: s.surfaceContainerHighest,
      text: s.onSurface,
      sub: s.onSurfaceVariant,
      tert: s.tertiary,
    );
  }

  /// The app's colours in the Glass look: the panels are see-through so
  /// the (blurred) wallpaper glows through; text stays solid.
  static ColorScheme get scheme {
    final p = palette;
    return ColorScheme(
      brightness: Brightness.dark,
      primary: p.accent,
      onPrimary: p.onAccent,
      primaryContainer: Color.alphaBlend(p.accent.withAlpha(0x59), p.base),
      onPrimaryContainer: p.text,
      secondary: p.sub,
      onSecondary: p.base,
      secondaryContainer: p.s0.withAlpha(0xCC),
      onSecondaryContainer: p.text,
      tertiary: p.tert,
      onTertiary: p.base,
      tertiaryContainer: p.s1.withAlpha(0xCC),
      onTertiaryContainer: p.text,
      error: const Color(0xFFF23F42),
      onError: Colors.white,
      errorContainer: const Color(0xFF5A1D1E),
      onErrorContainer: const Color(0xFFFFDAD9),
      surface: p.base.withAlpha(0x73),
      onSurface: p.text,
      surfaceContainerLowest: p.crust.withAlpha(0x59),
      surfaceContainerLow: p.mantle.withAlpha(0x99),
      surfaceContainer: p.base.withAlpha(0xBF),
      surfaceContainerHigh: p.s0.withAlpha(0xE0),
      surfaceContainerHighest: p.s1.withAlpha(0xEB),
      onSurfaceVariant: p.sub,
      outline: p.s1,
      outlineVariant: p.s0,
      inverseSurface: p.text,
      onInverseSurface: p.base,
      inversePrimary: p.accent,
      shadow: Colors.black,
      scrim: Colors.black,
      surfaceTint: Colors.transparent,
    );
  }

  // ---- wallpapers -------------------------------------------------------

  static String _chatKey(String roomId) => 'chat.vibe.glass_chat.$roomId';

  /// The (blurred) wallpaper for a chat, or the app's when [roomId] is
  /// null. A chat without its own returns null.
  static String? pathFor(String? roomId) {
    final p = roomId == null
        ? AppSettings.vibeGlassWallpaper.value
        : (AppSettings.store.getString(_chatKey(roomId)) ?? '');
    if (p.isEmpty || !File(p).existsSync()) return null;
    return p;
  }

  static bool hasChatWallpaper(String roomId) => pathFor(roomId) != null;

  /// Pick a picture: blur it once, keep it, and (for the app wallpaper)
  /// take its main colour for "From wallpaper". Returns false if cancelled.
  static Future<bool> pick(BuildContext context, {String? roomId}) async {
    final files = await selectFiles(context, type: FileType.image);
    if (files.isEmpty) return false;
    final bytes = await files.first.readAsBytes();
    await setFromBytes(bytes, roomId: roomId);
    return true;
  }

  /// Use [bytes] (a picture) as the app's or a chat's wallpaper.
  static Future<void> setFromBytes(Uint8List bytes, {String? roomId, String? name}) async {
    final (jpg, seed) = await Isolate.run(() => _process(bytes));
    final dir = Directory('${(await getApplicationSupportDirectory()).path}/vibe_glass');
    await dir.create(recursive: true);
    final name =
        '${roomId == null ? 'app' : 'chat_${roomId.hashCode.toUnsigned(32)}'}'
        '_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(jpg, flush: true);
    final old = pathFor(roomId);
    if (roomId == null) {
      await AppSettings.vibeGlassWallpaper.setItem(file.path);
      await AppSettings.vibeGlassSeed.setItem(seed);
      await AppSettings.store.setString(_nameKey, name ?? '');
    } else {
      await AppSettings.store.setString(_chatKey(roomId), file.path);
    }
    _delete(old);
    version.value++;
  }

  static const _nameKey = 'chat.vibe.glass_wallpaper_name';

  /// Which HyDE wallpaper the app uses (its file name), if it's one.
  static String get wallpaperName =>
      AppSettings.store.getString(_nameKey) ?? '';

  // ---- HyDE wallpapers, fetched from HyDE's own GitHub on request ----

  static final Map<String, List<VibeHydeWall>> _walls = {};

  /// The wallpapers of [p]'s HyDE theme (names, previews, downloads).
  static Future<List<VibeHydeWall>> hydeWalls(VibeGlassPalette p) async {
    final branch = p.hydeBranch, dir = p.hydeDir;
    if (branch == null || dir == null) return const [];
    final hit = _walls[p.id];
    if (hit != null) return hit;
    final r = await http.get(
      Uri.https(
        'api.github.com',
        '/repos/HyDE-Project/hyde-themes/contents/$dir',
        {'ref': branch},
      ),
      headers: {'Accept': 'application/vnd.github+json'},
    );
    if (r.statusCode != 200) {
      throw Exception('GitHub said ${r.statusCode}');
    }
    final list = <VibeHydeWall>[];
    for (final f in jsonDecode(r.body) as List) {
      if (f is! Map) continue;
      final name = f['name'] as String? ?? '';
      final url = f['download_url'] as String?;
      if (url == null || !RegExp(r'\.(png|jpe?g|webp)$', caseSensitive: false).hasMatch(name)) {
        continue;
      }
      list.add(VibeHydeWall(name, url));
    }
    _walls[p.id] = list;
    return list;
  }

  /// Download a HyDE wallpaper and use it for the whole app.
  static Future<void> useHyde(VibeHydeWall w) async {
    final r = await http.get(Uri.parse(w.url));
    if (r.statusCode != 200) throw Exception('Download failed (${r.statusCode})');
    await setFromBytes(r.bodyBytes, name: w.name);
  }

  /// Remove the app's wallpaper, or a chat's own one (it then shows the
  /// app's).
  static Future<void> remove({String? roomId}) async {
    final old = pathFor(roomId);
    if (roomId == null) {
      await AppSettings.vibeGlassWallpaper.setItem('');
      await AppSettings.store.remove(_nameKey);
    } else {
      await AppSettings.store.remove(_chatKey(roomId));
    }
    _delete(old);
    version.value++;
  }

  /// Hypr Launcher shares its theme: with "Follow Hypr Launcher" on, the
  /// Glass palette matches the launcher's (checked when Vibe comes back).
  static bool launcherFound = false;

  static Future<void> followLauncher() async {
    try {
      final r = await const MethodChannel('vibe/system')
          .invokeMapMethod<String, Object?>('hyprTheme');
      final id = r?['palette'];
      launcherFound = id is String;
      if (id is! String || !AppSettings.vibeGlassFollowLauncher.value) return;
      final known = id == 'wallbash' || palettes.any((p) => p.id == id);
      if (known && id != paletteId) await setPalette(id);
    } catch (_) {}
  }

  static Future<void> setPalette(String id) async {
    await AppSettings.vibeGlassPalette.setItem(id);
    version.value++;
  }

  static void _delete(String? path) {
    if (path == null) return;
    try {
      final f = File(path);
      FileImage(f).evict();
      if (f.existsSync()) f.deleteSync();
    } catch (e) {
      Logs().v('Vibe glass: could not delete old wallpaper', e);
    }
  }

  /// Runs in the background: blur (on a phone-sized copy) and find the
  /// main colour (the most common vivid hue).
  static (Uint8List, int) _process(Uint8List bytes) {
    final src = img.decodeImage(bytes);
    if (src == null) throw Exception('Not a picture');
    final small = src.width > 720 ? img.copyResize(src, width: 720) : src;
    final blurred = img.gaussianBlur(small, radius: 8);
    final jpg = Uint8List.fromList(img.encodeJpg(blurred, quality: 86));

    final tiny = img.copyResize(src, width: 48);
    final weight = List<double>.filled(24, 0);
    final sumR = List<double>.filled(24, 0);
    final sumG = List<double>.filled(24, 0);
    final sumB = List<double>.filled(24, 0);
    for (final p in tiny) {
      final r = p.r / 255, g = p.g / 255, b = p.b / 255;
      final mx = math.max(r, math.max(g, b)), mn = math.min(r, math.min(g, b));
      final sat = mx == 0 ? 0.0 : (mx - mn) / mx;
      if (sat < 0.25 || mx < 0.2) continue; // greys and near-black don't count
      double h;
      final d = mx - mn;
      if (mx == r) {
        h = ((g - b) / d) % 6;
      } else if (mx == g) {
        h = (b - r) / d + 2;
      } else {
        h = (r - g) / d + 4;
      }
      final bucket = ((h / 6) * 24).floor().clamp(0, 23);
      final w = sat * mx;
      weight[bucket] += w;
      sumR[bucket] += r * w;
      sumG[bucket] += g * w;
      sumB[bucket] += b * w;
    }
    var best = -1;
    for (var i = 0; i < 24; i++) {
      if (weight[i] > 0 && (best < 0 || weight[i] > weight[best])) best = i;
    }
    if (best < 0) return (jpg, 0xFF7AA2F7);
    final w = weight[best];
    int c(double v) => (v / w * 255).round().clamp(0, 255);
    final seed =
        0xFF000000 | (c(sumR[best]) << 16) | (c(sumG[best]) << 8) | c(sumB[best]);
    return (jpg, seed);
  }
}

/// One HyDE wallpaper: its file name and download link. The preview is a
/// small copy made by the wsrv.nl image service, so browsing doesn't
/// download full-size pictures.
class VibeHydeWall {
  final String name;
  final String url;
  const VibeHydeWall(this.name, this.url);

  String get title => name
      .replaceAll(RegExp(r'\.(png|jpe?g|webp)$', caseSensitive: false), '')
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .trim();

  String get preview => Uri.https('wsrv.nl', '/', {
    'url': url,
    'w': '180',
    'h': '320',
    'fit': 'cover',
    'output': 'webp',
  }).toString();
}

/// The Glass background (wallpaper or a palette gradient). Draws nothing
/// in the other looks. [roomId]: a chat's own wallpaper (nothing if it has
/// none, so the app's shows through).
class VibeGlassLayer extends StatelessWidget {
  final String? roomId;
  const VibeGlassLayer({this.roomId, super.key});

  @override
  Widget build(BuildContext context) {
    // depends on the theme, so it redraws when the look changes
    Theme.of(context);
    return ValueListenableBuilder<int>(
      valueListenable: VibeGlass.version,
      builder: (context, _, _) {
        if (!VibePalette.isGlass) return const SizedBox.shrink();
        final path = VibeGlass.pathFor(roomId);
        if (roomId != null && path == null) return const SizedBox.shrink();
        final p = VibeGlass.palette;
        final gradient = DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.alphaBlend(p.accent.withAlpha(0x2E), p.base),
                p.mantle,
                Color.alphaBlend(p.tert.withAlpha(0x1F), p.crust),
              ],
            ),
          ),
        );
        return IgnorePointer(
          child: RepaintBoundary(
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (path == null)
                  gradient
                else ...[
                  Image.file(
                    File(path),
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    errorBuilder: (_, _, _) => gradient,
                  ),
                  // keeps text readable over bright pictures
                  ColoredBox(color: p.crust.withAlpha(0x52)),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A page with the Glass background under it. Always the same widget shape
/// (the page never rebuilds when the look changes).
class VibeGlassBackdrop extends StatelessWidget {
  final String? roomId;
  final Widget child;
  const VibeGlassBackdrop({required this.child, this.roomId, super.key});

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned.fill(child: VibeGlassLayer(roomId: roomId)),
      child,
    ],
  );
}

/// Frosted glass behind a pane / bar in the Glass look (live blur of what's
/// underneath, only inside [radius]'s shape).
class VibeGlassBlur extends StatelessWidget {
  final Widget child;
  final BorderRadius radius;
  final double sigma;
  const VibeGlassBlur({
    required this.child,
    this.radius = BorderRadius.zero,
    this.sigma = 22,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    if (!VibePalette.isGlass) return child;
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: child,
      ),
    );
  }
}

/// Settings > Appearance, under "Colours" when Glass is chosen: the
/// wallpaper and the palette.
class VibeGlassSettings extends StatelessWidget {
  const VibeGlassSettings({super.key});

  Future<void> _pick(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await VibeGlass.pick(context);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not use that picture: $e')));
    }
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: VibeGlass.version,
    builder: (context, _, _) {
      final theme = Theme.of(context);
      final path = VibeGlass.pathFor(null);
      final current = VibeGlass.paletteId;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 44,
                height: 44,
                child: path == null
                    ? ColoredBox(
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: const Icon(Icons.wallpaper_outlined),
                      )
                    : Image.file(File(path), fit: BoxFit.cover),
              ),
            ),
            title: const Text('Wallpaper'),
            subtitle: Text(
              path == null
                  ? 'Pick a picture to put behind the glass'
                  : 'Blurred behind every screen',
            ),
            trailing: path == null
                ? null
                : IconButton(
                    tooltip: 'Remove',
                    icon: const Icon(Icons.close),
                    onPressed: () => VibeGlass.remove(),
                  ),
            onTap: () => _pick(context),
          ),
          if (VibeGlass.launcherFound)
            SwitchListTile.adaptive(
              title: const Text('Follow Hypr Launcher'),
              subtitle: const Text('Use the palette chosen in the launcher'),
              value: AppSettings.vibeGlassFollowLauncher.value,
              onChanged: (v) async {
                await AppSettings.vibeGlassFollowLauncher.setItem(v);
                await VibeGlass.followLauncher();
                VibeGlass.version.value++;
              },
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('From wallpaper'),
                  avatar: CircleAvatar(
                    backgroundColor: Color(AppSettings.vibeGlassSeed.value),
                  ),
                  selected: current == 'wallbash',
                  onSelected: (_) => VibeGlass.setPalette('wallbash'),
                ),
                for (final p in VibeGlass.palettes)
                  ChoiceChip(
                    label: Text(p.name),
                    avatar: CircleAvatar(backgroundColor: p.accent),
                    selected: current == p.id,
                    onSelected: (_) => VibeGlass.setPalette(p.id),
                  ),
              ],
            ),
          ),
          // the chosen HyDE theme's wallpapers (fetched from HyDE's GitHub
          // when you open this; only the one you tap is downloaded)
          if (VibeGlass.palette.hydeBranch != null)
            _HydeGallery(palette: VibeGlass.palette),
        ],
      );
    },
  );
}

/// Chat ⋮ menu > Chat wallpaper (Glass look).
abstract class VibeGlassChat {
  static Future<void> choose(BuildContext context, Room room) async {
    final has = VibeGlass.hasChatWallpaper(room.id);
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.wallpaper_outlined),
              title: const Text('Choose a picture for this chat'),
              onTap: () => Navigator.of(c).pop('pick'),
            ),
            if (has)
              ListTile(
                leading: const Icon(Icons.layers_clear_outlined),
                title: const Text('Use the app wallpaper'),
                onTap: () => Navigator.of(c).pop('remove'),
              ),
          ],
        ),
      ),
    );
    if (!context.mounted || choice == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (choice == 'pick') {
        await VibeGlass.pick(context, roomId: room.id);
      } else {
        await VibeGlass.remove(roomId: room.id);
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not use that picture: $e')));
    }
  }
}


class _HydeGallery extends StatefulWidget {
  final VibeGlassPalette palette;
  const _HydeGallery({required this.palette});

  @override
  State<_HydeGallery> createState() => _HydeGalleryState();
}

class _HydeGalleryState extends State<_HydeGallery> {
  late Future<List<VibeHydeWall>> _walls = VibeGlass.hydeWalls(widget.palette);

  @override
  void didUpdateWidget(_HydeGallery old) {
    super.didUpdateWidget(old);
    if (old.palette.id != widget.palette.id) {
      _walls = VibeGlass.hydeWalls(widget.palette);
    }
  }

  Future<void> _use(VibeHydeWall w) async {
    final messenger = ScaffoldMessenger.of(context);
    final r = await showFutureLoadingDialog(
      context: context,
      future: () => VibeGlass.useHyde(w),
    );
    if (r.error != null) {
      messenger.showSnackBar(SnackBar(content: Text('Could not get that wallpaper: ${r.error}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final using = VibeGlass.wallpaperName;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: Text(
            '${widget.palette.name} wallpapers · from HyDE',
            style: TextStyle(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        SizedBox(
          height: 172,
          child: FutureBuilder<List<VibeHydeWall>>(
            future: _walls,
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(
                  child: TextButton.icon(
                    onPressed: () => setState(
                      () => _walls = VibeGlass.hydeWalls(widget.palette),
                    ),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Couldn\'t load the wallpapers. Retry'),
                  ),
                );
              }
              final walls = snap.data;
              if (walls == null) {
                return const Center(child: CircularProgressIndicator.adaptive());
              }
              return ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: walls.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, i) {
                  final w = walls[i];
                  final on = w.name == using;
                  return GestureDetector(
                    onTap: () => _use(w),
                    child: Column(
                      children: [
                        Container(
                          width: 84,
                          height: 140,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: on ? theme.colorScheme.primary : Colors.transparent,
                              width: 2.5,
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Image.network(
                            w.preview,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => ColoredBox(
                              color: theme.colorScheme.surfaceContainerHighest,
                              child: const Icon(Icons.image_outlined),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          width: 84,
                          child: Text(
                            w.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}
