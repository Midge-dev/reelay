import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../data/plex/plex_models.dart';
import '../../kit/button.dart';
import '../../kit/icon.dart';
import '../../kit/text.dart';
import '../../theme/phosphor_icons.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';

const _retrySeconds = 12;

/// Screen 24 — the one failure that earns the whole screen (see
/// NoServersReachable's doc comment for why). Retry is automatic and
/// visibly counting down ("a screen that only recovers when pressed
/// strands anyone who walked away" — the handoff's empty/error explainer);
/// the button just hurries it.
///
/// The mockup's second action, "Server settings", isn't reachable yet —
/// this app's Settings screen requires an active LibraryContext (a
/// connected server), which is exactly what doesn't exist in this state.
/// "Start over" (back to the login screen) is offered instead: a real,
/// honest exit that's actually reachable today, not a placeholder that
/// goes nowhere.
class NoServersScreen extends StatefulWidget {
  final List<PlexResource> resources;
  final VoidCallback onRetry;
  final VoidCallback onStartOver;

  const NoServersScreen({super.key, required this.resources, required this.onRetry, required this.onStartOver});

  @override
  State<NoServersScreen> createState() => _NoServersScreenState();
}

class _NoServersScreenState extends State<NoServersScreen> {
  int _secondsRemaining = _retrySeconds;
  Timer? _timer;
  final _retryFocus = FocusNode(debugLabel: 'no-servers-retry');

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), _tick);
    WidgetsBinding.instance.addPostFrameCallback((_) => _retryFocus.requestFocus());
  }

  void _tick(Timer timer) {
    if (!mounted) return;
    if (_secondsRemaining <= 1) {
      timer.cancel();
      widget.onRetry();
      return;
    }
    setState(() => _secondsRemaining -= 1);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _retryFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.resources.length;
    return ColoredBox(
      color: AppColors.canvas,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AppIcon(PhosphorIconsRegular.cloudSlash, size: 72, tint: AppColors.lineStrong),
              const SizedBox(height: 18),
              const AppText("Can't reach any of your servers", style: AppTypography.title1, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              AppText(
                'Nothing is wrong with Reelay or your account. ${count == 1 ? 'One server is' : '$count servers are'} configured and none of them answered.',
                color: AppColors.ink3,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              if (widget.resources.isNotEmpty)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final resource in widget.resources) ...[
                      _ServerRow(resource: resource),
                      const SizedBox(height: 10),
                    ],
                  ],
                ),
              const SizedBox(height: 30),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppButton(
                    onClick: widget.onRetry,
                    focusNode: _retryFocus,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const AppIcon(PhosphorIconsRegular.arrowClockwise, size: 22),
                      const SizedBox(width: AppSpacing.sm),
                      const AppText('Try again now'),
                    ]),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  AppOutlinedButton(
                    onClick: widget.onStartOver,
                    child: const AppText('Start over'),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const AppIcon(PhosphorIconsRegular.clock, size: 20, tint: AppColors.ink4),
                  const SizedBox(width: AppSpacing.sm),
                  AppText('Trying again on its own in $_secondsRemaining second${_secondsRemaining == 1 ? '' : 's'}', color: AppColors.ink4),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ServerRow extends StatelessWidget {
  final PlexResource resource;

  const _ServerRow({required this.resource});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 82),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.line),
          borderRadius: BorderRadius.circular(AppShape.radiusMd),
        ),
        child: Row(
          children: [
            const AppIcon(PhosphorIconsRegular.hardDrives, size: 24, tint: AppColors.ink3),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText(resource.name, color: AppColors.ink2),
                  const SizedBox(height: 3),
                  const AppText('Plex', style: AppTypography.caption, color: AppColors.ink3),
                ],
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 9, height: 9, decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.error)),
                const SizedBox(width: AppSpacing.sm),
                const AppText('Unreachable', style: AppTypography.caption, color: AppColors.error),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
