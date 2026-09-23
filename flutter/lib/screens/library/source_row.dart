import 'package:flutter/widgets.dart';

import '../../data/plex/plex_models.dart';
import '../../data/plex/plex_resources_api.dart' show ServerReachability;
import '../../kit/card.dart';
import '../../kit/text.dart';
import '../../state/copy_facts.dart';
import '../../state/duplicate_fold.dart';
import '../../theme/scale.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';

const _rowMinHeight = 104.0;
const _statusWidth = 150.0;

/// One copy of a title as a choice (screens 03d and 25): where it is, what
/// it would cost to play here, and — in 03d — how it compares. Each row
/// states the two things that decide it: how far away the server is, and
/// whether this television plays the file directly.
class SourceRow extends StatelessWidget {
  final Sourced<PlexLibraryItem> copy;

  /// Null while this copy's detail is still being read.
  final CopyFacts? facts;

  /// The row's second line after "Plex · <distance>": the file in 03d,
  /// "answered just now" in 25.
  final String? detail;
  final bool showAudio;
  final bool chosen;
  final (String, Color)? status;
  final bool autofocus;
  final FocusNode? focusNode;
  final VoidCallback onClick;

  const SourceRow({
    super.key,
    required this.copy,
    required this.facts,
    required this.onClick,
    this.detail,
    this.showAudio = true,
    this.chosen = false,
    this.status,
    this.autofocus = false,
    this.focusNode,
  });

  static String distance(ServerReachability r) => switch (r) {
    ServerReachability.local => 'local',
    ServerReachability.relayed => 'relayed',
    ServerReachability.unreachable => 'unreachable',
  };

  @override
  Widget build(BuildContext context) {
    final unreachable = copy.reachability == ServerReachability.unreachable;
    final facts = this.facts;
    final chips = <Widget>[
      if (facts?.picture case final picture?)
        _FactChip(picture, emphasis: chosen ? AppColors.accent : null),
      if (showAudio && facts?.audio != null) _FactChip(facts!.audio!),
      if (facts != null)
        facts.directPlay
            ? const _FactChip('Direct play')
            : _FactChip('Will transcode', emphasis: AppColors.warning),
    ];

    return Opacity(
      opacity: unreachable ? 0.45 : 1,
      child: AppCard(
        onClick: onClick,
        enabled: !unreachable,
        selected: chosen,
        autofocus: autofocus,
        focusNode: focusNode,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: _rowMinHeight.du(context)),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppSpacing.xl.du(context),
              vertical: AppSpacing.md.du(context),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppText(copy.server.name, style: AppTypography.label),
                      SizedBox(height: 4.du(context)),
                      AppText(
                        [
                          'Plex',
                          distance(copy.reachability),
                          ?detail,
                        ].join(' · '),
                        style: AppTypography.caption,
                        color: AppColors.ink3,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                for (final (i, chip) in chips.indexed) ...[
                  SizedBox(width: (i == 0 ? AppSpacing.xl : 10.0).du(context)),
                  chip,
                ],
                if (status case (final label, final color)?) ...[
                  SizedBox(width: AppSpacing.xl.du(context)),
                  SizedBox(
                    width: _statusWidth.du(context),
                    child: AppText(
                      label,
                      style: AppTypography.caption,
                      color: color,
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A plain outlined fact ("1080p", "Direct play"); [emphasis] outlines it
/// in a colour — the accent for the chosen copy's picture, the warning
/// colour for a transcode.
class _FactChip extends StatelessWidget {
  final String label;
  final Color? emphasis;

  const _FactChip(this.label, {this.emphasis});

  @override
  Widget build(BuildContext context) {
    final emphasis = this.emphasis;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: 11.du(context),
        vertical: 4.du(context),
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppShape.radiusSm.du(context)),
        border: Border.all(
          color: emphasis ?? AppColors.lineStrong,
          width: AppShape.borderWidth.du(context),
        ),
      ),
      child: AppText(
        label,
        style: AppTypography.micro.copyWith(
          letterSpacing: 0,
          fontWeight: FontWeight.w400,
        ),
        color: emphasis == AppColors.warning
            ? AppColors.warning
            : emphasis != null
            ? AppColors.ink
            : AppColors.ink2,
      ),
    );
  }
}
