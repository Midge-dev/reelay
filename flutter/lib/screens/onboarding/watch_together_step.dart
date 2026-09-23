import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../data/settings/app_settings.dart';
import '../../kit/button.dart';
import '../../kit/focusable_surface.dart';
import '../../kit/icon.dart';
import '../../kit/surface_style.dart';
import '../../kit/text.dart';
import '../../pairing/pairing_server.dart';
import '../../state/data_providers.dart';
import '../../theme/phosphor_icons.dart';
import '../../theme/scale.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../common/click_to_type_text_field.dart';
import 'onboarding_frame.dart';

const _uuid = Uuid();

/// Screen O4 — Watch Together, the one optional step and the only one that
/// says what declining costs. Pairing from a phone leads; pasting a URL is
/// there for someone who already has one. Either way, or "Not now", marks
/// setup complete so the question is never asked again (see
/// AppSettings.setupComplete). Used both inside first-run setup and on its
/// own for an install that was set up before this step existed.
class WatchTogetherStep extends ConsumerStatefulWidget {
  final VoidCallback onDone;

  const WatchTogetherStep({super.key, required this.onDone});

  @override
  ConsumerState<WatchTogetherStep> createState() => _WatchTogetherStepState();
}

class _WatchTogetherStepState extends ConsumerState<WatchTogetherStep> {
  final _phoneFocus = FocusNode(debugLabel: 'setup-relay-phone');
  final _urlFocus = FocusNode(debugLabel: 'setup-relay-url');
  final _cancelPairingFocus = FocusNode(debugLabel: 'setup-relay-cancel');
  String _url = '';
  PairingServer? _pairing;
  String? _pairingUrl;
  String? _pairingError;
  bool _saving = false;
  bool _urlFocused = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _phoneFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _pairing?.stop();
    _phoneFocus.dispose();
    _urlFocus.dispose();
    _cancelPairingFocus.dispose();
    super.dispose();
  }

  Future<void> _finish({String? nickname, String? url}) async {
    if (_saving) return;
    setState(() => _saving = true);
    final store = ref.read(settingsStoreProvider);
    final current = await store.observe().first;
    final trimmed = url?.trim() ?? '';
    await store.save(
      current.copyWith(
        setupComplete: true,
        relays: trimmed.isEmpty
            ? current.relays
            : [
                ...current.relays,
                RelayEntry(
                  id: _uuid.v4(),
                  nickname: (nickname?.trim().isNotEmpty ?? false)
                      ? nickname!.trim()
                      : 'My relay',
                  url: trimmed,
                  isDefault: current.relays.isEmpty,
                ),
              ],
      ),
    );
    if (mounted) widget.onDone();
  }

  Future<void> _startPairing() async {
    setState(() => _pairingError = null);
    final server = PairingServer(
      onSubmitted: (nickname, url) => _finish(nickname: nickname, url: url),
    );
    final url = await server.start();
    if (!mounted) return;
    if (url == null) {
      setState(
        () => _pairingError = 'This TV has no Wi-Fi address to pair over. Check its network, or paste a relay URL instead.',
      );
      return;
    }
    setState(() {
      _pairing = server;
      _pairingUrl = url;
    });
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _cancelPairingFocus.requestFocus(),
    );
  }

  void _cancelPairing() {
    _pairing?.stop();
    setState(() {
      _pairing = null;
      _pairingUrl = null;
    });
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _phoneFocus.requestFocus(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingFrame(
      step: SetupStep.watchTogether,
      contentTop: 110,
      summaries: const {
        SetupStep.servers: 'Plex',
        SetupStep.link: 'Plex',
        SetupStep.watchTogether: 'Optional',
      },
      footnote: 'A relay only passes play, pause, seek and chat messages between you. No video goes through it — that still comes straight from your own server.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const StepHeading(
            kicker: 'STEP 3 OF 4 · OPTIONAL',
            title: 'Watch with someone who isn’t here',
            bodyMaxWidth: 760,
            body:
                'Watch Together keeps your playback in step with friends and family in another house, and carries the chat they send from their phones. '
                'Both need a relay server — a small free service you or they host once.',
          ),
          SizedBox(height: 44.du(context)),
          if (_pairingUrl != null)
            _pairingPanel(context)
          else
            _choices(context),
          if (_pairingError != null) ...[
            SizedBox(height: AppSpacing.lg.du(context)),
            AppText(
              _pairingError!,
              style: AppTypography.caption,
              color: AppColors.warning,
            ),
          ],
        ],
      ),
      footer: _skipBar(context),
    );
  }

  Widget _choices(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.xl.du(context),
      runSpacing: AppSpacing.xl.du(context),
      children: [
        SizedBox(
          width: 480.du(context),
          child: _WayInCard(
            focusNode: _phoneFocus,
            icon: PhosphorIconsRegular.deviceMobile,
            title: 'Set it up from my phone',
            body: 'Shows a code to scan; paste your relay’s address on the phone and it arrives here. No typing on the TV.',
            footer: AppText(
              'Recommended',
              style: AppTypography.caption,
              color: AppColors.accent300,
            ),
            onClick: _startPairing,
          ),
        ),
        SizedBox(
          width: 420.du(context),
          child: _WayInCard(
            icon: PhosphorIconsRegular.linkSimple,
            title: 'I already have one',
            body: 'Type or paste the relay URL.',
            onClick: () => _urlFocus.requestFocus(),
            footer: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  height: 56.du(context),
                  padding: EdgeInsets.symmetric(horizontal: 18.du(context)),
                  alignment: AlignmentDirectional.centerStart,
                  decoration: BoxDecoration(
                    color: _urlFocused
                        ? AppColors.surfaceRaised
                        : AppColors.background,
                    border: Border.all(
                      color: _urlFocused ? AppColors.accent : AppColors.line,
                      width: AppShape.borderWidth.du(context),
                    ),
                    borderRadius: BorderRadius.circular(
                      AppShape.radiusMd.du(context),
                    ),
                  ),
                  child: ClickToTypeTextField(
                    onFocusChange: (f) => setState(() => _urlFocused = f),
                    value: _url,
                    onValueChange: (v) => setState(() => _url = v),
                    focusNode: _urlFocus,
                    hintText: 'wss://…',
                    showBorder: false,
                    textStyle: AppTypography.caption.copyWith(
                      color: AppColors.ink,
                    ),
                  ),
                ),
                if (_url.trim().isNotEmpty) ...[
                  SizedBox(height: AppSpacing.md.du(context)),
                  AppButton(
                    onClick: () => _finish(url: _url),
                    child: AppText(
                      'Use this relay',
                      style: AppTypography.label,
                      color: null,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _pairingPanel(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(28.du(context)),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.line, width: 1.du(context)),
        borderRadius: BorderRadius.circular(AppShape.radiusMd.du(context)),
      ),
      child: Wrap(
        spacing: AppSpacing.xxl.du(context),
        runSpacing: AppSpacing.xl.du(context),
        children: [
          Container(
            width: 220.du(context),
            height: 220.du(context),
            padding: EdgeInsets.all(AppSpacing.lg.du(context)),
            decoration: BoxDecoration(
              color: AppColors.inkOnArt,
              borderRadius: BorderRadius.circular(
                AppShape.radiusLg.du(context),
              ),
            ),
            child: QrImageView(
              data: _pairingUrl!,
              backgroundColor: AppColors.inkOnArt,
            ),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 560.du(context)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                AppText(
                  'Scan with a phone on the same Wi-Fi as this TV, or open',
                  style: AppTypography.body,
                ),
                SizedBox(height: AppSpacing.sm.du(context)),
                AppText(
                  _pairingUrl!,
                  style: AppTypography.label,
                  color: AppColors.ink,
                ),
                SizedBox(height: AppSpacing.md.du(context)),
                AppText(
                  'Paste your relay’s address there and this step finishes on its own.',
                  style: AppTypography.caption,
                ),
                SizedBox(height: AppSpacing.xl.du(context)),
                AppOutlinedButton(
                  onClick: _cancelPairing,
                  focusNode: _cancelPairingFocus,
                  child: AppText(
                    'Cancel',
                    style: AppTypography.label,
                    color: null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _skipBar(BuildContext context) {
    return CustomPaint(
      foregroundPainter: LeadingSpinePainter(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppShape.radiusMd.du(context)),
        ),
        color: AppColors.warning,
        width: AppSpacing.xs.du(context),
      ),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: 28.du(context),
          vertical: AppSpacing.xl.du(context),
        ),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.line, width: 1.du(context)),
          borderRadius: BorderRadius.circular(AppShape.radiusMd.du(context)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppText(
                    'Skipping is fine',
                    style: AppTypography.body,
                    color: AppColors.ink,
                  ),
                  SizedBox(height: 5.du(context)),
                  AppText(
                    'Watch Together stays hidden until you add a relay — no empty rows, no prompts. '
                    'Everything else works exactly the same, and you can add one from Settings whenever.',
                    style: AppTypography.caption.copyWith(height: 1.5),
                  ),
                ],
              ),
            ),
            SizedBox(width: 28.du(context)),
            AppOutlinedButton(
              onClick: () => _finish(),
              child: AppText(
                'Not now',
                style: AppTypography.label,
                color: null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

SurfaceColors get _wayInColors => SurfaceColors(
  container: AppColors.surface,
  content: AppColors.ink2,
  focusedContainer: AppColors.surfaceRaised,
  focusedContent: AppColors.ink,
);
SurfaceBorder get _wayInBorder => SurfaceBorder(
  idle: SurfaceBorderSide.solid(AppColors.line),
  focused: SurfaceBorderSide.solid(AppColors.accent),
);

class _WayInCard extends StatelessWidget {
  final FocusNode? focusNode;
  final IconData icon;
  final String title;
  final String body;
  final Widget? footer;
  final VoidCallback onClick;

  const _WayInCard({
    this.focusNode,
    required this.icon,
    required this.title,
    required this.body,
    this.footer,
    required this.onClick,
  });

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: EdgeInsets.all(AppSpacing.xxl.du(context)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: AppIcon(icon, size: 32),
          ),
          SizedBox(height: 20.du(context)),
          AppText(title, style: AppTypography.title2, color: null),
          SizedBox(height: 14.du(context)),
          AppText(
            body,
            style: AppTypography.caption.copyWith(height: 1.55),
            color: AppColors.ink2,
          ),
          if (footer != null) ...[
            SizedBox(height: AppSpacing.xl.du(context)),
            footer!,
          ],
        ],
      ),
    );
    // The URL card holds its own focusable field; making the whole card a
    // focus target too would put two leaves where there should be one.
    if (focusNode == null) {
      return Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(
            color: AppColors.line,
            width: AppShape.borderWidth.du(context),
          ),
          borderRadius: BorderRadius.circular(AppShape.radiusMd.du(context)),
        ),
        child: content,
      );
    }
    return FocusableSurface(
      onClick: onClick,
      focusNode: focusNode,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppShape.radiusMd.du(context)),
      ),
      colors: _wayInColors,
      border: _wayInBorder,
      contentAlignment: AlignmentDirectional.topStart,
      child: content,
    );
  }
}
