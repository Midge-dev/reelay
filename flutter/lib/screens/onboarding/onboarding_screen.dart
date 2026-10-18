import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../data/jellyfin/jellyfin_auth_api.dart';
import '../../data/plex/plex_auth_api.dart';
import '../../data/settings/app_settings.dart';
import '../../focus/back_handler.dart';
import '../../kit/button.dart';
import '../../kit/focusable_surface.dart';
import '../../kit/icon.dart';
import '../../kit/surface_style.dart';
import '../../kit/text.dart';
import '../../state/data_providers.dart';
import '../../theme/phosphor_icons.dart';
import '../../theme/scale.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import 'jellyfin_link_step.dart';
import 'onboarding_frame.dart';
import 'watch_together_step.dart';

enum _Step { servers, link, jellyfin, watchTogether }

/// What first-run setup linked: a Plex token, a Jellyfin account, or both.
class SetupResult {
  final String? plexToken;
  final (JellyfinServerInfo, JellyfinSession)? jellyfin;

  const SetupResult({this.plexToken, this.jellyfin});
}

/// First-run setup, screens O1 → O2 (Plex) → O3 (Jellyfin) → O4, taking
/// O2 and O3 only for the servers chosen on O1. Linking stores what it
/// links but setup only hands it on once the Watch Together step has been
/// answered, so the relay question comes before the library loads, in the
/// design's order, and is never asked again. O5 is the connecting screen
/// that follows (see setup_ready_screen.dart).
///
/// [relinking]: Plex refused this TV's saved sign-in (it was removed from
/// the account's devices). Setup opens on the link step and says so, and
/// linking goes straight back in — everything else was already answered.
///
/// [addingTo]: Settings' Add more servers for this profile — O1 → O2/O3
/// without the step column or O4, opening with nothing chosen, and Back
/// from O1 is [onCancel]. Linking stores nothing itself; [onComplete] does.
class OnboardingScreen extends ConsumerStatefulWidget {
  final ValueChanged<SetupResult> onComplete;
  final bool relinking;
  final Profile? addingTo;
  final VoidCallback? onCancel;

  const OnboardingScreen({
    super.key,
    required this.onComplete,
    this.relinking = false,
    this.addingTo,
    this.onCancel,
  });

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  late _Step _step = widget.relinking ? _Step.link : _Step.servers;
  late final bool _adding = widget.addingTo != null;
  late bool _plexSelected = !_adding;
  bool _jellyfinSelected = false;
  String? _token;
  (JellyfinServerInfo, JellyfinSession)? _jellyfin;

  /// "Plex, Jellyfin" — what O1 settled on, for the rail.
  String get _serversSummary =>
      [if (_plexSelected) 'Plex', if (_jellyfinSelected) 'Jellyfin'].join(', ');

  /// How many accounts the link step covers, and which this is.
  String _linkSummary(_Step step) {
    final total = (_plexSelected ? 1 : 0) + (_jellyfinSelected ? 1 : 0);
    final index = step == _Step.jellyfin && _plexSelected ? 2 : 1;
    return '$index of $total';
  }

  void _toLinking() =>
      setState(() => _step = _plexSelected ? _Step.link : _Step.jellyfin);

  void _afterPlex() {
    if (_jellyfinSelected) {
      setState(() => _step = _Step.jellyfin);
    } else {
      _finishOrAsk();
    }
  }

  /// O4 next in setup; from Settings the relay was answered long ago.
  void _finishOrAsk() {
    if (_adding) {
      widget.onComplete(SetupResult(plexToken: _token, jellyfin: _jellyfin));
    } else {
      setState(() => _step = _Step.watchTogether);
    }
  }

  /// "STEP 2 OF 4 · PLEX", or "ADD SERVERS · PLEX" from Settings.
  String _linkKicker(String platform) =>
      _adding ? 'ADD SERVERS · $platform' : 'STEP 2 OF 4 · $platform';

