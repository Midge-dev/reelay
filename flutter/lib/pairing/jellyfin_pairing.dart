import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import '../data/jellyfin/jellyfin_auth_api.dart';
import '../screens/onboarding/jellyfin_link_session.dart';
import '../theme/tokens.dart';
import 'pairing_page.dart';
import 'pairing_server.dart';

const _kicker = 'JELLYFIN';

/// O3's phone side: the page the QR opens. The phone gives the server's
/// address first; once the TV has found it, the page offers Quick Connect
/// (one tap on a phone already signed in to Jellyfin) or a username and
/// password. Everything feeds the TV's [session], so whatever finishes
/// first — here, on the TV, or Quick Connect — links the account.
class JellyfinPairingServer {
  final JellyfinLinkSession session;

  /// How long the account page waits for the Quick Connect code to arrive
  /// after the address checks out — long enough for a LAN round trip.
  final Duration quickConnectWait;

  JellyfinPairingServer(
    this.session, {
    this.quickConnectWait = const Duration(seconds: 3),
  });

  final String _token = randomPairingToken();
  HttpServer? _server;

  @visibleForTesting
  String get token => _token;

  /// Starts serving and returns the page's URL, or null when this TV has
  /// no network address to serve it on.
  Future<String?> start() async {
    final ip = await localIpv4Address();
    if (ip == null) return null;
    final server = await shelf_io.serve(handle, InternetAddress.anyIPv4, 0);
    _server = server;
    return 'http://$ip:${server.port}/$_token';
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  /// The request handler, public for tests.
  Future<Response> handle(Request request) async {
    final path = request.url.path;
    final theme = AppColors.currentTheme;

    if (request.method == 'GET' && path == _token) {
      if (session.linked) {
        return pairingHtmlResponse(
          jellyfinLinkedPage(theme: theme, session: session),
        );
      }
      final changing = request.url.queryParameters.containsKey('change');
      final server = session.server;
      return pairingHtmlResponse(
        server == null || changing
            ? jellyfinAddressPage(theme: theme, action: '/$_token/server')
            : jellyfinAccountPage(
                theme: theme,
                token: _token,
                server: server,
                quickConnect: session.quickConnect,
              ),
      );
    }

    if (request.method == 'POST' && path == '$_token/server') {
      final address =
          parseFormFields(await request.readAsString())['address'] ?? '';
      if (address.isEmpty) {
        return pairingHtmlResponse(
          jellyfinAddressPage(
            theme: theme,
            action: '/$_token/server',
            error: 'Type the server’s address first.',
          ),
        );
      }
      final failure = await session.useAddress(address);
      final server = session.server;
      if (failure != null || server == null) {
        return pairingHtmlResponse(
          jellyfinAddressPage(
            theme: theme,
            action: '/$_token/server',
            address: address,
            error: jellyfinFailureMessage(
              failure ?? JellyfinAuthFailure.unreachable,
            ),
          ),
        );
      }
      await _waitForQuickConnect();
      return pairingHtmlResponse(
        jellyfinAccountPage(
          theme: theme,
          token: _token,
          server: server,
          quickConnect: session.quickConnect,
        ),
      );
    }

    if (request.method == 'POST' && path == '$_token/signin') {
      final fields = parseFormFields(await request.readAsString());
      final username = fields['username'] ?? '';
      final server = session.server;
      if (server == null) {
        return pairingHtmlResponse(
          jellyfinAddressPage(theme: theme, action: '/$_token/server'),
        );
      }
      if (session.linked) {
        return pairingHtmlResponse(
          jellyfinLinkedPage(theme: theme, session: session),
        );
      }
      if (username.isEmpty) {
        return pairingHtmlResponse(
          jellyfinAccountPage(
            theme: theme,
            token: _token,
            server: server,
            quickConnect: session.quickConnect,
            error: 'Type your username first.',
          ),
        );
      }
      final failure = await session.signIn(username, fields['password'] ?? '');
      if (failure != null) {
        return pairingHtmlResponse(
          jellyfinAccountPage(
            theme: theme,
            token: _token,
            server: server,
            quickConnect: session.quickConnect,
            username: username,
            error: jellyfinFailureMessage(failure),
          ),
        );
      }
      return pairingHtmlResponse(
        jellyfinLinkedPage(theme: theme, session: session),
      );
    }

    return Response.notFound('Not found');
  }

  Future<void> _waitForQuickConnect() async {
    final deadline = DateTime.now().add(quickConnectWait);
    while (session.quickConnect == null &&
        !session.linked &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }
}

String jellyfinAddressPage({
  required ThemeId theme,
  required String action,
  String address = '',
  String? error,
}) => pairingPageShell(
  theme: theme,
  kicker: _kicker,
  title: 'Link your Jellyfin server',
  body:
      '''
    <p class="lede">The address you open Jellyfin at in a browser — like 192.168.1.10:8096.</p>
    ${_error(error)}
    <form method="POST" action="${escapeHtml(action)}">
      <label class="field">
        <span>Server address</span>
        <input type="text" name="address" placeholder="192.168.1.10:8096" value="${escapeHtml(address)}" autocomplete="off" autocapitalize="off" autocorrect="off" spellcheck="false" inputmode="url" enterkeyhint="go" autofocus>
      </label>
      <button type="submit">Find server</button>
    </form>''',
);

String jellyfinAccountPage({
  required ThemeId theme,
  required String token,
  required JellyfinServerInfo server,
  JellyfinQuickConnect? quickConnect,
  String username = '',
  String? error,
}) {
  // Jellyfin's own approve page, with the code already filled in — one tap
  // for a phone already signed in to that server.
  final approve = quickConnect == null
      ? ''
      : '''
    <p class="lede">Already signed in to Jellyfin on this phone? Approve this TV there.</p>
    <a class="button" href="${escapeHtml('${server.baseUrl}/web/#/quickconnect?code=${quickConnect.code}')}">Approve with Quick Connect</a>
    <p class="lede">Or enter code <span class="code">${escapeHtml(quickConnect.code)}</span> under Quick Connect in any signed-in Jellyfin app.</p>
    <div class="or">or sign in</div>''';
  return pairingPageShell(
    theme: theme,
    kicker: _kicker,
    title: 'Sign in to ${server.name}',
    body:
        '''
    <div class="status" role="status"><span class="dot"></span>Found ${escapeHtml(server.name)} · ${escapeHtml(server.baseUrl)}</div>
    $approve
    ${_error(error)}
    <form method="POST" action="/${escapeHtml(token)}/signin">
      <label class="field">
        <span>Username</span>
        <input type="text" name="username" value="${escapeHtml(username)}" autocomplete="username" autocapitalize="off" autocorrect="off" spellcheck="false" enterkeyhint="next">
      </label>
      <label class="field">
        <span>Password</span>
        <input type="password" name="password" autocomplete="current-password" enterkeyhint="go">
      </label>
      <button type="submit">Sign in</button>
    </form>
    <p class="lede">Sent straight to your server over your own network. Reelay keeps the token it returns, not the password.</p>
    <a class="quiet" href="/${escapeHtml(token)}?change">Use a different server</a>''',
  );
}

String jellyfinLinkedPage({
  required ThemeId theme,
  required JellyfinLinkSession session,
}) => pairingPageShell(
  theme: theme,
  kicker: _kicker,
  title: 'Linked',
  body:
      '''
    <div class="status" role="status"><span class="dot"></span>${escapeHtml(session.server?.name ?? 'Jellyfin')} is linked on your TV</div>
    <p class="lede">You can close this page.</p>''',
);

String _error(String? error) => error == null
    ? ''
    : '<p class="error" role="alert">${escapeHtml(error)}</p>';
