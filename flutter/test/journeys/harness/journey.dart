import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/data/plex/secure_token_store.dart';
import 'package:reelay/data/settings/app_settings.dart';
import 'package:reelay/data/settings/settings_store.dart';
import 'package:reelay/main.dart';
import 'package:reelay/state/data_providers.dart';
import 'package:reelay/sync/relay_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import '../../playback/fake_video_player_platform.dart';
import 'fake_http.dart';
import 'fake_jellyfin.dart';
import 'fake_plex.dart';
import 'fake_relay.dart';

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
  @override
  Future<void> saveHomeServerTokens(String profileId, String json) async => values['home:$profileId'] = json;
  @override
  Future<String?> loadHomeServerTokens(String profileId) async => values['home:$profileId'];
  @override
  Future<void> clearHomeServerTokens(String profileId) async => values.remove('home:$profileId');
}

/// The real app, as someone on the sofa uses it: [ReelayApp] with a
/// Jellyfin-only profile signed in to [server], driven by remote keys.
/// Nothing is faked above the network and the two stores — every screen,
/// controller and focus rule is the app's own.
class Journey {
  Journey._(this.tester, this.server, this.network, this._relay, this._plex);

  final WidgetTester tester;
  final FakeJellyfin server;
  final FakePlex? _plex;

  /// The Plex account and server, for journeys started with one.
  FakePlex get plex => _plex ?? (throw StateError('this journey has no Plex server: pass plex: to journey()'));
  final FakeRelay? _relay;

  final _friends = <Friend>[];

  /// Someone else on their own TV, on this journey's relay. Left for you at
  /// the end of the journey.
  Friend friend({String name = 'Riley'}) {
    final f = Friend(relay, name: name, peerId: '${name.toLowerCase()}-peer');
    _friends.add(f);
    return f;
  }

  /// The Watch Together relay, for journeys started with one.
  FakeRelay get relay => _relay ?? (throw StateError('this journey has no relay: pass relay: to journey()'));
  final FakeNetwork network;

  /// Steps taken so far, for a failure to show how it got there.
  final steps = <String>[];

  static bool _realFontsLoaded = false;

  /// The app's own type (Inter) and icons (Phosphor) in place of the test
  /// font's boxes — for screenshots a person can read. Off by default: the
  /// test font's wide square glyphs make the crawler's overflow check
  /// stricter than real text.
  static Future<void> _loadRealFonts(WidgetTester tester) async {
    if (_realFontsLoaded) return;
    _realFontsLoaded = true;
    await tester.runAsync(() async {
      Future<void> load(String family, String asset) async {
        await (FontLoader(family)..addFont(rootBundle.load(asset))).load();
      }

      await load('Inter', 'assets/fonts/Inter-Variable.ttf');
      await load('packages/phosphor_flutter/PhosphorRegular', 'packages/phosphor_flutter/lib/fonts/Phosphor.ttf');
      await load('packages/phosphor_flutter/PhosphorFill', 'packages/phosphor_flutter/lib/fonts/Phosphor-Fill.ttf');
    });
  }

  static Future<Journey> _boot(WidgetTester tester, FakeJellyfin server, FakeNetwork network, {FakePlex? plex, bool withJellyfin = true, double uiScale = AppSettings.defaultUiScale, FakeRelay? relay, bool realFonts = false, AppSettings Function(AppSettings)? settings}) async {
    if (realFonts) await _loadRealFonts(tester);
    VideoPlayerPlatform.instance = FakeVideoPlayerPlatform();
    // The Shield's real geometry: a 960×540 logical canvas (1080p at 2×).
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    final store = SettingsStore(SharedPreferencesAsync());
    final profile = Profile(
      id: 'p1',
      name: 'Sam',
      watchTogetherName: 'Sam',
      plexUsername: plex == null ? null : FakePlex.username,
      jellyfin: withJellyfin
          ? const JellyfinLink(serverId: 'jf-den', serverName: 'Den', baseUrl: 'http://den.local:8096', userId: FakeJellyfin.userId, username: 'sam')
          : null,
    );
    if (relay != null) {
      RelayClient.openChannel = relay.open;
      addTearDown(() => RelayClient.openChannel = defaultOpenChannel);
    }
    final initial = AppSettings(
      profiles: [profile],
      setupComplete: true,
      uiScale: uiScale,
      relays: [if (relay != null) RelayEntry(id: 'r1', nickname: 'Test relay', url: relay.url, isDefault: true)],
    );
    await store.save(settings?.call(initial) ?? initial);
    final tokens = _MemoryTokenStore();
    if (withJellyfin) tokens.values['jellyfin:p1'] = 'jf-token';
    if (plex != null) tokens.values['plex:p1'] = FakePlex.accountToken;

    final journey = Journey._(tester, server, network, relay, plex).._tokens = tokens;
    await journey._launch();
    return journey;
  }

  late _MemoryTokenStore _tokens;

  /// What the app has saved in its secure store, by key: `plex:<profile id>`,
  /// `jellyfin:<profile id>`, and `plex` for the install's own.
  Map<String, String> get savedTokens => Map.unmodifiable(_tokens.values);