  @override
  Widget build(BuildContext context) {
    return switch (_step) {
      _Step.servers => _ServersStep(
        addingTo: widget.addingTo,
        onCancel: widget.onCancel,
        plexSelected: _plexSelected,
        jellyfinSelected: _jellyfinSelected,
        onTogglePlex: () => setState(() => _plexSelected = !_plexSelected),
        onToggleJellyfin: () =>
            setState(() => _jellyfinSelected = !_jellyfinSelected),
        onContinue: _toLinking,
      ),
      _Step.link => BackHandler(
        onBack: () => setState(() => _step = _Step.servers),
        child: _LinkStep(
          relinking: widget.relinking,
          showSteps: !_adding,
          kicker: _linkKicker('PLEX'),
          summaries: {
            SetupStep.servers: _serversSummary,
            SetupStep.link: _linkSummary(_Step.link),
          },
          onBack: () => setState(() => _step = _Step.servers),
          onLinked: (token) async {
            if (!_adding) {
              await ref.read(secureTokenStoreProvider).saveToken(token);
            }
            if (!mounted) return;
            if (widget.relinking) {
              widget.onComplete(SetupResult(plexToken: token));
              return;
            }
            _token = token;
            _afterPlex();
          },
        ),
      ),
      _Step.jellyfin => JellyfinLinkStep(
        kicker: _linkKicker('JELLYFIN'),
        showSteps: !_adding,
        summaries: {
          SetupStep.servers: _serversSummary,
          SetupStep.link: _linkSummary(_Step.jellyfin),
        },
        onBack: () => setState(() => _step = _Step.servers),
        onSkip: _plexSelected ? _finishOrAsk : null,
        onLinked: (server, session) {
          _jellyfin = (server, session);
          _finishOrAsk();
        },
      ),
      _Step.watchTogether => BackHandler(
        onBack: () => setState(() => _step = _Step.servers),
        child: WatchTogetherStep(
          serversSummary: _serversSummary,
          onDone: () => widget.onComplete(
            SetupResult(plexToken: _token, jellyfin: _jellyfin),
          ),
        ),
      ),
    };
  }
}

// ---- O1 · Where's your library? -------------------------------------------

class _ServersStep extends StatefulWidget {
  /// Set when Settings opened this for a profile that already has accounts.
  final Profile? addingTo;
  final VoidCallback? onCancel;
  final bool plexSelected;
  final bool jellyfinSelected;
  final VoidCallback onTogglePlex;
  final VoidCallback onToggleJellyfin;
  final VoidCallback onContinue;

  const _ServersStep({
    this.addingTo,
    this.onCancel,
    required this.plexSelected,
    required this.jellyfinSelected,
    required this.onTogglePlex,
    required this.onToggleJellyfin,
    required this.onContinue,
  });

  @override
  State<_ServersStep> createState() => _ServersStepState();
}

class _ServersStepState extends State<_ServersStep> {
  final _plexFocus = FocusNode(debugLabel: 'setup-plex-card');
  final _continueFocus = FocusNode(debugLabel: 'setup-continue');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _plexFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _plexFocus.dispose();
    _continueFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final adding = widget.addingTo;
    final plexUser = adding?.plexUsername;
    final jellyfin = adding?.jellyfin;
    final frame = OnboardingFrame(
      step: SetupStep.servers,
      showSteps: adding == null,
      footnote: adding == null
          ? 'All of this can be changed later in Settings. Nothing here is permanent.'
          : 'A profile has one account of each kind, so choosing one it already has switches it.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          adding == null
              ? const StepHeading(
                  kicker: 'STEP 1 OF 4',
                  title: 'Where’s your library?',
                  body:
                      'Reelay talks to Plex and Jellyfin equally well, and to more than one of each. '
                      'Pick every kind you have — each gets its own sign-in next.',
                )
              : const StepHeading(
                  kicker: 'SETTINGS · ADD SERVERS',
                  title: 'What would you like to add?',
                  body:
                      'Pick one or both — each gets its own sign-in next. '
                      'Servers shared with a Plex account come with it.',
                ),
          SizedBox(height: 42.du(context)),
          // Side by side as in O1; at large UI sizes the cards narrow rather
          // than stacking, which pushed Jellyfin and Continue off-screen.
          // Down from either card is Continue — from Settings, Back sits
          // nearer the Jellyfin card and took the press.
          Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onKeyEvent: (_, event) {
              if (event is! KeyDownEvent ||
                  event.logicalKey != LogicalKeyboardKey.arrowDown ||
                  !(widget.plexSelected || widget.jellyfinSelected)) {
                return KeyEventResult.ignored;
              }
              _continueFocus.requestFocus();
              return KeyEventResult.handled;
            },
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Flexible(
                  child: _ChoiceCard(
                    focusNode: _plexFocus,
                    selected: widget.plexSelected,
                    icon: PhosphorIconsFill.hardDrives,
                    title: 'Plex',
                    body: plexUser != null
                        ? 'Signed in as $plexUser. Choose it to switch to another Plex account.'
                        : 'Sign in once on your phone. Shared servers come with you.',
                    onClick: widget.onTogglePlex,
                  ),
                ),
                SizedBox(width: AppSpacing.xl.du(context)),
                Flexible(
                  child: _ChoiceCard(
                    selected: widget.jellyfinSelected,
                    icon: widget.jellyfinSelected
                        ? PhosphorIconsFill.hardDrives
                        : PhosphorIconsRegular.hardDrives,
                    title: 'Jellyfin',
                    body: jellyfin != null
                        ? 'Signed in to ${jellyfin.serverName} as ${jellyfin.username}. Choose it to switch.'
                        : 'Your own server address and account, paired from your phone.',
                    onClick: widget.onToggleJellyfin,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      footer: Row(
        children: [
          AppOutlinedButton(
            onClick: widget.onContinue,
            focusNode: _continueFocus,
            enabled: widget.plexSelected || widget.jellyfinSelected,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppText('Continue', style: AppTypography.label, color: null),
                SizedBox(width: AppSpacing.md.du(context)),
                const AppIcon(PhosphorIconsRegular.arrowRight, size: 22),
              ],
            ),
          ),
          if (widget.onCancel case final cancel?) ...[
            SizedBox(width: AppSpacing.lg.du(context)),
            AppOutlinedButton(
              onClick: cancel,
              child: AppText('Back', style: AppTypography.label, color: null),
            ),
          ],
          if (!widget.plexSelected && !widget.jellyfinSelected) ...[
            SizedBox(width: 20.du(context)),
            AppText(
              'Select at least one to continue',
              style: AppTypography.caption,
            ),
          ],
        ],
      ),
    );
    return switch (widget.onCancel) {
      final cancel? => BackHandler(onBack: cancel, child: frame),
      null => frame,
    };
  }
}

