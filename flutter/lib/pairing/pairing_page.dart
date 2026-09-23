import 'dart:ui' show Color;

import '../theme/tokens.dart';

/// The phone page the pairing server serves — "Pair from my phone" — on
/// the Nocturne system, in the TV's own theme, laid out like the phone
/// chat page (`relay/chat.html`): the mark and a Watch Together kicker, a
/// title, then the form. The TV renders this page itself, so the palette
/// comes straight from [nocturnePalette] rather than a copy that can drift.
///
/// Every value put into the page is escaped; the error text is always one
/// of the server's own fixed strings.
String pairingFormPage({
  required ThemeId theme,
  required String action,
  required String nickname,
  required String url,
  required bool editing,
  String? error,
}) {
  final errorHtml = error == null
      ? ''
      : '<p class="error" role="alert">${_escape(error)}</p>';
  return _page(
    theme: theme,
    title: editing ? 'Update this relay' : 'Add a relay',
    body:
        '''
    <p class="lede">Name it and paste its address — both appear on your TV.</p>
    $errorHtml
    <form method="POST" action="${_escape(action)}">
      <label class="field">
        <span>Nickname</span>
        <input type="text" name="nickname" placeholder="Sam's relay" value="${_escape(nickname)}" maxlength="40" autocomplete="off" autocapitalize="words" enterkeyhint="next"${nickname.isEmpty ? ' autofocus' : ''}>
      </label>
      <label class="field">
        <span>Relay address</span>
        <input type="text" name="url" placeholder="wss://your-relay?token=…" value="${_escape(url)}" autocomplete="off" autocapitalize="off" autocorrect="off" spellcheck="false" inputmode="url" enterkeyhint="send">
      </label>
      <button type="submit">
        <svg width="20" height="20" viewBox="0 0 256 256" fill="none" stroke="currentColor" stroke-width="18" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="40" y="48" width="176" height="120" rx="12"/><line x1="96" y1="208" x2="160" y2="208"/><line x1="128" y1="168" x2="128" y2="208"/></svg>
        Send to TV
      </button>
    </form>''',
  );
}

String pairingSentPage({required ThemeId theme}) => _page(
  theme: theme,
  title: 'Sent to your TV',
  body: '''
    <div class="status" role="status"><span class="dot"></span>Sent</div>
    <p class="lede">The relay is filled in on the TV. You can close this page.</p>''',
);

String _page({
  required ThemeId theme,
  required String title,
  required String body,
}) {
  final p = nocturnePalette(theme);
  return '''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover, interactive-widget=resizes-content">
<meta name="theme-color" content="${_hex(p.background)}">
<title>Reelay — ${_escape(title)}</title>
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500&display=swap">
<style>
  :root {
    --bg:${_hex(p.background)}; --surface:${_hex(p.surface)}; --raised:${_hex(p.surfaceRaised)};
    --line:${_hex(p.line)}; --line-strong:${_hex(p.lineStrong)};
    --ink:${_hex(p.ink)}; --ink3:${_hex(p.ink3)}; --ink4:${_hex(p.ink4)};
    --accent:${_hex(p.accent)}; --a300:${_hex(p.accent300)}; --a700:${_hex(p.accent700)}; --a900:${_hex(p.accent900)};
    --ok:#6FB98A; --bad:#E07A6F; color-scheme:dark;
  }
  * { box-sizing:border-box; }
  html, body { min-height:100%; }
  body {
    margin:0; min-height:100vh; min-height:100dvh;
    padding:calc(14px + env(safe-area-inset-top)) 18px calc(24px + env(safe-area-inset-bottom));
    background:radial-gradient(120% 50% at 0% 0%, var(--surface) 0%, var(--bg) 60%);
    background-color:var(--bg); color:var(--ink);
    font:400 15px/1.45 Inter, system-ui, -apple-system, sans-serif;
    -webkit-font-smoothing:antialiased; -webkit-tap-highlight-color:transparent;
  }
  ::selection { background:var(--a700); color:var(--ink); }
  :focus-visible { outline:2px solid var(--accent); outline-offset:2px; }
  main { max-width:440px; margin:0 auto; display:flex; flex-direction:column; gap:18px; }
  header { position:relative; display:flex; align-items:center; gap:12px; padding-bottom:14px; }
  header::after {
    content:""; position:absolute; left:-18px; right:-18px; bottom:0; height:1px;
    background:linear-gradient(90deg, transparent, var(--line) 48px, var(--line) calc(100% - 48px), transparent);
  }
  .titles { display:flex; flex-direction:column; gap:2px; min-width:0; }
  .kicker { display:flex; align-items:center; gap:8px; font-size:11px; font-weight:500; letter-spacing:.1em; color:var(--a300); }
  .kicker::before { content:""; width:12px; height:2px; background:var(--accent); }
  h1 { margin:0; font-size:17px; font-weight:500; letter-spacing:-.01em; }
  .lede { margin:0; color:var(--ink3); font-size:14px; }
  form { display:flex; flex-direction:column; gap:14px; }
  .field { display:flex; flex-direction:column; gap:6px; }
  .field span { font-size:12px; font-weight:500; color:var(--ink3); }
  input {
    width:100%; height:48px; padding:0 14px; border-radius:8px; border:1px solid var(--line-strong);
    background:var(--surface); color:var(--ink); font:400 16px Inter, system-ui, sans-serif;
  }
  input::placeholder { color:var(--ink4); }
  input:focus { outline:none; border-color:var(--accent); background:var(--raised); }
  button {
    margin-top:4px; height:48px; border-radius:8px; border:1.5px solid var(--accent); background:transparent;
    color:var(--a300); font:500 15px Inter, system-ui, sans-serif; cursor:pointer;
    display:flex; align-items:center; justify-content:center; gap:10px; transition:background .12s;
  }
  button:hover { background:var(--a900); }
  button:active { background:var(--a700); color:var(--ink); }
  .error { margin:0; color:var(--bad); font-size:13px; }
  .status { display:flex; align-items:center; gap:7px; font-size:13px; color:var(--ink3); }
  .dot { width:7px; height:7px; border-radius:50%; background:var(--ok); flex:none; }
</style>
</head>
<body>
<main>
  <header>
    <svg width="26" height="26" viewBox="0 0 46 46" aria-hidden="true"><rect x="5" y="9" width="36" height="12" rx="4" fill="var(--accent)"/><rect x="5" y="25" width="22" height="12" rx="4" fill="var(--ink)"/></svg>
    <div class="titles">
      <div class="kicker">WATCH TOGETHER</div>
      <h1>${_escape(title)}</h1>
    </div>
  </header>
$body
</main>
</body>
</html>
''';
}

String _hex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

String _escape(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('"', '&quot;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');
