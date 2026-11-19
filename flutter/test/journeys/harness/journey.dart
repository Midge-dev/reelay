import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/data/plex/secure_token_store.dart';
import 'package:reelay/data/settings/app_settings.dart';
import 'package:reelay/data/settings/settings_store.dart';
import 'package:reelay/main.dart';
import 'package:reelay/state/data_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import '../../playback/fake_video_player_platform.dart';
import 'fake_http.dart';
import 'fake_jellyfin.dart';

class _MemoryTokenStore implements SecureTokenStore {
  final values = <String, String>{};
  @override
  Future<void> saveToken(String token) async => values['plex'] = token;
  @override
  Future<String?> loadToken() async => values['plex'];
  @override
  Future<void> clearToken() async => values.remove('plex');
  @override
  Future<void> saveTokenForProfile(String profileId, String token) async => values['plex:$profileId'] = token;
  @override
  Future<String?> loadTokenForProfile(String profileId) async => values['plex:$profileId'];
  @override
  Future<void> clearTokenForProfile(String profileId) async => values.remove('plex:$profileId');
  @override
  Future<void> saveJellyfinToken(String profileId, String token) async => values['jellyfin:$profileId'] = token;
  @override
  Future<String?> loadJellyfinToken(String profileId) async => values['jellyfin:$profileId'];
  @override
  Future<void> clearJellyfinToken(String profileId) async => values.remove('jellyfin:$profileId');
}

/// The real app, as someone on the sofa uses it: [ReelayApp] with a
/// Jellyfin-only profile signed in to [server], driven by remote keys.
/// Nothing is faked above the network and the two stores — every screen,
/// controller and focus rule is the app's own.
class Journey {
  Journey._(this.tester, this.server, this.network);

  final WidgetTester tester;
  final FakeJellyfin server;
  final FakeNetwork network;

  /// Steps taken so far, for a failure to show how it got there.
  final steps = <String>[];

