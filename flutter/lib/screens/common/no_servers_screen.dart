import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../data/plex/plex_models.dart';
import '../../kit/button.dart';
import '../../kit/icon.dart';
import '../../kit/text.dart';
import '../../theme/phosphor_icons.dart';
import '../../theme/scale.dart';
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

  const NoServersScreen({
    super.key,
    required this.resources,
    required this.onRetry,
    required this.onStartOver,
  });

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
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _retryFocus.requestFocus(),
    );
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
          constraints: BoxConstraints(maxWidth: 900.du(context)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(
                PhosphorIconsRegular.cloudSlash,
                size: 72,
                tint: AppColors.lineStrong,
              ),
              SizedBox(height: 18.du(context)),
              AppText(
                "Can't reach any of your servers",
                style: AppTypography.title1,
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 12.du(context)),
              AppText(
                'Nothing is wrong with Reelay or your account. ${count == 1 ? 'One server is' : '$count servers are'} configured and none of them answered.',
                color: AppColors.ink3,
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 40.du(context)),
              if (widget.resources.isNotEmpty)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final resource in widget.resources) ...[
                      _ServerRow(resource: resource),
                      SizedBox(height: 10.du(context)),
                    ],
                  ],
                ),
              SizedBox(height: 30.du(context)),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppButton(
                    onClick: widget.onRetry,
                    focusNode: _retryFocus,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const AppIcon(
                          PhosphorIconsRegular.arrowClockwise,
                          size: 22,
                        ),
                        SizedBox(width: AppSpacing.sm.du(context)),
                        const AppText('Try again now'),
                      ],
                    ),
                  ),
                  SizedBox(width: AppSpacing.md.du(context)),
                  AppOutlinedButton(
                    onClick: widget.onStartOver,
                    child: const AppText('Start over'),
                  ),
                ],
              ),
              SizedBox(height: 18.du(context)),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppIcon(
                    PhosphorIconsRegular.clock,
                    size: 20,
                    tint: AppColors.ink4,
                  ),
                  SizedBox(width: AppSpacing.sm.du(context)),
                  AppText(
                    'Trying again on its own in $_secondsRemaining second${_secondsRemaining == 1 ? '' : 's'}',
                    color: AppColors.ink4,
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

class _ServerRow extends StatelessWidget {
  final PlexResource resource;

  const _ServerRow({required this.resource});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: 82.du(context)),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: AppSpacing.xl.du(context)),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.line),
          borderRadius: BorderRadius.circular(AppShape.radiusMd.du(context)),
        ),
        child: Row(
          children: [
            AppIcon(
              PhosphorIconsRegular.hardDrives,
              size: 24,
              tint: AppColors.ink3,
            ),
            SizedBox(width: AppSpacing.lg.du(context)),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText(resource.name, color: AppColors.ink2),
                  SizedBox(height: 3.du(context)),
                  AppText(
                    _detail(resource),
                    style: AppTypography.caption,
                    color: AppColors.ink3,
                  ),
                ],
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 9.du(context),
                  height: 9.du(context),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.error,
                  ),
                ),
                SizedBox(width: AppSpacing.sm.du(context)),
                AppText(
                  'Unreachable',
                  style: AppTypography.caption,
                  color: AppColors.error,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// "Plex · 192.168.0.12 · no answer on the local network" — the address
/// this TV tried first and where it lives, for the person who owns the
/// machine and can act on it (screen 24).
String _detail(PlexResource resource) {
  final connections = resource.connections;
  final first =
      connections.where((c) => c.local && !c.relay).firstOrNull ??
      connections.where((c) => !c.relay).firstOrNull;
  var host = first == null ? null : Uri.tryParse(first.uri)?.host;
  // Plex hands out "192-168-0-12.<hash>.plex.direct"; the IP is the part
  // the owner recognises.
  if (host != null && host.endsWith('.plex.direct')) {
    host = host.split('.').first.replaceAll('-', '.');
  }
  if (host == null || host.isEmpty) return 'Plex';
  final where = first!.local
      ? 'no answer on the local network'
      : 'no answer over the internet';
  return 'Plex · $host · $where';
}
