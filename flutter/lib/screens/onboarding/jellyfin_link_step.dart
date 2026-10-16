import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../app_version.dart';
import '../../data/jellyfin/jellyfin_auth_api.dart';
import '../../focus/back_handler.dart';
import '../../kit/button.dart';
import '../../kit/icon.dart';
import '../../kit/text.dart';
import '../../pairing/jellyfin_pairing.dart';
import '../../state/data_providers.dart';
import '../../theme/phosphor_icons.dart';
import '../../theme/scale.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../common/click_to_type_text_field.dart';
import 'jellyfin_link_session.dart';
import 'onboarding_frame.dart';

/// Screens O3 and O3b — Link Jellyfin. O3 leads with the phone: its QR
/// opens a page this TV serves (see jellyfin_pairing.dart) where the
/// server's address goes first, then Quick Connect or a password. O3b is
/// the same step typed on the TV. One [JellyfinLinkSession] sits under
/// both, so switching between them never cancels anything and whichever
/// way finishes first links the account.
class JellyfinLinkStep extends ConsumerStatefulWidget {
  final void Function(JellyfinServerInfo server, JellyfinSession session)
  onLinked;

  /// Back to O1.
  final VoidCallback onBack;

  /// Go on without Jellyfin — null when it's the only server chosen, as
  /// there'd be nothing to go on to.
  final VoidCallback? onSkip;

  /// "STEP 2 OF 4 · JELLYFIN".
  final String kicker;

  /// The left rail's summaries — "Plex, Jellyfin", "2 of 2".
  final Map<SetupStep, String> summaries;

  /// False when linking from Settings, outside setup — no step column.
  final bool showSteps;

  const JellyfinLinkStep({
    super.key,
    required this.onLinked,
    required this.onBack,
    this.onSkip,
    required this.kicker,
    this.summaries = const {},
    this.showSteps = true,
  });

  @override
  ConsumerState<JellyfinLinkStep> createState() => _JellyfinLinkStepState();
}

class _JellyfinLinkStepState extends ConsumerState<JellyfinLinkStep> {
  final _typeFocus = FocusNode(debugLabel: 'setup-jellyfin-type');
  final _addressFocus = FocusNode(debugLabel: 'setup-jellyfin-address');
  final _usernameFocus = FocusNode(debugLabel: 'setup-jellyfin-username');

  JellyfinLinkSession? _session;
  JellyfinPairingServer? _pairing;
  String? _pairingUrl;
  bool _noNetwork = false;

  /// O3b: typing on the TV.
  bool _typing = false;
  String _address = '';
  String _username = '';
  String _password = '';

  @override
  void initState() {
    super.initState();
    _start();
    _focusAfterFrame(_typeFocus);
  }

  Future<void> _start() async {
    final String deviceId;
    try {
      deviceId = await ref
          .read(plexIdentityProvider)
          .getOrCreateClientIdentifier();
    } catch (_) {
      // No device id means no session at all; typing is no better off, so
      // say what's left — Back or Skip.
      if (mounted) setState(() => _noNetwork = true);
      return;
    }
    if (!mounted) return;
    final session = JellyfinLinkSession(
      JellyfinAuthApi(
        deviceId: deviceId,
        deviceName: jellyfinDeviceName,
        appVersion: appVersionName,
      ),
      onLinked: (server, session) {
        if (mounted) widget.onLinked(server, session);
      },
    )..addListener(_onSessionChanged);
    setState(() => _session = session);
    final pairing = JellyfinPairingServer(session);
    String? url;
    try {
      url = await pairing.start();
    } catch (_) {
      url = null;
    }
    if (!mounted) {
      await pairing.stop();
      return;
    }
    setState(() {
      _pairing = pairing;
      _pairingUrl = url;
      _noNetwork = url == null;
    });
  }

  void _onSessionChanged() {
    if (!mounted) return;
    final server = _session?.server;
    // An address that arrived from the phone shows in the typed field too.
    if (server != null && _address.isEmpty) _address = server.baseUrl;
    setState(() {});
  }

