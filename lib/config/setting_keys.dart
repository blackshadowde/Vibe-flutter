// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:async/async.dart';
import 'package:vibe/utils/platform_infos.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix_api_lite/utils/logs.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Push gateway for Firebase pushes. Vibe no longer uses one (Android has its
/// own connection or ntfy), so it's empty unless a build sets
/// VIBE_PUSH_GATEWAY.
const String _vibeGateway = String.fromEnvironment('VIBE_PUSH_GATEWAY');

/// The gateway older Vibe versions registered; only used to remove those
/// registrations from the Matrix server.
const String vibeLegacyGateway =
    'https://summer-brook-a863.ashishboddu940.workers.dev/_matrix/push/v1/notify';

enum AppSettings<T> {
  textMessageMaxLength<int>('textMessageMaxLength', 16384),

  /// Max lines for unselected HTML/text bubbles; 0 = unlimited (no fade).
  messagePreviewMaxLines<int>('chat.vibe.message_preview_max_lines', 25),
  audioRecordingNumChannels<int>('audioRecordingNumChannels', 1),
  audioRecordingAutoGain<bool>('audioRecordingAutoGain', true),
  audioRecordingEchoCancel<bool>('audioRecordingEchoCancel', false),
  audioRecordingNoiseSuppress<bool>('audioRecordingNoiseSuppress', true),
  audioRecordingBitRate<int>('audioRecordingBitRate', 64000),
  audioRecordingSamplingRate<int>('audioRecordingSamplingRate', 44100),
  showNoGoogle<bool>('chat.vibe.show_no_google', false),
  unifiedPushRegistered<bool>('chat.vibe.unifiedpush.registered', false),
  unifiedPushEndpoint<String>('chat.vibe.unifiedpush.endpoint', ''),
  pushNotificationsGatewayUrl<String>(
    'pushNotificationsGatewayUrl',
    _vibeGateway,
  ),
  pushNotificationsPusherFormat<String>(
    'pushNotificationsPusherFormat',
    'event_id_only',
  ),
  renderHtml<bool>('chat.vibe.renderHtml', true),
  fontSizeFactor<double>('chat.vibe.font_size_factor', 1.0),
  // Telegram-style chat text size 12–30 (0 = not set yet: use the factor).
  vibeTextSize<int>('chat.vibe.text_size', 0),
  hideRedactedEvents<bool>('chat.vibe.hideRedactedEvents', false),
  hideUnknownEvents<bool>('chat.vibe.hideUnknownEvents', true),
  autoplayImages<bool>('chat.vibe.autoplay_images', true),
  sendTypingNotifications<bool>('chat.vibe.send_typing_notifications', true),
  sendPublicReadReceipts<bool>('chat.vibe.send_public_read_receipts', true),
  swipeRightToLeftToReply<bool>('chat.vibe.swipeRightToLeftToReply', true),
  sendOnEnter<bool>('chat.vibe.send_on_enter', false),
  displayNavigationRail<bool>('chat.vibe.display_navigation_rail', false),
  experimentalVoip<bool>('chat.vibe.experimental_voip', false),
  // Keys go only to your cross-signed (verified) devices, like Element
  shareKeysWith<String>('chat.vibe.share_keys_with_3', 'crossVerified'),
  noEncryptionWarningShown<bool>(
    'chat.vibe.no_encryption_warning_shown',
    false,
  ),
  displayChatDetailsColumn('chat.vibe.display_chat_details_column', false),
  // AppConfig-mirrored settings
  applicationName<String>('chat.vibe.application_name', 'Vibe'),
  defaultHomeserver<String>(
    'chat.vibe.default_homeserver',
    'matrix.unredacted.org',
  ),
  // colorSchemeSeed stored as ARGB int
  colorSchemeSeedInt<int>('chat.vibe.color_scheme_seed', 0xFF5865F2),
  emojiSuggestionLocale<String>('emoji_suggestion_locale', ''),
  enableSoftLogout<bool>('chat.vibe.enable_soft_logout', false),
  enableMatrixNativeOIDC<bool>('chat.vibe.enable_matrix_native_oidc', false),
  presetHomeserver<String>('chat.vibe.preset_homeserver', ''),
  welcomeText<String>('chat.vibe.welcome_text', ''),
  website<String>('chat.vibe.website_url', 'https://get-vibe.github.io'),
  logoUrl<String>(
    'chat.vibe.logo_url',
    'https://get-vibe.github.io/assets/icon.png',
  ),
  privacyPolicy<String>(
    'chat.vibe.privacy_policy_url',
    'https://matrix.org/legal/privacy-notice/',
  ),
  tos<String>('chat.vibe.tos_url', 'https://matrix.org/legal/terms-and-conditions/'),
  sendTimelineEventTimeout<int>('chat.vibe.send_timeline_event_timeout', 15),
  webNotificationSound<bool>('chat.vibe.web_notification_sound', true),
  chatFilter<String>('chat.vibe.chat_filter', 'allChats'),
  hideRoomsInSpaces<bool>('chat.vibe.hideRoomsInSpaces', false),
  showThumbnailsInTimeline<bool>('chat.vibe.showThumbnailsInTimeline', true),
  vibeHaptics<bool>('chat.vibe.haptics', true),
  // Notifications show only the app name and "New message" (no names, text or pictures)
  vibeHideNotificationContent<bool>('chat.vibe.notification_privacy', false),
  // Glass look: palette ('wallbash' = from the wallpaper), the processed
  // (blurred) wallpaper file and the colour picked from it
  vibeGlassPalette<String>('chat.vibe.glass_palette', 'wallbash'),
  vibeGlassWallpaper<String>('chat.vibe.glass_wallpaper', ''),
  vibeGlassSeed<int>('chat.vibe.glass_seed', 0xFF7AA2F7),
  // Glass look: take the palette from Hypr Launcher when it's installed
  vibeGlassFollowLauncher<bool>('chat.vibe.glass_follow_launcher', true),
  vibeSaveMedia<bool>('chat.vibe.save_media', false),
  vibeStatusBubble<bool>('chat.vibe.status_bubble', true),
  vibeLowData<bool>('chat.vibe.low_data', false),
  vibeLinkPreviews<bool>('chat.vibe.link_previews', true),
  // in encrypted chats the server would see the link: off unless chosen
  vibeLinkPreviewsEncrypted<bool>('chat.vibe.link_previews_encrypted', false),
  // status shows the song playing in any music app (Android)
  vibeNowPlaying<bool>('chat.vibe.now_playing', false),
  vibeNowPlayingPrev<String>('chat.vibe.now_playing_prev', ''),
  // strict encryption: new chats start with it, intro shown once
  vibeStrictNew<bool>('chat.vibe.strict_new', true),
  vibeStrictIntro<bool>('chat.vibe.strict_intro', false),
  // 'direct' (own connection, like Vibgram - default), 'standard' (Firebase
  // via the Worker) or 'builtin' (ntfy, no Google)
  vibePushMode<String>('chat.vibe.push_mode', 'direct'),
  vibeDirectBatteryAsked<bool>('chat.vibe.direct_battery_asked', false),
  // last time Vibe asked to be let run in the background (ms since epoch)
  vibeBatteryAskedAt<int>('chat.vibe.battery_asked_at', 0),
  // Privacy: hide online / last seen; who sees my status and local time
  // ('everyone', 'picked' or 'nobody'); picked = comma-separated user ids.
  vibeHidePresence<bool>('chat.vibe.hide_presence', false),
  vibeStatusAudience<String>('chat.vibe.status_audience', 'everyone'),
  vibeStatusAllowed<String>('chat.vibe.status_allowed', ''),
  vibeMyStatus<String>('chat.vibe.my_status', ''),
  // Chat backups: auto backup 'off', 'daily' or 'weekly'.
  vibeAutoBackup<String>('chat.vibe.auto_backup', 'off'),
  vibeLastAutoBackup<int>('chat.vibe.last_auto_backup', 0),
  vibeAutoBackupResult<String>('chat.vibe.auto_backup_result', ''),
  // Sticker packs hidden from the sticker tray (names, one per line)
  vibeHiddenStickerPacks<String>('chat.vibe.hidden_sticker_packs', ''),
  // Element Call server for calls ('' = the default, call.element.io)
  vibeCallServer<String>('chat.vibe.call_server', ''),
  // Where automatic backups go when picked (Google Drive file), '' = this phone
  vibeBackupCloudUri<String>('chat.vibe.backup_cloud_uri', ''),
  vibeNtfyTopic<String>('chat.vibe.ntfy_topic', ''),
  vibeNtfyLastId<String>('chat.vibe.ntfy_last_id', ''),
  // Days to keep downloaded media on this phone. 0 = forever.
  vibeKeepMediaDays<int>('chat.vibe.keep_media_days', 0),
  // Media cache limit in MB on this phone. 0 = no limit.
  vibeCacheLimitMb<int>('chat.vibe.cache_limit_mb', 0),
  // Decoded pictures kept in memory while Vibe runs (MB).
  vibeMemoryCacheMb<int>('chat.vibe.memory_cache_mb', 256),
  // Group tag shown next to my name in groups (room id, '' = none)
  vibeGroupTag<String>('chat.vibe.group_tag', ''),
  // Web: sign out when the browser closes (shared computers)
  vibeWebSessionOnly<bool>('chat.vibe.web_session_only', false),
  doubleTapToReact<bool>('chat.vibe.double_tap_to_react', false),
  doubleTapReaction<String>('chat.vibe.double_tap_reaction', '❤️'),
  benchmarksInLogs<bool>('chat.vibe.benchmarks_in_logs', false);

