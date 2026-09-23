import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../data/plex/plex_models.dart';
import '../../data/plex/plex_resources_api.dart' show ServerReachability;
import '../../focus/back_handler.dart';
import '../../kit/button.dart';
import '../../kit/icon.dart';
import '../../kit/text.dart';
import '../../state/copy_facts.dart';
import '../../state/duplicate_fold.dart';
import '../../theme/phosphor_icons.dart';
import '../../theme/scale.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../common/time_format.dart';
import 'source_row.dart';

const _dialogWidth = 1020.0;

/// Screen 03d — "Where to watch from". One title, several files. Reelay has
/// already chosen; this panel says what it chose and lets you disagree.
/// Each row states the two things that decide it — how far away the server
/// is, and what the file will cost to play — and your place belongs to the
/// title, not to any one copy, so switching source never loses it.
///
/// Duplicates fold into one card everywhere except here (DESIGN.md
/// non-negotiable #10). Rows come in fold priority order.
class SourcePickerDialog extends StatefulWidget {
  final String title;
  final FoldedWork<PlexLibraryItem> work;
  final Sourced<PlexLibraryItem> activeCopy;
  final Future<CopyFacts> Function(Sourced<PlexLibraryItem> copy) loadFacts;

  /// How far in you are on the title (0 = not started).
  final int resumeAtMs;
  final ValueChanged<Sourced<PlexLibraryItem>> onSelect;
  final VoidCallback onPlay;
  final VoidCallback onClose;

  const SourcePickerDialog({
    super.key,
    required this.title,
    required this.work,
    required this.activeCopy,
    required this.loadFacts,
    required this.resumeAtMs,
    required this.onSelect,
    required this.onPlay,
    required this.onClose,
  });

  @override
  State<SourcePickerDialog> createState() => _SourcePickerDialogState();
}

class _SourcePickerDialogState extends State<SourcePickerDialog> {
  final _facts = <String, CopyFacts>{};
  final _silent = <String>{};
  final _chosenFocus = FocusNode(debugLabel: 'source-picker-chosen');

  static String _id(Sourced<PlexLibraryItem> c) => c.server.machineIdentifier;