SurfaceColors get _cardColors => SurfaceColors(
  container: AppColors.surface,
  content: AppColors.ink2,
  focusedContainer: AppColors.surfaceRaised,
  focusedContent: AppColors.ink,
  selectedContainer: AppColors.surface,
  selectedContent: AppColors.ink,
);
SurfaceBorder get _cardBorder => SurfaceBorder(
  idle: SurfaceBorderSide.solid(AppColors.line),
  focused: SurfaceBorderSide.solid(AppColors.accent),
);

/// A large choice card (O1's server types, O4's two ways in): icon, name,
/// one sentence, and a check when chosen.
class _ChoiceCard extends StatelessWidget {
  final FocusNode? focusNode;
  final bool selected;
  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onClick;

  const _ChoiceCard({
    this.focusNode,
    required this.selected,
    required this.icon,
    required this.title,
    required this.body,
    required this.onClick,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 400.du(context),
        minHeight: 230.du(context),
      ),
      child: FocusableSurface(
        onClick: onClick,
        selected: selected,
        focusNode: focusNode,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppShape.radiusMd.du(context)),
        ),
        colors: _cardColors,
        border: _cardBorder,
        contentAlignment: AlignmentDirectional.topStart,
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.xxl.du(context)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  AppIcon(icon, size: 34),
                  const Spacer(),
                  if (selected)
                    AppIcon(
                      PhosphorIconsFill.checkCircle,
                      size: 28,
                      tint: AppColors.accent300,
                    ),
                ],
              ),
              SizedBox(height: 20.du(context)),
              AppText(title, style: AppTypography.title2, color: null),
              SizedBox(height: AppSpacing.md.du(context)),
              AppText(
                body,
                style: AppTypography.caption.copyWith(height: 1.5),
                color: AppColors.ink2,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---- O2 · Link Plex --------------------------------------------------------

const _pollInterval = Duration(seconds: 2);

class _LinkStep extends ConsumerStatefulWidget {
  final VoidCallback onBack;
  final ValueChanged<String> onLinked;
  final bool relinking;
  final Map<SetupStep, String> summaries;
  final bool showSteps;
  final String kicker;

  const _LinkStep({
    required this.onBack,
    required this.onLinked,
    this.relinking = false,
    this.showSteps = true,
    this.kicker = 'STEP 2 OF 4 · PLEX',
    this.summaries = const {
      SetupStep.servers: 'Plex',
      SetupStep.link: '1 of 1',
    },
  });

  @override
  ConsumerState<_LinkStep> createState() => _LinkStepState();
}

/// The four-character code, large, with a QR to plex.tv/link beside it.
/// The code refreshes itself when Plex expires it and says so — no
/// "code expired" dead end. A failure names what failed and keeps both
/// ways forward (a new code, or Back).
class _LinkStepState extends ConsumerState<_LinkStep> {
  final _newCodeFocus = FocusNode(debugLabel: 'setup-new-code');
  String? _code;
  String? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _start();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _newCodeFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _generation++;
    _newCodeFocus.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final generation = ++_generation;
    setState(() {
      _code = null;
      _error = null;
    });
    try {
      final clientIdentifier = await ref
          .read(plexIdentityProvider)
          .getOrCreateClientIdentifier();
      final api = PlexAuthApi(clientIdentifier);
      while (mounted && generation == _generation) {
        final pin = await api.createPin();
        if (!mounted || generation != _generation) return;
        setState(() => _code = pin.code);
        final deadline = DateTime.now().add(Duration(seconds: pin.expiresIn));
        while (DateTime.now().isBefore(deadline)) {
          await Future.delayed(_pollInterval);
          if (!mounted || generation != _generation) return;
          final token = (await api.pollPin(pin.id)).authToken;
          if (token != null) {
            widget.onLinked(token);
            return;
          }
        }
        // Expired unused: loop round for a fresh code on its own.
      }
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(
        () => _error = 'Couldn’t reach plex.tv to get a code. Check the TV’s connection, then try a new code.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final code = _code;
    return OnboardingFrame(
      step: SetupStep.link,
      // The title runs to two lines at large UI sizes; the tighter top keeps
      // New code / Back on screen without scrolling.
      contentTop: 80,
      summaries: widget.summaries,
      showSteps: widget.showSteps,
      footnote: 'Reelay never sees your password. Plex hands back a token for this TV only, and it stays on the device.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          widget.relinking
              ? const StepHeading(
                  kicker: 'PLEX SIGNED THIS TV OUT',
                  title: 'Link this TV to Plex again',
                  body:
                      'It was removed from your Plex account\'s devices. '
                      'Link it again and everything else is as you left it.',
                )
              : StepHeading(
                  kicker: widget.kicker,
                  title: 'Link this TV to your Plex account',
                ),
          SizedBox(height: 32.du(context)),
          // QR beside the code, as in O2 — stacking them pushed the code and
          // the buttons below the fold at large UI sizes.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 300.du(context),
                    height: 300.du(context),
                    padding: EdgeInsets.all(AppSpacing.xl.du(context)),
                    decoration: BoxDecoration(
                      color: AppColors.inkOnArt,
                      borderRadius: BorderRadius.circular(
                        AppShape.radiusLg.du(context),
                      ),
                    ),
                    child: QrImageView(
                      data: 'https://plex.tv/link',
                      backgroundColor: AppColors.inkOnArt,
                    ),
                  ),
                  SizedBox(height: 18.du(context)),
                  AppText(
                    'Scan with any phone camera',
                    style: AppTypography.caption,
                  ),
                ],
              ),
              SizedBox(width: 56.du(context)),
              Flexible(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: 640.du(context)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppText(
                        'Scanning opens plex.tv/link on your phone. Sign in there if you need to, and enter the code below.',
                        style: AppTypography.body,
                      ),
                      SizedBox(height: 26.du(context)),
                      Container(
                        padding: EdgeInsets.all(28.du(context)),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          border: Border.all(
                            color: AppColors.line,
                            width: 1.du(context),
                          ),
                          borderRadius: BorderRadius.circular(
                            AppShape.radiusMd.du(context),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AppText(
                              'No camera? On any device open plex.tv/link and enter',
                              style: AppTypography.caption,
                            ),
                            SizedBox(height: 14.du(context)),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: AlignmentDirectional.centerStart,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  for (final (i, ch)
                                      in (code ?? '····')
                                          .split('')
                                          .indexed) ...[
                                    if (i > 0) SizedBox(width: 14.du(context)),
                                    Container(
                                      width: 86.du(context),
                                      height: 110.du(context),
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: AppColors.surfaceRaised,
                                        border: Border.all(
                                          color: AppColors.lineStrong,
                                          width: 1.du(context),
                                        ),
                                        borderRadius: BorderRadius.circular(
                                          AppShape.radiusMd.du(context),
                                        ),
                                      ),
                                      child: AppText(
                                        ch,
                                        style: AppTypography.display,
                                        color: code == null
                                            ? AppColors.ink4
                                            : AppColors.ink,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 26.du(context)),
                      Row(
                        children: [
                          Container(
                            width: 9.du(context),
                            height: 9.du(context),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _error != null
                                  ? AppColors.error
                                  : AppColors.warning,
                            ),
                          ),
                          SizedBox(width: 14.du(context)),
                          Flexible(
                            child: AppText(
                              _error ??
                                  (code == null
                                      ? 'Asking Plex for a code…'
                                      : 'Waiting for you to approve it · the code refreshes on its own'),
                              style: AppTypography.label,
                              color: AppColors.ink2,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      footer: Row(
        children: [
          AppOutlinedButton(
            onClick: _start,
            focusNode: _newCodeFocus,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AppIcon(PhosphorIconsRegular.arrowsClockwise, size: 22),
                SizedBox(width: AppSpacing.md.du(context)),
                AppText('New code', style: AppTypography.label, color: null),
              ],
            ),
          ),
          SizedBox(width: AppSpacing.lg.du(context)),
          AppOutlinedButton(
            onClick: widget.onBack,
            child: AppText('Back', style: AppTypography.label, color: null),
          ),
        ],
      ),
    );
  }
}