  final String key;
  final T defaultValue;

  const AppSettings(this.key, this.defaultValue);

  static SharedPreferences get store => _store!;
  static SharedPreferences? _store;

  static Future<void> reset({bool loadWebConfigFile = true}) async {
    await AppSettings._store!.clear();
    await init(loadWebConfigFile: loadWebConfigFile);
  }

  static Future<SharedPreferences> init({bool loadWebConfigFile = true}) async {
    if (AppSettings._store != null) return AppSettings.store;

    final store = AppSettings._store = await SharedPreferences.getInstance();

    // Settings used to be saved as 'chat.fluffy.*': carry them over once.
    for (final setting in AppSettings.values) {
      if (!setting.key.startsWith('chat.vibe.')) continue;
      final oldKey = 'chat.fluffy.${setting.key.substring(10)}';
      final oldValue = store.get(oldKey);
      if (oldValue == null) continue;
      if (store.get(setting.key) == null) {
        if (oldValue is bool) await store.setBool(setting.key, oldValue);
        if (oldValue is int) await store.setInt(setting.key, oldValue);
        if (oldValue is double) await store.setDouble(setting.key, oldValue);
        if (oldValue is String) await store.setString(setting.key, oldValue);
        if (oldValue is List<String>) {
          await store.setStringList(setting.key, oldValue);
        }
      }
      await store.remove(oldKey);
    }

    // Migrate wrong datatype for fontSizeFactor
    final fontSizeFactorString = Result(
      () => store.getString(AppSettings.fontSizeFactor.key),
    ).asValue?.value;
    if (fontSizeFactorString != null) {
      Logs().i('Migrate wrong datatype for fontSizeFactor!');
      await store.remove(AppSettings.fontSizeFactor.key);
      final fontSizeFactor = double.tryParse(fontSizeFactorString);
      if (fontSizeFactor != null) {
        await store.setDouble(AppSettings.fontSizeFactor.key, fontSizeFactor);
      }
    }

    if (store.getBool(AppSettings.sendOnEnter.key) == null) {
      await store.setBool(AppSettings.sendOnEnter.key, !PlatformInfos.isMobile);
    }
    if (store.getBool(AppSettings.doubleTapToReact.key) == null) {
      await store.setBool(
        AppSettings.doubleTapToReact.key,
        PlatformInfos.isMobile,
      );
    }
    if (kIsWeb && loadWebConfigFile) {
      try {
        final configJsonString = utf8.decode(
          (await http.get(Uri.parse('config.json'))).bodyBytes,
        );
        final configJson =
            json.decode(configJsonString) as Map<String, Object?>;
        for (final setting in AppSettings.values) {
          if (store.get(setting.key) != null) continue;
          final configValue = configJson[setting.name];
          if (configValue == null) continue;
          if (configValue is bool) {
            await store.setBool(setting.key, configValue);
          }
          if (configValue is String) {
            await store.setString(setting.key, configValue);
          }
          if (configValue is int) {
            await store.setInt(setting.key, configValue);
          }
          if (configValue is double) {
            await store.setDouble(setting.key, configValue);
          }
        }
      } on FormatException catch (_) {
        Logs().v('[ConfigLoader] config.json not found');
      } catch (e) {
        Logs().v('[ConfigLoader] config.json not found', e);
      }
    }

    return store;
  }
}

