import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/jellyfin/jellyfin_auth_api.dart';

/// One attempt at linking a Jellyfin account, shared by every way in: the
/// phone form (O3), typing on the TV (O3b) and Quick Connect. Whichever
/// finishes first wins — moving between O3 and O3b never cancels the
/// others (design: "the QR stays live the whole time").
///
/// Once a server is known, a Quick Connect code is kept live for it: an
/// expired code is replaced on its own, as the Plex code is on O2.
class JellyfinLinkSession extends ChangeNotifier {
  final JellyfinAuthApi _api;
  final Duration pollInterval;
  final void Function(JellyfinServerInfo server, JellyfinSession session)
  onLinked;

  JellyfinLinkSession(
    this._api, {
    required this.onLinked,
    this.pollInterval = const Duration(seconds: 3),
  });

  /// The server the account will be on, once an address has checked out.
  JellyfinServerInfo? get server => _server;
  JellyfinServerInfo? _server;

  /// The code to approve on a signed-in device; null until a server is
  /// known, or when the server has Quick Connect off.
  JellyfinQuickConnect? get quickConnect => _quickConnect;
  JellyfinQuickConnect? _quickConnect;

  /// The username last tried, shown on the TV as it arrives from the phone.
  String? get username => _username;
  String? _username;

  /// Why the last address or sign-in failed. Cleared by the next attempt.
  JellyfinAuthFailure? get failure => _failure;
  JellyfinAuthFailure? _failure;

  /// An address check or sign-in is in flight.
  bool get busy => _busy;
  bool _busy = false;

  bool get linked => _linked;
  bool _linked = false;

  // Bumped whenever the server changes or the session ends, so a stale
  // Quick Connect loop stops instead of linking the wrong server.
  int _generation = 0;
  bool _disposed = false;

  /// Checks [typed] and, when it's a Jellyfin server, makes it the one
  /// this session links to. Returns why it isn't, or null.
  Future<JellyfinAuthFailure?> useAddress(String typed) async {
    if (_linked) return null;
    _set(busy: true, failure: null);
    try {
      final info = await _api.probe(typed);
      if (_disposed || _linked) return null;
      final sameServer = info.id == _server?.id;
      _server = info;
      if (!sameServer) {
        _username = null;
        _quickConnect = null;
        unawaited(_keepQuickConnectLive(++_generation));
      }
      _set(busy: false);
      return null;
    } on JellyfinAuthException catch (e) {
      _set(busy: false, failure: e.failure);
      return e.failure;
    }
  }

  /// Signs in to the current server. Returns why it failed, or null once
  /// linked.
  Future<JellyfinAuthFailure?> signIn(String username, String password) async {
    final server = _server;
    if (server == null || _linked) return null;
    _username = username;
    _set(busy: true, failure: null);
    try {
      final session = await _api.signIn(
        server.baseUrl,
        username: username,
        password: password,
      );
      _finish(server, session);
      return null;
    } on JellyfinAuthException catch (e) {
      _set(busy: false, failure: e.failure);
      return e.failure;
    }
  }

  Future<void> _keepQuickConnectLive(int generation) async {
    final server = _server!;
    bool current() => !_disposed && !_linked && generation == _generation;
    if (!await _api.isQuickConnectEnabled(server.baseUrl) || !current()) return;
    while (current()) {
      final JellyfinQuickConnect request;
      try {
        request = await _api.startQuickConnect(server.baseUrl);
      } on JellyfinAuthException {
        return;
      }
      if (!current()) return;
      _quickConnect = request;
      notifyListeners();
      try {
        while (true) {
          await Future<void>.delayed(pollInterval);
          if (!current()) return;
          if (await _api.quickConnectApproved(server.baseUrl, request.secret)) {
            final session = await _api.finishQuickConnect(
              server.baseUrl,
              request.secret,
            );
            if (current()) _finish(server, session);
            return;
          }
        }
      } on JellyfinAuthException catch (e) {
        // An expired code is replaced; anything else ends Quick Connect
        // quietly — the password path is still there.
        if (e.failure != JellyfinAuthFailure.quickConnectExpired) {
          if (current()) {
            _quickConnect = null;
            notifyListeners();
          }
          return;
        }
      }
    }
  }

  void _finish(JellyfinServerInfo server, JellyfinSession session) {
    if (_linked || _disposed) return;
    _linked = true;
    _busy = false;
    _generation++;
    notifyListeners();
    onLinked(server, session);
  }

  void _set({bool? busy, Object? failure = _keep}) {
    if (_disposed) return;
    if (busy != null) _busy = busy;
    if (!identical(failure, _keep)) _failure = failure as JellyfinAuthFailure?;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}

const _keep = Object();

/// What went wrong, as a sentence for the TV and the phone — the cause and
/// the fix, never an exception string.
String jellyfinFailureMessage(JellyfinAuthFailure failure) => switch (failure) {
  JellyfinAuthFailure.unreachable => 'Nothing answered at that address. Check it, and that the server is on the same network as this TV.',
  JellyfinAuthFailure.notJellyfin => 'Something answered, but it isn’t a Jellyfin server. Check the address and port.',
  JellyfinAuthFailure.notSetUp => 'That Jellyfin server hasn’t finished its first-run setup. Finish it in a browser, then try again.',
  JellyfinAuthFailure.wrongCredentials =>
    'The server didn’t accept that username and password.',
  JellyfinAuthFailure.quickConnectDisabled =>
    'Quick Connect is switched off on this server.',
  JellyfinAuthFailure.quickConnectExpired =>
    'That code expired before it was approved.',
};
