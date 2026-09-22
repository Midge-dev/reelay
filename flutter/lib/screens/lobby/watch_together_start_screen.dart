import 'package:flutter/widgets.dart';

import '../../kit/button.dart';
import '../../kit/focusable_surface.dart';
import '../../kit/icon.dart';
import '../../kit/radio_button.dart';
import '../../kit/surface_style.dart';
import '../../kit/switch.dart';
import '../../kit/text.dart';
import '../../theme/phosphor_icons.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';

/// Screen 09 — "three decisions, one confirm" before a room opens.
/// Rendered as its own full screen, matching PlaybackFailed's disclosed
/// simplification (no literal dimmed-detail-page-behind-it). Seats shows
/// the account's configured max (not editable here — changing it lives in
/// Settings); Phone chat is a real, working toggle in this UI but isn't
/// wired to a specific effect yet (see the code's own note at its call
/// site) — disclosed rather than either faked or dropped from the layout.
class WatchTogetherStartScreen extends StatefulWidget {
  final String roomTitle;
  final bool defaultRestart;
  final int maxSeats;
  final String? relayNickname;
  final Future<bool> Function()? checkRelayReachable;
  final void Function({required bool restart, required bool showPhoneChat})
  onConfirm;
  final VoidCallback onCancel;

  const WatchTogetherStartScreen({
    super.key,
    required this.roomTitle,
    this.defaultRestart = false,
    required this.maxSeats,
    this.relayNickname,
    this.checkRelayReachable,
    required this.onConfirm,
    required this.onCancel,
  });

  @override
  State<WatchTogetherStartScreen> createState() =>
      _WatchTogetherStartScreenState();
}

enum _RelayCheck { checking, reachable, unreachable, unknown }

class _WatchTogetherStartScreenState extends State<WatchTogetherStartScreen> {
  late bool _restart = widget.defaultRestart;
  bool _phoneChatEnabled = true;
  _RelayCheck _relayCheck = _RelayCheck.unknown;
  final _confirmFocus = FocusNode(debugLabel: 'wt-start-confirm');

  @override
  void initState() {
    super.initState();
    final check = widget.checkRelayReachable;
    if (check != null) {
      setState(() => _relayCheck = _RelayCheck.checking);
      check().then((reachable) {
        if (mounted)
          setState(
            () => _relayCheck = reachable
                ? _RelayCheck.reachable
                : _RelayCheck.unreachable,
          );
      });
    }
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _confirmFocus.requestFocus(),
    );
  }

  @override
  void dispose() {
    _confirmFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.background,
      child: Center(
        child: Container(
          width: 860,
          padding: const EdgeInsets.all(AppSpacing.xxxl),
          decoration: BoxDecoration(
            color: AppColors.surfaceOverlay,
            border: Border.all(color: AppColors.lineStrong),
            borderRadius: BorderRadius.circular(AppShape.radiusLg),
            boxShadow: AppElevation.overlay,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppIcon(
                    PhosphorIconsRegular.usersThree,
                    size: 22,
                    tint: AppColors.accent300,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  AppText(
                    'WATCH TOGETHER',
                    style: AppTypography.micro,
                    color: AppColors.accent300,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              AppText(
                'Start a room for ${widget.roomTitle}',
                style: AppTypography.title2,
              ),
              const SizedBox(height: AppSpacing.xl),
              _ChoiceRow(
                title: 'Resume',
                subtitle: 'Where you left off',
                selected: !_restart,
                onClick: () => setState(() => _restart = false),
              ),
              const SizedBox(height: AppSpacing.sm),
              _ChoiceRow(
                title: 'Start from the beginning',
                subtitle: 'Everyone sees it fresh',
                selected: _restart,
                onClick: () => setState(() => _restart = true),
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: _InfoRow(
                      title: 'Seats',
                      subtitle: 'Including you',
                      trailing: AppText(
                        '${widget.maxSeats}',
                        style: AppTypography.label,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: _InfoRow(
                      title: 'Phone chat',
                      subtitle: 'Show a QR to join',
                      trailing: AppSwitch(
                        checked: _phoneChatEnabled,
                        onCheckedChange: (v) =>
                            setState(() => _phoneChatEnabled = v),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              _RelayStatusRow(
                check: _relayCheck,
                relayNickname: widget.relayNickname,
              ),
              const SizedBox(height: AppSpacing.xl),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppButton(
                    onClick: () => widget.onConfirm(
                      restart: _restart,
                      showPhoneChat: _phoneChatEnabled,
                    ),
                    focusNode: _confirmFocus,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const AppIcon(
                          PhosphorIconsRegular.usersThree,
                          size: 22,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        const AppText('Open the room'),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  AppOutlinedButton(
                    onClick: widget.onCancel,
                    child: const AppText('Cancel'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final _choiceShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.circular(AppShape.radiusMd),
);
final _choiceColors = SurfaceColors(
  container: AppColors.surface,
  content: AppColors.ink2,
  focusedContainer: AppColors.surfaceRaised,
  focusedContent: AppColors.ink,
  selectedContainer: AppColors.surfaceRaised,
  selectedContent: AppColors.ink,
);
final _choiceBorder = SurfaceBorder(
  focused: SurfaceBorderSide.solid(AppColors.accent),
);

class _ChoiceRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onClick;

  const _ChoiceRow({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onClick,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 88),
      child: FocusableSurface(
        onClick: onClick,
        selected: selected,
        shape: _choiceShape,
        colors: _choiceColors,
        border: _choiceBorder,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppText(title, style: AppTypography.label),
                    const SizedBox(height: 3),
                    AppText(
                      subtitle,
                      style: AppTypography.caption,
                      color: AppColors.ink3,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              AppRadioButton(selected: selected),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget trailing;

  const _InfoRow({
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 88),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.lineStrong),
        borderRadius: BorderRadius.circular(AppShape.radiusMd),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText(title, color: AppColors.ink2),
                const SizedBox(height: 3),
                AppText(
                  subtitle,
                  style: AppTypography.caption,
                  color: AppColors.ink3,
                ),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}

class _RelayStatusRow extends StatelessWidget {
  final _RelayCheck check;
  final String? relayNickname;

  const _RelayStatusRow({required this.check, required this.relayNickname});

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (check) {
      _RelayCheck.checking => (AppColors.ink4, 'Checking relay…'),
      _RelayCheck.reachable => (
        AppColors.success,
        'Relay reachable · guests will sync within a frame',
      ),
      _RelayCheck.unreachable => (
        AppColors.error,
        "Relay didn't answer — guests may have trouble joining",
      ),
      _RelayCheck.unknown => (
        AppColors.ink4,
        relayNickname != null ? 'Relay: $relayNickname' : 'No relay configured',
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        border: Border(
          left: BorderSide(color: color, width: AppShape.spineWidth),
        ),
        borderRadius: BorderRadius.circular(AppShape.radiusSm),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: AppText(label, color: AppColors.ink2)),
        ],
      ),
    );
  }
}
