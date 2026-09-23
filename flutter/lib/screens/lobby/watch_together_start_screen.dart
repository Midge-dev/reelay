import 'package:flutter/widgets.dart';

import '../../kit/button.dart';
import '../../kit/focusable_surface.dart';
import '../../kit/icon.dart';
import '../../kit/radio_button.dart';
import '../../kit/surface_style.dart';
import '../../kit/switch.dart';
import '../../kit/text.dart';
import '../../theme/phosphor_icons.dart';
import '../../theme/scale.dart';
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
    // A dialog over the page it came from (screen 09): scrim.dialog, flat,
    // never a blur.
    return ColoredBox(
      color: AppScrims.dialog,
      child: Center(
        child: Container(
          width: 860.du(context),
          padding: EdgeInsets.all(AppSpacing.xxxl.du(context)),
          decoration: BoxDecoration(
            color: AppColors.surfaceOverlay,
            border: Border.all(color: AppColors.lineStrong),
            borderRadius: BorderRadius.circular(AppShape.radiusLg.du(context)),
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
                  SizedBox(width: AppSpacing.md.du(context)),
                  AppText(
                    'WATCH TOGETHER',
                    style: AppTypography.micro,
                    color: AppColors.accent300,
                  ),
                ],
              ),
              SizedBox(height: AppSpacing.lg.du(context)),
              AppText(
                'Start a room for ${widget.roomTitle}',
                style: AppTypography.title2,
              ),
              SizedBox(height: AppSpacing.xl.du(context)),
              _ChoiceRow(
                title: 'Resume',
                subtitle: 'Where you left off',
                selected: !_restart,
                onClick: () => setState(() => _restart = false),
              ),
              SizedBox(height: AppSpacing.sm.du(context)),
              _ChoiceRow(
                title: 'Start from the beginning',
                subtitle: 'Everyone sees it fresh',
                selected: _restart,
                onClick: () => setState(() => _restart = true),
              ),
              SizedBox(height: AppSpacing.lg.du(context)),
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
                  SizedBox(width: AppSpacing.md.du(context)),
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
              SizedBox(height: AppSpacing.lg.du(context)),
              _RelayStatusRow(
                check: _relayCheck,
                relayNickname: widget.relayNickname,
              ),
              SizedBox(height: AppSpacing.xl.du(context)),
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
                        SizedBox(width: AppSpacing.sm.du(context)),
                        const AppText('Open the room'),
                      ],
                    ),
                  ),
                  SizedBox(width: AppSpacing.md.du(context)),
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

RoundedRectangleBorder _choiceShape(BuildContext context) =>
    RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppShape.radiusMd.du(context)),
    );
SurfaceColors get _choiceColors => SurfaceColors(
  container: AppColors.surface,
  content: AppColors.ink2,
  focusedContainer: AppColors.surfaceRaised,
  focusedContent: AppColors.ink,
  selectedContainer: AppColors.surfaceRaised,
  selectedContent: AppColors.ink,
);
SurfaceBorder get _choiceBorder => SurfaceBorder(
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
      constraints: BoxConstraints(minHeight: 88.du(context)),
      child: FocusableSurface(
        onClick: onClick,
        selected: selected,
        shape: _choiceShape(context),
        colors: _choiceColors,
        border: _choiceBorder,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.xl.du(context)),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppText(title, style: AppTypography.label),
                    SizedBox(height: 3.du(context)),
                    AppText(
                      subtitle,
                      style: AppTypography.caption,
                      color: AppColors.ink3,
                    ),
                  ],
                ),
              ),
              SizedBox(width: AppSpacing.lg.du(context)),
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
      constraints: BoxConstraints(minHeight: 88.du(context)),
      padding: EdgeInsets.symmetric(horizontal: AppSpacing.xl.du(context)),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.lineStrong),
        borderRadius: BorderRadius.circular(AppShape.radiusMd.du(context)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText(title, color: AppColors.ink2),
                SizedBox(height: 3.du(context)),
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
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.lg.du(context),
        vertical: AppSpacing.md.du(context),
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        border: Border(
          left: BorderSide(color: color, width: AppShape.spineWidth.du(context)),
        ),
        borderRadius: BorderRadius.circular(AppShape.radiusSm.du(context)),
      ),
      child: Row(
        children: [
          Container(
            width: 8.du(context),
            height: 8.du(context),
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          SizedBox(width: AppSpacing.md.du(context)),
          Expanded(child: AppText(label, color: AppColors.ink2)),
        ],
      ),
    );
  }
}