  static Future<Journey> _boot(WidgetTester tester, FakeJellyfin server, FakeNetwork network, {double uiScale = AppSettings.defaultUiScale}) async {
    VideoPlayerPlatform.instance = FakeVideoPlayerPlatform();
    // The Shield's real geometry: a 960×540 logical canvas (1080p at 2×).
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    final store = SettingsStore(SharedPreferencesAsync());
    const profile = Profile(
      id: 'p1',
      name: 'Sam',
      watchTogetherName: 'Sam',
      jellyfin: JellyfinLink(serverId: 'jf-den', serverName: 'Den', baseUrl: 'http://den.local:8096', userId: FakeJellyfin.userId, username: 'sam'),
    );
    await store.save(AppSettings(profiles: const [profile], setupComplete: true, uiScale: uiScale));
    final tokens = _MemoryTokenStore()..values['jellyfin:p1'] = 'jf-token';

    await tester.pumpWidget(
      ProviderScope(
        overrides: [secureTokenStoreProvider.overrideWithValue(tokens)],
        child: const ReelayApp(),
      ),
    );
    final journey = Journey._(tester, server, network);
    // Start-up needs a moment of real time once (an asset load resolves on
    // the real clock, not the test's), then the splash and first rows run
    // on the test's clock.
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await journey.wait(const Duration(milliseconds: 500));
    }
    await journey.wait(const Duration(seconds: 5)); // every Home row in
    return journey;
  }

  /// Lets time pass in small steps (animations, timers, fake requests).
  /// Never pumpAndSettle: loading indicators animate forever.
  Future<void> wait([Duration total = const Duration(milliseconds: 400)]) async {
    const step = Duration(milliseconds: 50);
    for (var t = Duration.zero; t < total; t += step) {
      await tester.pump(step);
    }
  }

  /// One press of a remote button, as the Shield sends it.
  Future<void> press(LogicalKeyboardKey key, {int times = 1}) async {
    for (var i = 0; i < times; i++) {
      await tester.sendKeyEvent(key);
      await wait(const Duration(milliseconds: 300));
      steps.add('${_name(key)} → ${describeFocus()}');
      _checkFocusVisible();
    }
  }

  /// Checked after every press: on a TV, focus you can't see is a remote
  /// that does nothing. Turn off around a moment that legitimately has no
  /// focus target (the player with its controls hidden is still fine: its
  /// screen-wide node is focused and on screen).
  bool checkFocusAfterEveryPress = true;

  void _checkFocusVisible() {
    if (!checkFocusAfterEveryPress) return;
    expect(focus != null && focusOnScreen, isTrue, reason: _why('after that press nothing visible had focus'));
  }

  /// Holds Select down for [held] — the long press that removes a title
  /// from Continue Watching.
  Future<void> holdSelect({Duration held = const Duration(milliseconds: 900)}) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    var t = Duration.zero;
    const repeatEvery = Duration(milliseconds: 50);
    await wait(const Duration(milliseconds: 400)); // the platform's repeat delay
    t += const Duration(milliseconds: 400);
    while (t < held) {
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
      await tester.pump(repeatEvery);
      t += repeatEvery;
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await wait(const Duration(milliseconds: 400));
    steps.add('Hold Select ${held.inMilliseconds}ms → ${describeFocus()}');
    _checkFocusVisible();
  }

  Future<void> up([int times = 1]) => press(LogicalKeyboardKey.arrowUp, times: times);
  Future<void> down([int times = 1]) => press(LogicalKeyboardKey.arrowDown, times: times);
  Future<void> left([int times = 1]) => press(LogicalKeyboardKey.arrowLeft, times: times);
  Future<void> right([int times = 1]) => press(LogicalKeyboardKey.arrowRight, times: times);
  Future<void> select() => press(LogicalKeyboardKey.select);

  /// The remote's Back button (Android's system back).
  Future<void> back() async {
    await tester.binding.handlePopRoute();
    await wait(const Duration(seconds: 1));
    steps.add('Back → ${describeFocus()}');
    _checkFocusVisible();
  }

  static String _name(LogicalKeyboardKey key) => switch (key) {
    LogicalKeyboardKey.arrowUp => 'Up',
    LogicalKeyboardKey.arrowDown => 'Down',
    LogicalKeyboardKey.arrowLeft => 'Left',
    LogicalKeyboardKey.arrowRight => 'Right',
    LogicalKeyboardKey.select => 'Select',
    _ => key.keyLabel,
  };

  FocusNode? get focus => FocusManager.instance.primaryFocus;

  static List<String> _textsUnder(Element root) {
    final texts = <String>[];
    void visit(Element e) {
      final w = e.widget;
      if (w is RichText) texts.add(w.text.toPlainText());
      e.visitChildren(visit);
    }

    root.visitChildren(visit);
    return texts.where((t) => t.trim().isNotEmpty).toList();
  }

  /// The text that names what's focused: its own, or — for a poster, whose
  /// title sits under its artwork, outside the focused box — the nearest
  /// enclosing widget's, while that's still just a few words.
  List<String> focusedTexts() {
    final context = focus?.context;
    if (context == null) return const [];
    final own = _textsUnder(context as Element);
    if (own.isNotEmpty) return own;
    var found = const <String>[];
    var levels = 0;
    context.visitAncestorElements((ancestor) {
      final texts = _textsUnder(ancestor);
      if (texts.isNotEmpty) {
        if (texts.length <= 4) found = texts;
        return false;
      }
      return ++levels < 12;
    });
    return found;
  }

  /// The name an icon-only button gives itself (a Semantics label around it).
  String? _focusedSemanticsLabel() {
    String? label;
    focus?.context?.visitAncestorElements((a) {
      final w = a.widget;
      if (w is Semantics && w.properties.label != null) {
        label = w.properties.label;
        return false;
      }
      return true;
    });
    return label;
  }

  /// The focused widget's on-screen box, or null if it has none.
  Rect? focusedRect() {
    final node = focus;
    if (node == null || node.context == null) return null;
    final box = node.context!.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// How a person would name what's focused: its text, else its label.
  String describeFocus() {
    final node = focus;
    if (node == null) return 'NOTHING';
    final texts = focusedTexts();
    final label = texts.isNotEmpty ? texts.take(3).join(' / ') : (node.debugLabel ?? node.context?.widget.runtimeType.toString() ?? '?');
    final rect = focusedRect();
    final where = rect == null ? 'no box' : '${rect.left.round()},${rect.top.round()} ${rect.width.round()}×${rect.height.round()}';
    return '"$label" [$where]';
  }

  /// Whether the focused widget sits inside something faded right out —
  /// focused, but nobody can see it.
  bool get focusFadedOut {
    final context = focus?.context;
    if (context == null) return false;
    var faded = false;
    context.visitAncestorElements((a) {
      final w = a.widget;
      if ((w is Opacity && w.opacity == 0) || (w is AnimatedOpacity && w.opacity == 0)) {
        faded = true;
        return false;
      }
      if (w is FadeTransition && w.opacity.value == 0) {
        faded = true;
        return false;
      }
      return true;
    });
    return faded;
  }

  /// Whether the focused widget is on screen — at least half of it, and
  /// not faded out.
  bool get focusOnScreen {
    if (focusFadedOut) return false;
    final rect = focusedRect();
    if (rect == null || rect.isEmpty) return false;
    final screen = Offset.zero & tester.view.physicalSize;
    final visible = rect.intersect(screen);
    return !visible.isEmpty && visible.width * visible.height >= rect.width * rect.height / 2;
  }

  /// Whether [text] is anywhere on screen right now — as text, or as an
  /// icon button's name.
  bool shows(String text) =>
      find.text(text).evaluate().isNotEmpty ||
      find.textContaining(text).evaluate().isNotEmpty ||
      find.bySemanticsLabel(text).evaluate().isNotEmpty;

  /// Fails, with the steps so far, unless focus is on something showing
  /// [text] and is on screen.
  void expectFocusOn(String text, {String? because}) {
    final texts = focusedTexts();
    final onIt = texts.any((t) => t.contains(text)) || _focusedSemanticsLabel() == text;
    expect(onIt && focusOnScreen, isTrue, reason: _why('focus should be on "$text"${because == null ? '' : ' — $because'}'));
  }

  String _why(String what) => [
    what,
    'focus is ${describeFocus()}${focusFadedOut ? ' (FADED OUT)' : focusOnScreen ? '' : ' (OFF SCREEN)'}',
    'steps:',
    for (final s in steps) '  $s',
    if (network.unrouted.isNotEmpty) 'requests nothing served: ${network.unrouted.map((r) => '$r').toSet().join(', ')}',
  ].join('\n');

  String why(String what) => _why(what);
}