  @override
  void dispose() {
    _chosenFocus.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // The chosen row takes focus from whatever the page had.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _chosenFocus.requestFocus();
    });
    for (final copy in widget.work.copies) {
      if (copy.reachability == ServerReachability.unreachable) continue;
      unawaited(
        widget
            .loadFacts(copy)
            .then((f) {
              if (mounted) setState(() => _facts[_id(copy)] = f);
            })
            .catchError((_) {
              if (mounted) setState(() => _silent.add(_id(copy)));
            }),
      );
    }
  }

  bool _isChosen(Sourced<PlexLibraryItem> c) =>
      _id(c) == _id(widget.activeCopy);

  (String, Color) _status(Sourced<PlexLibraryItem> copy) {
    if (_isChosen(copy)) return ('Chosen', AppColors.success);
    final chosenRank = _facts[_id(widget.activeCopy)]?.pictureRank ?? 0;
    final rank = _facts[_id(copy)]?.pictureRank ?? 0;
    return switch (copy.reachability) {
      ServerReachability.unreachable => ('Unreachable', AppColors.error),
      ServerReachability.relayed => ('Relayed', AppColors.warning),
      ServerReachability.local when rank > 0 && rank < chosenRank => (
        'Lower quality',
        AppColors.ink3,
      ),
      ServerReachability.local => ('Local', AppColors.success),
    };
  }

  @override
  Widget build(BuildContext context) {
    final copies = widget.work.copies;
    // The furthest any copy has you, as well as the page's own.
    final resumeAt = _facts.values.fold(
      widget.resumeAtMs,
      (at, f) => f.viewOffsetMs > at ? f.viewOffsetMs : at,
    );
    return Positioned.fill(
      child: ColoredBox(
        color: AppScrims.dialog,
        child: Center(
          child: BackHandler(
            onBack: widget.onClose,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: _dialogWidth.du(context),
                maxHeight: MediaQuery.sizeOf(context).height * 0.9,
              ),
              child: Container(
                padding: EdgeInsets.all(AppSpacing.xxxl.du(context)),
                decoration: BoxDecoration(
                  color: AppColors.surfaceOverlay,
                  borderRadius: BorderRadius.circular(
                    AppShape.radiusLg.du(context),
                  ),
                  border: Border.all(color: AppColors.lineStrong),
                  boxShadow: AppElevation.overlay,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AppIcon(
                            PhosphorIconsRegular.hardDrives,
                            size: 28,
                            tint: AppColors.accent300,
                          ),
                          SizedBox(width: AppSpacing.md.du(context)),
                          AppText(
                            'WHERE TO WATCH FROM',
                            style: AppTypography.micro,
                            color: AppColors.accent300,
                          ),
                        ],
                      ),
                      SizedBox(height: AppSpacing.xl.du(context)),
                      AppText(
                        '${widget.title} is on ${countWord(copies.length)} of your servers',
                        style: AppTypography.title2,
                      ),
                      SizedBox(height: AppSpacing.xl.du(context)),
                      for (final (index, copy) in copies.indexed) ...[
                        if (index > 0)
                          SizedBox(height: AppSpacing.md.du(context)),
                        SourceRow(
                          copy: copy,
                          facts: _facts[_id(copy)],
                          detail: _silent.contains(_id(copy))
                              ? 'not answering'
                              : _facts[_id(copy)]?.file,
                          chosen: _isChosen(copy),
                          status: _status(copy),
                          focusNode: _isChosen(copy) ? _chosenFocus : null,
                          onClick: () {
                            if (!_isChosen(copy)) widget.onSelect(copy);
                            widget.onClose();
                          },
                        ),
                      ],
                      if (resumeAt > 0) ...[
                        SizedBox(height: AppSpacing.xl.du(context)),
                        _ResumeNote(resumeAtMs: resumeAt),
                      ],
                      SizedBox(height: AppSpacing.xl.du(context)),
                      Row(
                        children: [
                          AppButton(
                            onClick: widget.onPlay,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const AppIcon(PhosphorIconsFill.play, size: 22),
                                SizedBox(width: AppSpacing.md.du(context)),
                                AppText(
                                  'Play from ${widget.activeCopy.server.name}',
                                ),
                              ],
                            ),
                          ),
                          SizedBox(width: AppSpacing.xl.du(context)),
                          Expanded(
                            child: AppText(
                              'Back closes and keeps the chosen source',
                              style: AppTypography.caption,
                              color: AppColors.ink4,
                              textAlign: TextAlign.right,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "You are 46:12 in. That is kept against the title, so any source you
/// pick resumes there."
class _ResumeNote extends StatelessWidget {
  final int resumeAtMs;

  const _ResumeNote({required this.resumeAtMs});

  @override
  Widget build(BuildContext context) {
    // A rounded box can't take a one-sided border, so the spine is its own
    // strip inside the clip.
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppShape.radiusSm.du(context)),
      child: ColoredBox(
        color: AppColors.surfaceRaised,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ColoredBox(
                color: AppColors.success,
                child: SizedBox(width: 4.du(context)),
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: 20.du(context),
                    vertical: AppSpacing.lg.du(context),
                  ),
                  child: Row(
                    children: [
                      AppIcon(
                        PhosphorIconsRegular.clockCounterClockwise,
                        size: 22,
                        tint: AppColors.success,
                      ),
                      SizedBox(width: 14.du(context)),
                      Expanded(
                        child: AppText(
                          'You are ${formatTimecode(resumeAtMs)} in. That is '
                          'kept against the title, so any source you pick '
                          'resumes there.',
                          style: AppTypography.caption,
                          color: AppColors.ink2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