  Future<void> _launch({Duration settle = const Duration(seconds: 5)}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [secureTokenStoreProvider.overrideWithValue(_tokens)],
        child: const ReelayApp(),
      ),
    );
    // Start-up needs a moment of real time once (an asset load resolves on
    // the real clock, not the test's), then the splash and first rows run
    // on the test's clock.
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await wait(const Duration(milliseconds: 500));
    }
    await wait(settle); // every Home row in
  }

  /// Quits the app and opens it again, as turning the TV off and on does:
  /// the settings and secure stores keep what the app saved, nothing else.
  /// [settle] is how long to give it after the splash; zero looks at the
  /// first thing it shows.
  Future<void> relaunch({Duration settle = const Duration(seconds: 5)}) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30)); // leftover timers run out
    steps.add('— relaunch —');
    await _launch(settle: settle);
  }

  /// Lets time pass in small steps (animations, timers, fake requests).
  /// Never pumpAndSettle: loading indicators animate forever.
  Future<void> wait([Duration total = const Duration(milliseconds: 400)]) async {
    const step = Duration(milliseconds: 50);
    for (var t = Duration.zero; t < total; t += step) {
      await tester.pump(step);
    }
  }

  /// The video player underneath the app (fake): what it opened, and
  /// whether it was last told to play or to pause.
  FakeVideoPlayerPlatform get video => VideoPlayerPlatform.instance as FakeVideoPlayerPlatform;
  bool get videoPlaying => video.calls.lastWhere((c) => c == 'play' || c == 'pause', orElse: () => 'pause') == 'play';

  /// Saves what's on screen as a PNG under build/journey_shots/ (or
  /// \$JOURNEY_SHOTS), for looking at a screen rather than reading its
  /// text. Fonts are the test's — the app's own type is loaded by the
  /// harness only where the test environment allows it.
  Future<String> screenshot(String name) async {
    final dir = Directory(Platform.environment['JOURNEY_SHOTS'] ?? 'build/journey_shots')..createSync(recursive: true);
    final path = '${dir.path}/$name.png';
    final layer = tester.binding.renderViews.first.debugLayer! as OffsetLayer;
    final size = tester.view.physicalSize;
    await tester.runAsync(() async {
      final image = await layer.toImage(Offset.zero & size);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File(path).writeAsBytesSync(bytes!.buffer.asUint8List());
    });
    return path;
  }

  /// Lets a moment of real time pass — for work that resolves on the real
  /// clock rather than the test's (the settings store's reads).
  Future<void> realTime([int hops = 3]) async {
    for (var i = 0; i < hops; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await wait(const Duration(milliseconds: 200));
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

  /// Types [text] into the field being edited, as the TV's keyboard does
  /// (through the text input channel), then finishes it with the keyboard's
  /// Done — a field opened for typing with Select first.
  Future<void> type(String text) async {
    tester.testTextInput.enterText(text);
    await wait(const Duration(milliseconds: 200));
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await wait(const Duration(milliseconds: 300));
    steps.add('Type "$text" → ${describeFocus()}');
  }

  /// Holds Select down for [held] — the long press that removes a title
  /// from Continue Watching. [halfway] runs once, midway through, still
  /// held — to look at the screen while the hold is under way.
  Future<void> holdSelect({Duration held = const Duration(milliseconds: 900), void Function()? halfway}) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    var t = Duration.zero;
    const repeatEvery = Duration(milliseconds: 50);
    await wait(const Duration(milliseconds: 400)); // the platform's repeat delay
    t += const Duration(milliseconds: 400);
    var lookedHalfway = halfway == null;
    while (t < held) {
      if (!lookedHalfway && t >= held ~/ 2) {
        lookedHalfway = true;
        halfway!();
      }
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

  /// Every piece of text on screen, top to bottom — for exploring a screen
  /// and for failure messages.
  List<String> screenTexts() {
    final root = tester.binding.rootElement;
    return root == null ? const [] : _textsUnder(root);
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

final defaultOpenChannel = RelayClient.openChannel;

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
/// network in place for everything the test (and the app) does. With
/// [plex], the profile is also signed in to that Plex account (only to it,
/// with [jellyfin] false).
void journey(
  String description,
  Future<void> Function(Journey j) body, {
  FakeJellyfin Function()? server,
  FakePlex Function()? plex,
  bool jellyfin = true,
  double uiScale = AppSettings.defaultUiScale,
  bool relay = false,
  bool realFonts = false,
  bool skip = false,
  AppSettings Function(AppSettings)? settings,
}) {
  testWidgets(skip: skip, description, (tester) async {
    final fakeJellyfin = server?.call() ?? FakeJellyfin();
    final fakeRelay = relay ? FakeRelay() : null;
    final fakePlex = plex?.call();
    final network = FakeNetwork([fakeJellyfin.route, ?fakePlex?.route, ?fakeRelay?.route]);
    await HttpOverrides.runWithHttpOverrides(() async {
      final j = await Journey._boot(tester, fakeJellyfin, network, plex: fakePlex, withJellyfin: jellyfin, uiScale: uiScale, relay: fakeRelay, realFonts: realFonts, settings: settings);
      try {
        await body(j);
      } finally {
        for (final f in j._friends) {
          f.leave();
        }
      }
      // Unmount and let leftover timers (auto-hide, polls) run out.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 30));
    }, network);
  });
}