  @override
  void dispose() {
    _pairing?.stop();
    _session
      ?..removeListener(_onSessionChanged)
      ..dispose();
    _typeFocus.dispose();
    _addressFocus.dispose();
    _usernameFocus.dispose();
    super.dispose();
  }

  void _focusAfterFrame(FocusNode node) =>
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) node.requestFocus();
      });

  void _showTyping(bool typing) {
    setState(() => _typing = typing);
    _focusAfterFrame(typing ? _addressFocus : _typeFocus);
  }

  /// O3b's one action: test the address first, then sign in.
  Future<void> _continueTyped() async {
    final session = _session;
    if (session == null || session.busy) return;
    final server = session.server;
    final addressChanged =
        server == null ||
        (_address.trim() != server.baseUrl && _address.trim().isNotEmpty);
    if (addressChanged) {
      if (_address.trim().isEmpty) return;
      final failure = await session.useAddress(_address);
      if (failure == null && mounted) _focusAfterFrame(_usernameFocus);
      return;
    }
    if (_username.trim().isEmpty) {
      _usernameFocus.requestFocus();
      return;
    }
    await session.signIn(_username.trim(), _password);
  }

  @override
  Widget build(BuildContext context) {
    return BackHandler(
      onBack: _typing ? () => _showTyping(false) : widget.onBack,
      child: OnboardingFrame(
        step: SetupStep.link,
        contentTop: 80,
        summaries: widget.summaries,
        showSteps: widget.showSteps,
        footnote: 'Reelay never keeps your password. Jellyfin hands back a token for this TV only, and it stays on the device.',
        footer: _footer(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StepHeading(
              kicker: widget.kicker,
              title: _typing
                  ? 'Type it in with the remote'
                  : 'Fill this in from your phone',
            ),
            SizedBox(height: 32.du(context)),
            if (_typing) _typed(context) else _fromPhone(context),
          ],
        ),
      ),
    );
  }

  // ---- O3 ----

  Widget _fromPhone(BuildContext context) {
    final url = _pairingUrl;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 260.du(context),
              height: 260.du(context),
              padding: EdgeInsets.all(AppSpacing.lg.du(context)),
              decoration: BoxDecoration(
                color: AppColors.inkOnArt,
                borderRadius: BorderRadius.circular(
                  AppShape.radiusLg.du(context),
                ),
              ),
              child: url == null
                  ? null
                  : QrImageView(data: url, backgroundColor: AppColors.inkOnArt),
            ),
            SizedBox(height: 18.du(context)),
            if (url != null) ...[
              AppText('Or visit', style: AppTypography.caption),
              SizedBox(height: AppSpacing.xs.du(context)),
              AppText(
                url.replaceFirst('http://', ''),
                style: AppTypography.label,
                color: AppColors.ink,
              ),
            ],
          ],
        ),
        SizedBox(width: 56.du(context)),
        Flexible(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 700.du(context)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText(
                  _noNetwork
                      ? 'This TV has no Wi-Fi address for a phone to reach. Type it on the TV instead.'
                      : 'Your phone needs to be on the same Wi-Fi as the TV. What you send there appears here.',
                  style: AppTypography.body,
                ),
                SizedBox(height: 26.du(context)),
                _progressPanel(context),
                SizedBox(height: AppSpacing.lg.du(context)),
                _status(context),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _progressPanel(BuildContext context) {
    final session = _session;
    final server = session?.server;
    final quickConnect = session?.quickConnect;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: 28.du(context),
        vertical: AppSpacing.md.du(context),
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.line, width: 1.du(context)),
        borderRadius: BorderRadius.circular(AppShape.radiusMd.du(context)),
      ),
      child: Column(
        children: [
          _PanelRow(
            label: 'Server',
            value: server == null ? null : '${server.name} · ${server.baseUrl}',
            waiting: 'Waiting…',
          ),
          _divider(context),
          _PanelRow(
            label: 'Quick Connect',
            value: quickConnect?.code,
            large: true,
            waiting: server == null ? 'After the server' : 'Getting a code…',
          ),
          _divider(context),
          _PanelRow(
            label: 'Username',
            value: session?.username,
            waiting: 'Waiting…',
            live: server != null,
          ),
        ],
      ),
    );
  }

  Widget _divider(BuildContext context) =>
      Container(height: 1.du(context), color: AppColors.line);

  /// One line under the panel: what to do next, or what went wrong.
  Widget _status(BuildContext context) {
    final session = _session;
    final failure = session?.failure;
    final String text;
    if (failure != null) {
      text = jellyfinFailureMessage(failure);
    } else if (session?.quickConnect != null) {
      text = 'Tap Approve on your phone, or enter the code under Quick Connect in any signed-in Jellyfin app.';
    } else if (session?.server != null) {
      text = 'Sign in on your phone to finish.';
    } else {
      text = 'Sent straight to your server over your own network.';
    }
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: 640.du(context)),
      child: AppText(
        text,
        style: AppTypography.caption.copyWith(height: 1.5),
        color: failure != null ? AppColors.warning : null,
      ),
    );
  }

  // ---- O3b ----

  Widget _typed(BuildContext context) {
    final session = _session;
    final server = session?.server;
    final failure = session?.failure;
    final shortcuts = [
      'http://',
      'https://',
      '.local',
      ':$jellyfinDefaultPort',
    ];
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: 900.du(context)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Field(
            label: 'SERVER ADDRESS',
            value: _address,
            hint: 'loft:8096',
            focusNode: _addressFocus,
            onChanged: (v) => setState(() => _address = v),
            trailing: server == null ? null : '✓ ${server.name}',
          ),
          SizedBox(height: AppSpacing.md.du(context)),
          Wrap(
            spacing: AppSpacing.md.du(context),
            runSpacing: AppSpacing.md.du(context),
            children: [
              for (final s in shortcuts)
                AppOutlinedButton(
                  dense: true,
                  onClick: () => setState(
                    () => _address = s.startsWith('http')
                        ? '$s${_address.replaceFirst(RegExp(r'^https?://'), '')}'
                        : '$_address$s',
                  ),
                  child: AppText(s, style: AppTypography.label, color: null),
                ),
            ],
          ),
          SizedBox(height: AppSpacing.xl.du(context)),
          _Field(
            label: 'USERNAME',
            value: _username,
            hint: server == null ? 'After the address checks out' : 'Not set',
            focusNode: _usernameFocus,
            enabled: server != null,
            onChanged: (v) => setState(() => _username = v),
          ),
          SizedBox(height: AppSpacing.md.du(context)),
          _Field(
            label: 'PASSWORD',
            value: _password,
            hint: server == null ? 'After the address checks out' : 'Not set',
            enabled: server != null,
            obscure: true,
            onChanged: (v) => setState(() => _password = v),
          ),
          SizedBox(height: AppSpacing.lg.du(context)),
          AppText(
            failure != null ? jellyfinFailureMessage(failure) : 'Reelay tests the address before asking for your account, so a typo is caught here rather than after all three.',
            style: AppTypography.caption.copyWith(height: 1.5),
            color: failure != null ? AppColors.warning : null,
          ),
        ],
      ),
    );
  }

  Widget _footer(BuildContext context) {
    final session = _session;
    final busy = session?.busy ?? false;
    final serverKnown =
        session?.server != null && _address.trim() == session!.server!.baseUrl;
    // Wraps rather than overflows: the two O3 buttons are wide, and at
    // large UI sizes they don't fit side by side.
    return Wrap(
      spacing: AppSpacing.lg.du(context),
      runSpacing: AppSpacing.md.du(context),
      children: [
        if (_typing) ...[
          AppOutlinedButton(
            onClick: _continueTyped,
            enabled: !busy,
            child: AppText(
              busy
                  ? 'Checking…'
                  : (serverKnown ? 'Sign in' : 'Test and continue'),
              style: AppTypography.label,
              color: null,
            ),
          ),
          AppOutlinedButton(
            onClick: () => _showTyping(false),
            child: AppText(
              'Use my phone',
              style: AppTypography.label,
              color: null,
            ),
          ),
        ] else ...[
          AppOutlinedButton(
            onClick: () => _showTyping(true),
            focusNode: _typeFocus,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AppIcon(PhosphorIconsRegular.keyboard, size: 22),
                SizedBox(width: AppSpacing.md.du(context)),
                AppText(
                  'Type it on the TV instead',
                  style: AppTypography.label,
                  color: null,
                ),
              ],
            ),
          ),
          if (widget.onSkip case final skip?)
            AppOutlinedButton(
              onClick: skip,
              child: AppText(
                'Skip Jellyfin',
                style: AppTypography.label,
                color: null,
              ),
            )
          else
            AppOutlinedButton(
              onClick: widget.onBack,
              child: AppText('Back', style: AppTypography.label, color: null),
            ),
        ],
      ],
    );
  }
}

