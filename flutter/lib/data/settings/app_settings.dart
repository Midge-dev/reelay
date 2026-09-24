import '../../theme/tokens.dart';

enum ChatOverlayCorner { topStart, topEnd, bottomStart, bottomEnd }

class RelayEntry {
  final String id;
  final String nickname;
  final String url;
  final bool isDefault;

  const RelayEntry({
    required this.id,
    required this.nickname,
    required this.url,
    this.isDefault = false,
  });

  RelayEntry copyWith({bool? isDefault}) => RelayEntry(
    id: id,
    nickname: nickname,
    url: url,
    isDefault: isDefault ?? this.isDefault,
  );

  factory RelayEntry.fromJson(Map<String, dynamic> json) => RelayEntry(
    id: json['id'] as String,
    nickname: json['nickname'] as String,
    url: json['url'] as String,
    isDefault: json['isDefault'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'nickname': nickname,
    'url': url,
    'isDefault': isDefault,
  };
}

/// A device-local identity, distinct from the Plex account it's bound to —
/// see DESIGN.md's "Profiles are Reelay's own" note. Holds at most one Plex
/// account (Jellyfin is a real, disabled slot elsewhere in the UI, not
/// modeled here yet — see server_switcher_panel.dart's matching note).
class Profile {
  final String id;
  final String name;
  final String watchTogetherName;
  final String plexUsername;
  final String? thumb;

  const Profile({
    required this.id,
    required this.name,
    required this.watchTogetherName,
    required this.plexUsername,
    this.thumb,
  });

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
    id: json['id'] as String,
    name: json['name'] as String,
    watchTogetherName: json['watchTogetherName'] as String,
    plexUsername: json['plexUsername'] as String,
    thumb: json['thumb'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'watchTogetherName': watchTogetherName,
    'plexUsername': plexUsername,
    'thumb': thumb,
  };
}

class BitratePreset {
  final int kbps;
  final String label;

  const BitratePreset(this.kbps, this.label);
}

class AppSettings {
  static const defaultMaxBitrateKbps = 8000;
  static const defaultMaxHostSeats = 8;

  // Screen 22's "UI Size" stepper — a manual multiplier on top of
  // AppScale's screenHeight/1080 factor (see theme/scale.dart). No API
  // tells a set-top box its panel's real physical size, so a 4K TV
  // reporting the same 1920x1080 logical surface as a 32" one renders
  // identically at factor 1.0 even though it reads much smaller from a
  // couch — this is the manual compensation for that, not a replacement
  // for it. Range kept at 100-150% (never below the base design size) with
  // 130% the default, per user preference after trying the full range.
  static const defaultUiScale = 1.3;
  static const minUiScale = 1.0;
  static const maxUiScale = 1.5;
  static const uiScaleStep = 0.05;

  static const bitratePresets = [
    BitratePreset(2000, '2 Mbps (Low)'),
    BitratePreset(4000, '4 Mbps (Medium)'),
    BitratePreset(8000, '8 Mbps (Good)'),
    BitratePreset(20000, '20 Mbps (High)'),
  ];

  static const maxHostSeatsOptions = [2, 4, 6, 8, 12, 14, 16, 18, 20, 22, 24];

  final List<RelayEntry> relays;
  final int maxHostSeats;
  final int maxVideoBitrateKbps;
  final bool forceBurnSubtitles;

  /// Switch the TV's refresh rate to the film's (24p for most films) for
  /// the length of playback, so motion doesn't judder. Off by default, as
  /// in Plex's own app: the switch blanks the screen for a second or two.
  final bool matchFrameRate;
  final bool showChatOverlay;
  final ChatOverlayCorner chatOverlayCorner;
  // Multi-server hub: every reachable, owned/shared server the account can
  // see connects at once by default — this is the opt-out list, keyed by
  // PlexServer.machineIdentifier, not an opt-in single selection. Replaces
  // the old single nullable `selectedServerId`.
  final Set<String> disabledServerIds;
  final List<Profile> profiles;
  final ThemeId themeId;
  final double uiScale;

  /// First-run setup (screens O1-O5) has been finished — including the
  /// optional Watch Together step, whether a relay was added or "Not now"
  /// was chosen. Without it, a skipped relay step would be offered again on
  /// every launch; the design says skipping means no more prompts.
  final bool setupComplete;

  const AppSettings({
    this.relays = const [],
    this.maxHostSeats = defaultMaxHostSeats,
    this.maxVideoBitrateKbps = defaultMaxBitrateKbps,
    this.forceBurnSubtitles = false,
    this.matchFrameRate = false,
    this.showChatOverlay = true,
    this.chatOverlayCorner = ChatOverlayCorner.bottomEnd,
    this.disabledServerIds = const {},
    this.profiles = const [],
    this.themeId = ThemeId.nocturne,
    this.uiScale = defaultUiScale,
    this.setupComplete = false,
  });

  AppSettings copyWith({
    List<RelayEntry>? relays,
    int? maxHostSeats,
    int? maxVideoBitrateKbps,
    bool? forceBurnSubtitles,
    bool? matchFrameRate,
    bool? showChatOverlay,
    ChatOverlayCorner? chatOverlayCorner,
    Set<String>? disabledServerIds,
    List<Profile>? profiles,
    ThemeId? themeId,
    double? uiScale,
    bool? setupComplete,
  }) {
    return AppSettings(
      relays: relays ?? this.relays,
      maxHostSeats: maxHostSeats ?? this.maxHostSeats,
      maxVideoBitrateKbps: maxVideoBitrateKbps ?? this.maxVideoBitrateKbps,
      forceBurnSubtitles: forceBurnSubtitles ?? this.forceBurnSubtitles,
      matchFrameRate: matchFrameRate ?? this.matchFrameRate,
      showChatOverlay: showChatOverlay ?? this.showChatOverlay,
      chatOverlayCorner: chatOverlayCorner ?? this.chatOverlayCorner,
      disabledServerIds: disabledServerIds ?? this.disabledServerIds,
      profiles: profiles ?? this.profiles,
      themeId: themeId ?? this.themeId,
      uiScale: uiScale ?? this.uiScale,
      setupComplete: setupComplete ?? this.setupComplete,
    );
  }

  RelayEntry? get defaultRelay {
    if (relays.isEmpty) return null;
    for (final relay in relays) {
      if (relay.isDefault) return relay;
    }
    return relays.first;
  }
}
