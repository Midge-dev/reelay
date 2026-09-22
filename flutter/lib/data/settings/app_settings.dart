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
  final bool showChatOverlay;
  final ChatOverlayCorner chatOverlayCorner;
  final String? selectedServerId;
  final List<Profile> profiles;
  final ThemeId themeId;

  const AppSettings({
    this.relays = const [],
    this.maxHostSeats = defaultMaxHostSeats,
    this.maxVideoBitrateKbps = defaultMaxBitrateKbps,
    this.forceBurnSubtitles = false,
    this.showChatOverlay = true,
    this.chatOverlayCorner = ChatOverlayCorner.bottomEnd,
    this.selectedServerId,
    this.profiles = const [],
    this.themeId = ThemeId.nocturne,
  });

  AppSettings copyWith({
    List<RelayEntry>? relays,
    int? maxHostSeats,
    int? maxVideoBitrateKbps,
    bool? forceBurnSubtitles,
    bool? showChatOverlay,
    ChatOverlayCorner? chatOverlayCorner,
    String? selectedServerId,
    List<Profile>? profiles,
    ThemeId? themeId,
  }) {
    return AppSettings(
      relays: relays ?? this.relays,
      maxHostSeats: maxHostSeats ?? this.maxHostSeats,
      maxVideoBitrateKbps: maxVideoBitrateKbps ?? this.maxVideoBitrateKbps,
      forceBurnSubtitles: forceBurnSubtitles ?? this.forceBurnSubtitles,
      showChatOverlay: showChatOverlay ?? this.showChatOverlay,
      chatOverlayCorner: chatOverlayCorner ?? this.chatOverlayCorner,
      selectedServerId: selectedServerId ?? this.selectedServerId,
      profiles: profiles ?? this.profiles,
      themeId: themeId ?? this.themeId,
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