extension AppSettingsBoolExtension on AppSettings<bool> {
  bool get value {
    final value = Result(() => AppSettings.store.getBool(key));
    final error = value.asError;
    if (error != null) {
      Logs().e(
        'Unable to fetch $key from storage. Removing entry...',
        error.error,
        error.stackTrace,
      );
    }
    return value.asValue?.value ?? defaultValue;
  }

  Future<void> setItem(bool value) => AppSettings.store.setBool(key, value);
}

extension AppSettingsStringExtension on AppSettings<String> {
  String get value {
    final value = Result(() => AppSettings.store.getString(key));
    final error = value.asError;
    if (error != null) {
      Logs().e(
        'Unable to fetch $key from storage. Removing entry...',
        error.error,
        error.stackTrace,
      );
    }
    return value.asValue?.value ?? defaultValue;
  }

  Future<void> setItem(String value) => AppSettings.store.setString(key, value);
}

extension AppSettingsIntExtension on AppSettings<int> {
  int get value {
    final value = Result(() => AppSettings.store.getInt(key));
    final error = value.asError;
    if (error != null) {
      Logs().e(
        'Unable to fetch $key from storage. Removing entry...',
        error.error,
        error.stackTrace,
      );
    }
    return value.asValue?.value ?? defaultValue;
  }

  Future<void> setItem(int value) => AppSettings.store.setInt(key, value);
}

extension AppSettingsDoubleExtension on AppSettings<double> {
  double get value {
    final value = Result(() => AppSettings.store.getDouble(key));
    final error = value.asError;
    if (error != null) {
      Logs().e(
        'Unable to fetch $key from storage. Removing entry...',
        error.error,
        error.stackTrace,
      );
    }
    return value.asValue?.value ?? defaultValue;
  }

  Future<void> setItem(double value) => AppSettings.store.setDouble(key, value);
}
