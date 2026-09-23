import 'dart:math';

import 'package:flutter/widgets.dart';

import '../../kit/icon.dart';
import '../../kit/text.dart';
import '../../theme/phosphor_icons.dart';
import '../../theme/scale.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import 'onboarding_frame.dart';

const _flavor = [
  'Dimming the house lights…',
  'Buttering the popcorn…',
  'Finding your seat…',
  'Cueing up the trailers…',
];

/// Screen O5 — "Ready, the work itemised". Replaces the bare spinner at the
/// end of setup: the step column stays, and the connection's real progress
/// is listed as it completes (signed in, servers reached, libraries found,
/// what is loading now), with the popcorn line kept underneath for warmth.
/// Home opens on its own when loading finishes — nothing to press.
class SetupReadyScreen extends StatefulWidget {
  final List<String> done;
  final String? current;
  final String? headline;

  const SetupReadyScreen({
    super.key,
    required this.done,
    this.current,
    this.headline,
  });

  @override
  State<SetupReadyScreen> createState() => _SetupReadyScreenState();
}

class _SetupReadyScreenState extends State<SetupReadyScreen> {
  late final String _line = _flavor[Random().nextInt(_flavor.length)];

  @override
  Widget build(BuildContext context) {
    final gap = SizedBox(height: AppSpacing.lg.du(context));
    return OnboardingFrame(
      step: SetupStep.ready,
      contentTop: 110,
      summaries: const {
        SetupStep.servers: 'Plex',
        SetupStep.link: 'Plex',
        SetupStep.watchTogether: 'Done',
      },
      footnote: 'Nothing is written until it succeeds. Everything here can be changed later in Settings.',
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 820.du(context)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            StepHeading(
              kicker: 'STEP 4 OF 4',
              title: widget.headline ?? 'Getting your library ready',
              body: 'This opens on its own as soon as your library has loaded.',
            ),
            SizedBox(height: 30.du(context)),
            Container(
              padding: EdgeInsets.all(28.du(context)),
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: Border.all(color: AppColors.line, width: 1.du(context)),
                borderRadius: BorderRadius.circular(
                  AppShape.radiusMd.du(context),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final (i, line) in widget.done.indexed) ...[
                    if (i > 0) gap,
                    Row(
                      children: [
                        AppIcon(
                          PhosphorIconsFill.checkCircle,
                          size: 22,
                          tint: AppColors.success,
                        ),
                        SizedBox(width: AppSpacing.lg.du(context)),
                        Expanded(
                          child: AppText(
                            line,
                            style: AppTypography.label,
                            color: AppColors.ink2,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (widget.current != null) ...[
                    if (widget.done.isNotEmpty) gap,
                    Row(
                      children: [
                        SizedBox(
                          width: 22.du(context),
                          child: Center(
                            child: Container(
                              width: 9.du(context),
                              height: 9.du(context),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.warning,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: AppSpacing.lg.du(context)),
                        Expanded(
                          child: AppText(
                            '${widget.current}…',
                            style: AppTypography.label,
                            color: AppColors.ink,
                          ),
                        ),
                      ],
                    ),
                  ],
                  SizedBox(height: 20.du(context)),
                  Container(height: 1.du(context), color: AppColors.line),
                  gap,
                  AppText(_line, style: AppTypography.caption),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
