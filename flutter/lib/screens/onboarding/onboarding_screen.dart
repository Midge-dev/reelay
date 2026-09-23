import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../data/plex/plex_auth_api.dart';
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
import 'onboarding_frame.dart';
import 'watch_together_step.dart';

enum _Step { servers, link, watchTogether }

/// First-run setup, screens O1 → O2 → O4 (O3, Link Jellyfin, stays
/// unreachable until Jellyfin ships — DESIGN.md). Linking stores the
/// token but setup only hands it on once the Watch Together step has been
/// answered, so the relay question comes before the library loads, in the
/// design's order, and is never asked again. O5 is the connecting screen
/// that follows (see setup_ready_screen.dart).
///
/// [relinking]: Plex refused this TV's saved sign-in (it was removed from
/// the account's devices). Setup opens on the link step and says so, and
/// linking goes straight back in — everything else was already answered.
class OnboardingScreen extends ConsumerStatefulWidget {
  final ValueChanged<String> onComplete;
  final bool relinking;

  const OnboardingScreen({
    super.key,
    required this.onComplete,
    this.relinking = false,
  });

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  late _Step _step = widget.relinking ? _Step.link : _Step.servers;
  bool _plexSelected = true;
  String? _token;

  @override
  Widget build(BuildContext context) {
    return switch (_step) {
      _Step.servers => _ServersStep(
        plexSelected: _plexSelected,
        onTogglePlex: () => setState(() => _plexSelected = !_plexSelected),
        onContinue: () => setState(() => _step = _Step.link),
      ),
      _Step.link => BackHandler(
        onBack: () => setState(() => _step = _Step.servers),
        child: _LinkStep(
          relinking: widget.relinking,
          onBack: () => setState(() => _step = _Step.servers),
          onLinked: (token) async {
            await ref.read(secureTokenStoreProvider).saveToken(token);
            if (!mounted) return;
            if (widget.relinking) {
              widget.onComplete(token);
              return;
            }
            setState(() {
              _token = token;
              _step = _Step.watchTogether;
            });
          },
        ),
      ),
      _Step.watchTogether => BackHandler(
        onBack: () => setState(() => _step = _Step.servers),
        child: WatchTogetherStep(onDone: () => widget.onComplete(_token!)),
      ),
    };
  }
}

// ---- O1 · Where's your library? -------------------------------------------

class _ServersStep extends StatefulWidget {
  final bool plexSelected;
  final VoidCallback onTogglePlex;
  final VoidCallback onContinue;

  const _ServersStep({
    required this.plexSelected,
    required this.onTogglePlex,
    required this.onContinue,
  });

  @override
  State<_ServersStep> createState() => _ServersStepState();
}

class _ServersStepState extends State<_ServersStep> {
  final _plexFocus = FocusNode(debugLabel: 'setup-plex-card');

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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingFrame(
      step: SetupStep.servers,
      footnote: 'All of this can be changed later in Settings. Nothing here is permanent.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const StepHeading(
            kicker: 'STEP 1 OF 4',
            title: 'Where’s your library?',
            body:
                'Reelay is built to talk to Plex and Jellyfin equally well, and to more than one of each. '
                'Jellyfin is not connectable yet — the card is here so the shape of the choice is right from the first release.',
          ),
          SizedBox(height: 42.du(context)),
          // Side by side as in O1; at large UI sizes the cards narrow rather
          // than stacking, which pushed Jellyfin and Continue off-screen.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                child: _ChoiceCard(
                  focusNode: _plexFocus,
                  selected: widget.plexSelected,
                  icon: PhosphorIconsFill.hardDrives,
                  title: 'Plex',
                  body: 'Sign in once on your phone. Shared servers come with you.',
                  onClick: widget.onTogglePlex,
                ),
              ),
              SizedBox(width: AppSpacing.xl.du(context)),
              // Disabled per DESIGN.md until Jellyfin support ships —
              // FocusableSurface's disabled state is exactly the rule: 45%
              // opacity and out of the focus order. A stated dead end, not
              // a live card that leads nowhere.
              Flexible(
                child: _ChoiceCard(
                  selected: false,
                  enabled: false,
                  icon: PhosphorIconsRegular.hardDrives,
                  title: 'Jellyfin',
                  body: 'Your own server address and account, paired from your phone. Not connectable yet.',
                  badge: 'COMING SOON',
                  onClick: () {},
                ),
              ),
            ],
          ),
        ],
      ),
      footer: Row(
        children: [
          AppOutlinedButton(
            onClick: widget.onContinue,
            enabled: widget.plexSelected,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppText('Continue', style: AppTypography.label, color: null),
                SizedBox(width: AppSpacing.md.du(context)),
                const AppIcon(PhosphorIconsRegular.arrowRight, size: 22),
              ],
            ),
          ),
          if (!widget.plexSelected) ...[
            SizedBox(width: 20.du(context)),
            AppText(
              'Select at least one to continue',
              style: AppTypography.caption,
            ),
          ],
        ],
      ),
    );
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
  final bool enabled;
  final IconData icon;
  final String title;
  final String body;
  final String? badge;
  final VoidCallback onClick;

  const _ChoiceCard({
    this.focusNode,
    required this.selected,
    this.enabled = true,
    required this.icon,
    required this.title,
    required this.body,
    this.badge,
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
        enabled: enabled,
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
                  if (badge != null)
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Container(
                          height: 34.du(context),
                          padding: EdgeInsets.symmetric(
                            horizontal: AppSpacing.md.du(context),
                          ),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.line,
                            borderRadius: BorderRadius.circular(
                              AppShape.radiusSm.du(context),
                            ),
                          ),
                          child: AppText(
                            badge!,
                            style: AppTypography.micro,
                            color: AppColors.ink2,
                          ),
                        ),
                      ),
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

  const _LinkStep({
    required this.onBack,
    required this.onLinked,
    this.relinking = false,
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
      summaries: const {SetupStep.servers: 'Plex', SetupStep.link: '1 of 1'},
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
              : const StepHeading(
                  kicker: 'STEP 2 OF 4 · PLEX',
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
