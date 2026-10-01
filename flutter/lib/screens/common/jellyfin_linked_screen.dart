import 'package:flutter/widgets.dart';

import '../../kit/button.dart';
import '../../kit/icon.dart';
import '../../kit/text.dart';
import '../../theme/phosphor_icons.dart';
import '../../theme/scale.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';

/// A Jellyfin-only profile before its libraries can be browsed: one icon,
/// what's true, what happens next — rather than an empty home. Goes away
/// when Jellyfin browsing lands.
class JellyfinLinkedScreen extends StatefulWidget {
  final String serverName;
  final String username;
  final VoidCallback onStartOver;

  const JellyfinLinkedScreen({
    super.key,
    required this.serverName,
    required this.username,
    required this.onStartOver,
  });

  @override
  State<JellyfinLinkedScreen> createState() => _JellyfinLinkedScreenState();
}

class _JellyfinLinkedScreenState extends State<JellyfinLinkedScreen> {
  final _startOverFocus = FocusNode(debugLabel: 'jellyfin-linked-start-over');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _startOverFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _startOverFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.canvas,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 900.du(context)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(
                PhosphorIconsRegular.hardDrives,
                size: 72,
                tint: AppColors.lineStrong,
              ),
              SizedBox(height: 18.du(context)),
              AppText(
                'Linked to ${widget.serverName} as ${widget.username}',
                style: AppTypography.title1,
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 12.du(context)),
              AppText(
                'Browsing Jellyfin libraries isn’t in this build yet. Your sign-in is saved, so they’ll appear here once it is.',
                color: AppColors.ink3,
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 40.du(context)),
              AppOutlinedButton(
                onClick: widget.onStartOver,
                focusNode: _startOverFocus,
                child: AppText(
                  'Set up again',
                  style: AppTypography.label,
                  color: null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