extension RailNavigation on Journey {
  bool get _onRail => (focusedRect()?.left ?? 9999) < 60;

  /// Goes to [item] on the rail (Home, Search, Watchlist, Movies, …) and
  /// opens it.
  Future<void> openFromRail(String item) async {
    for (var i = 0; i < 6 && !_onRail; i++) {
      await left();
    }
    expect(_onRail, isTrue, reason: why('should have reached the rail'));
    for (var i = 0; i < 10 && !focusedTexts().any((t) => t.contains('Home')); i++) {
      await up();
    }
    for (var i = 0; i < 10 && !focusedTexts().any((t) => t.contains(item)); i++) {
      await down();
    }
    expectFocusOn(item);
    await select();
    await wait(const Duration(seconds: 1));
  }
}

/// What a crawl found.
class CrawlReport {
  /// Every distinct place focus went, by description.
  final visited = <String>{};

  /// Places where no direction moved focus anywhere.
  final traps = <String>{};
}

extension FocusCrawl on Journey {
  /// [presses] seeded-random D-pad moves (no Select or Back, so it stays on
  /// this screen and its rail), checking after each that focus is visible
  /// — and, at the end, that nowhere it went was a dead end. [pauseEvery]
  /// in a while waits long enough for things that hide themselves (the
  /// player's controls) to do so.
  Future<CrawlReport> crawl({int presses = 150, int seed = 1, int pauseEvery = 0}) async {
    final rng = _Rng(seed);
    final report = CrawlReport();
    final moves = <String, Map<LogicalKeyboardKey, String>>{};
    const keys = [LogicalKeyboardKey.arrowUp, LogicalKeyboardKey.arrowDown, LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.arrowRight];
    for (var i = 0; i < presses; i++) {
      final from = _placeKey();
      final key = keys[rng.next(4)];
      await press(key);
      final to = _placeKey();
      report.visited.add(to);
      (moves[from] ??= {})[key] = to;
      if (pauseEvery > 0 && i % pauseEvery == pauseEvery - 1) {
        await wait(const Duration(seconds: 5));
        _checkFocusVisible();
      }
    }
    for (final MapEntry(key: place, value: outcomes) in moves.entries) {
      if (outcomes.length == 4 && outcomes.values.every((to) => to == place)) report.traps.add(place);
    }
    return report;
  }

  String _placeKey() {
    final rect = focusedRect();
    return '${describeFocus().split(' [').first} @${rect?.left.round()},${rect?.top.round()}';
  }
}

/// A tiny deterministic generator, so a crawl replays exactly.
class _Rng {
  _Rng(this._state);
  int _state;
  int next(int max) {
    _state = (_state * 1103515245 + 12345) & 0x7fffffff;
    return _state % max;
  }
}

/// A test that runs the whole app against [FakeJellyfin], with the fake
/// network in place for everything the test (and the app) does.
void journey(String description, Future<void> Function(Journey j) body, {FakeJellyfin Function()? server, double uiScale = AppSettings.defaultUiScale}) {
  testWidgets(description, (tester) async {
    final jellyfin = server?.call() ?? FakeJellyfin();
    final network = FakeNetwork([jellyfin.route]);
    await HttpOverrides.runWithHttpOverrides(() async {
      final j = await Journey._boot(tester, jellyfin, network, uiScale: uiScale);
      await body(j);
      // Unmount and let leftover timers (auto-hide, polls) run out.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 30));
    }, network);
  });
}