/// A label and its value in O3's progress panel; "Waiting…" with an amber
/// dot until the value arrives.
class _PanelRow extends StatelessWidget {
  final String label;
  final String? value;
  final String waiting;
  final bool large;

  /// Whether this row is the one being waited on — only then does it carry
  /// the dot.
  final bool live;

  const _PanelRow({
    required this.label,
    required this.value,
    required this.waiting,
    this.large = false,
    this.live = true,
  });

  @override
  Widget build(BuildContext context) {
    final value = this.value;
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: 64.du(context)),
      child: Row(
        children: [
          SizedBox(
            width: 180.du(context),
            child: AppText(label, style: AppTypography.caption),
          ),
          Expanded(
            child: value == null
                ? AppText(
                    waiting,
                    style: AppTypography.body,
                    color: AppColors.ink3,
                  )
                : AppText(
                    large ? value.split('').join(' ') : value,
                    style: large ? AppTypography.title1 : AppTypography.body,
                    color: AppColors.ink,
                  ),
          ),
          if (value == null && live)
            Container(
              width: 9.du(context),
              height: 9.du(context),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.warning,
              ),
            ),
        ],
      ),
    );
  }
}

/// One of O3b's three fields: an uppercase label over the value, typed with
/// the TV's own keyboard.
class _Field extends StatefulWidget {
  final String label;
  final String value;
  final String hint;
  final FocusNode? focusNode;
  final ValueChanged<String> onChanged;
  final bool enabled;
  final bool obscure;
  final String? trailing;

