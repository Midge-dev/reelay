import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../data/plex/plex_models.dart';
import '../../kit/button.dart';
import '../../kit/icon.dart';
import '../../kit/text.dart';
import '../../state/copy_facts.dart';
import '../../state/duplicate_fold.dart';
import '../../theme/phosphor_icons.dart';
import '../../theme/scale.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../library/source_row.dart';
import 'time_format.dart';

/// Screen 25 — "COULDN'T START". The reason in one plain sentence (no
/// codes, never "unknown error"). Because duplicates are folded, the way
/// out is usually an offer: when another copy is reachable ([alternate]),
/// the dialog says what that copy is and that you'd carry on where you
/// were, and playing it is the first thing focused; retrying the failed
/// server and the full source list (03d) come after. With no alternate,
/// retrying is primary. Drawn over the detail page, which stays inert
/// underneath (AppRoot).
class PlaybackFailedScreen extends StatefulWidget {
  final String reason;
  final String serverName;
  final VoidCallback onRetry;
  final VoidCallback onBack;

  /// The title, for "The Quiet Coast is on two other servers".
  final String? title;

  /// How many other servers hold the title (alternate included).
  final int otherCopies;
  final Sourced<PlexLibraryItem>? alternate;
  final Future<CopyFacts> Function(Sourced<PlexLibraryItem> copy)? loadFacts;
  final int? resumeAtMs;
  final VoidCallback? onPlayAlternate;
  final VoidCallback? onAllSources;

  const PlaybackFailedScreen({
    super.key,
    required this.reason,
    required this.serverName,
    required this.onRetry,
    required this.onBack,
    this.title,
    this.otherCopies = 0,
    this.alternate,
    this.loadFacts,
    this.resumeAtMs,
    this.onPlayAlternate,
    this.onAllSources,
  });

  @override
  State<PlaybackFailedScreen> createState() => _PlaybackFailedScreenState();
}

class _PlaybackFailedScreenState extends State<PlaybackFailedScreen> {
  final _primaryFocus = FocusNode(debugLabel: 'playback-failed-primary');
  CopyFacts? _facts;
  bool _alternateSilent = false;

  bool get _hasAlternate =>
      widget.alternate != null && widget.onPlayAlternate != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _primaryFocus.requestFocus(),
    );
    final alternate = widget.alternate;
    final load = widget.loadFacts;
    if (alternate != null && load != null) {
      unawaited(
        load(alternate)
            .then((f) {
              if (mounted) setState(() => _facts = f);
            })
            .catchError((_) {
              if (mounted) setState(() => _alternateSilent = true);
            }),
      );
    }
  }

  @override
  void dispose() {
    _primaryFocus.dispose();
    super.dispose();
  }

  /// "The Quiet Coast is on two other servers. Loft has a 1080p copy this
  /// television can play directly, and you would carry on from 46:12."
  String _offer(String alternateName) {
    final facts = _facts;
    final at = [
      widget.resumeAtMs ?? 0,
      facts?.viewOffsetMs ?? 0,
    ].reduce((a, b) => a > b ? a : b);
    final others = widget.otherCopies;
    final where = widget.title == null || others < 1
        ? null
        : '${widget.title} is on ${countWord(others)} other '
              'server${others == 1 ? '' : 's'}.';
    final copy = facts == null
        ? 'There is a copy on $alternateName'
        : '$alternateName has ${facts.picture == null ? 'a copy' : 'a ${facts.picture} copy'}'
              '${facts.directPlay ? ' this television can play directly' : ' the server would convert for this television'}';
    final carryOn = at > 0
        ? ', and you would carry on from ${formatTimecode(at)}.'
        : '.';
    return [?where, '$copy$carryOn'].join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final alternate = widget.alternate;
    return ColoredBox(
      color: AppScrims.dialog,
      child: Center(
        child: Container(
          width: 900.du(context),
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
                  const AppIcon(
                    PhosphorIconsRegular.warning,
                    size: 28,
                    tint: AppColors.warning,
                  ),
                  SizedBox(width: AppSpacing.md.du(context)),
                  AppText(
                    "COULDN'T START",
                    style: AppTypography.micro,
                    color: AppColors.warning,
                  ),
                ],
              ),
              SizedBox(height: AppSpacing.xl.du(context)),
              AppText(widget.reason, style: AppTypography.title2),
              if (_hasAlternate && alternate != null) ...[
                SizedBox(height: AppSpacing.xl.du(context)),
                AppText(
                  _offer(alternate.server.name),
                  style: AppTypography.body,
                  color: AppColors.ink2,
                ),
                SizedBox(height: AppSpacing.xl.du(context)),
                SourceRow(
                  copy: alternate,
                  facts: _facts,
                  detail: _facts != null
                      ? 'answered just now'
                      : _alternateSilent
                      ? 'not answering either'
                      : null,
                  showAudio: false,
                  onClick: widget.onPlayAlternate!,
                  focusNode: _primaryFocus,
                ),
              ],
              SizedBox(height: AppSpacing.xxl.du(context)),
              Wrap(
                // Wrap, not Row — three buttons can exceed this dialog's
                // width at some scale factors.
                spacing: AppSpacing.md.du(context),
                runSpacing: AppSpacing.md.du(context),
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (_hasAlternate && alternate != null) ...[
                    AppButton(
                      onClick: widget.onPlayAlternate!,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const AppIcon(PhosphorIconsFill.play, size: 22),
                          SizedBox(width: AppSpacing.md.du(context)),
                          AppText('Play from ${alternate.server.name}'),
                        ],
                      ),
                    ),
                    AppOutlinedButton(
                      onClick: widget.onRetry,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const AppIcon(
                            PhosphorIconsRegular.arrowClockwise,
                            size: 22,
                          ),
                          SizedBox(width: AppSpacing.md.du(context)),
                          AppText('Try ${widget.serverName} again'),
                        ],
                      ),
                    ),
                    if (widget.onAllSources case final onAllSources?)
                      AppOutlinedButton(
                        onClick: onAllSources,
                        child: const AppText('All sources'),
                      ),
                  ] else ...[
                    AppButton(
                      onClick: widget.onRetry,
                      focusNode: _primaryFocus,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const AppIcon(
                            PhosphorIconsRegular.arrowClockwise,
                            size: 22,
                          ),
                          SizedBox(width: AppSpacing.sm.du(context)),
                          AppText('Try ${widget.serverName} again'),
                        ],
                      ),
                    ),
                    AppOutlinedButton(
                      onClick: widget.onBack,
                      child: const AppText('Back'),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