  const _Field({
    required this.label,
    required this.value,
    required this.hint,
    this.focusNode,
    required this.onChanged,
    this.enabled = true,
    this.obscure = false,
    this.trailing,
  });

  @override
  State<_Field> createState() => _FieldState();
}

class _FieldState extends State<_Field> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final field = Container(
      padding: EdgeInsets.symmetric(
        horizontal: 22.du(context),
        vertical: AppSpacing.md.du(context),
      ),
      decoration: BoxDecoration(
        color: _focused ? AppColors.surfaceRaised : AppColors.surface,
        border: Border.all(
          color: _focused ? AppColors.accent : AppColors.line,
          width: AppShape.borderWidth.du(context),
        ),
        borderRadius: BorderRadius.circular(AppShape.radiusMd.du(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: AppText(widget.label, style: AppTypography.micro),
              ),
              if (widget.trailing case final trailing?)
                AppText(
                  trailing,
                  style: AppTypography.caption,
                  color: AppColors.success,
                ),
            ],
          ),
          SizedBox(height: AppSpacing.xs.du(context)),
          ClickToTypeTextField(
            value: widget.value,
            onValueChange: widget.onChanged,
            focusNode: widget.focusNode,
            hintText: widget.hint,
            showBorder: false,
            obscureText: widget.obscure,
            onFocusChange: (f) => setState(() => _focused = f),
            textStyle: AppTypography.body.copyWith(color: AppColors.ink),
          ),
        ],
      ),
    );
    // Disabled: 45% and out of the focus order (DESIGN.md).
    if (!widget.enabled) {
      return Opacity(opacity: 0.45, child: ExcludeFocus(child: field));
    }
    return field;
  }
}
