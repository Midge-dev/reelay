import 'dart:math';

import 'package:flutter/widgets.dart';

import '../../kit/icon.dart';
import '../../kit/text.dart';
import '../../theme/phosphor_icons.dart';
import '../../theme/scale.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../common/reelay_mark.dart';

/// The four setup steps (screens O1-O5).
enum SetupStep {
  servers('Your servers'),
  link('Link your account'),
  watchTogether('Watch Together'),
  ready('Ready');

  final String label;
  const SetupStep(this.label);
}

const _columnWidth = 520.0;
const _stepRowHeight = 72.0;

/// The frame every setup screen shares: a 520 du step column on the left
/// (logo, "SETUP", the four steps — done ones checked with what was chosen,
/// the current one on a raised fill with the accent spine, the rest dim —
/// and a line of reassurance at the foot), and the step's own content on
/// the right from 120 du down.
class OnboardingFrame extends StatelessWidget {
  final SetupStep step;

  /// What each finished (or current) step settled on — "Plex", "Optional".
  final Map<SetupStep, String> summaries;
  final String footnote;
  final Widget child;

  /// The step's actions, pinned to the foot of the content when it fits,
  /// following it when a large UI size makes the page scroll.
  final Widget? footer;

  /// Top inset of the content column; O4 and O5 sit a little higher.
  final double contentTop;

  const OnboardingFrame({
    super.key,
    required this.step,
    this.summaries = const {},
    required this.footnote,
    required this.child,
    this.footer,
    this.contentTop = 120,
  });

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.background,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            // At most about a third of the screen, so a large UI size
            // doesn't leave the step content too narrow to hold its cards.
            width: min(
              _columnWidth.du(context),
              MediaQuery.sizeOf(context).width * 0.34,
            ),
            decoration: BoxDecoration(
              color: AppColors.canvas,
              border: Border(
                right: BorderSide(color: AppColors.line, width: 1.du(context)),
              ),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: AppSpacing.safeX.du(context),
                  vertical: 56.du(context),
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - (2 * 56).du(context),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              const ReelayMark(),
                              SizedBox(width: 14.du(context)),
                              AppText(
                                'Reelay',
                                style: AppTypography.rowLabel,
                                color: AppColors.ink,
                              ),
                            ],
                          ),
                          SizedBox(height: 44.du(context)),
                          AppText(
                            'SETUP',
                            style: AppTypography.micro,
                            color: AppColors.ink3,
                          ),
                          SizedBox(height: 44.du(context)),
                          for (final s in SetupStep.values) ...[
                            _StepRow(
                              step: s,
                              current: step,
                              summary: summaries[s],
                            ),
                            SizedBox(height: 6.du(context)),
                          ],
                        ],
                      ),
                      Padding(
                        padding: EdgeInsets.only(
                          top: AppSpacing.xxl.du(context),
                        ),
                        child: AppText(
                          footnote,
                          style: AppTypography.caption.copyWith(height: 1.6),
                          color: AppColors.ink4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                clipBehavior: Clip.none,
                // The handoff pads the column the same top and bottom; the
                // bottom used to be the 48 screen-edge minimum, which sat
                // O4's "Skipping is fine" bar right on the screen's edge.
                padding: EdgeInsets.fromLTRB(
                  96.du(context),
                  contentTop.du(context),
                  96.du(context),
                  contentTop.du(context),
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight:
                        constraints.maxHeight - (contentTop * 2).du(context),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Focus moving back up into the step shows as much of
                      // its top (the heading) as fits with the focused item
                      // still on screen — the default only scrolled to the
                      // focused button, leaving the heading off the top.
                      Builder(
                        builder: (context) => Focus(
                          canRequestFocus: false,
                          skipTraversal: true,
                          onFocusChange: (focused) {
                            if (!focused) return;
                            WidgetsBinding.instance.addPostFrameCallback(
                              (_) => _revealTop(context),
                            );
                          },
                          child: child,
                        ),
                      ),
                      if (footer != null)
                        Padding(
                          padding: EdgeInsets.only(
                            top: AppSpacing.xxl.du(context),
                          ),
                          // Focus inside the footer (O4's Not now) shows the
                          // whole bar and the margin under it — the focused
                          // button's own ensureVisible stopped at the button,
                          // leaving the bar cut by the screen's edge.
                          child: Builder(
                            builder: (context) => Focus(
                              canRequestFocus: false,
                              skipTraversal: true,
                              onFocusChange: (focused) {
                                if (!focused) return;
                                WidgetsBinding.instance.addPostFrameCallback((
                                  _,
                                ) {
                                  if (!context.mounted) return;
                                  final position = Scrollable.of(context)
                                      .position;
                                  position.animateTo(
                                    position.maxScrollExtent,
                                    duration: AppMotion.rowScroll,
                                    curve: AppMotion.enter,
                                  );
                                });
                              },
                              child: footer!,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final SetupStep step;
  final SetupStep current;
  final String? summary;

  const _StepRow({required this.step, required this.current, this.summary});

  @override
  Widget build(BuildContext context) {
    final isCurrent = step == current;
    final isDone = step.index < current.index;
    final spine = isCurrent
        ? AppColors.accent
        : (isDone ? AppColors.ink : AppColors.transparent);
    // The spine is its own strip, not a one-sided border — Flutter can't
    // round a box whose border differs per side.
    return ClipRRect(
      borderRadius: BorderRadius.horizontal(
        right: Radius.circular(AppShape.radiusMd.du(context)),
      ),
      child: Container(
        constraints: BoxConstraints(minHeight: _stepRowHeight.du(context)),
        color: isCurrent ? AppColors.surfaceRaised : null,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: AppShape.spineWidth.du(context), color: spine),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 22.du(context)),
                  child: _content(
                    context,
                    isCurrent: isCurrent,
                    isDone: isDone,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _content(
    BuildContext context, {
    required bool isCurrent,
    required bool isDone,
  }) {
    return Row(
      children: [
        if (isDone)
          AppIcon(
            PhosphorIconsFill.checkCircle,
            size: 22,
            tint: AppColors.success,
          )
        else
          AppText(
            '${step.index + 1}',
            style: AppTypography.caption,
            color: isCurrent ? AppColors.accent300 : AppColors.ink4,
          ),
        SizedBox(width: AppSpacing.lg.du(context)),
        Expanded(
          child: AppText(
            step.label,
            style: AppTypography.body.copyWith(
              height: 1.3,
              fontWeight: isCurrent ? FontWeight.w500 : FontWeight.w400,
            ),
            color: isCurrent
                ? AppColors.ink
                : (isDone ? AppColors.ink2 : AppColors.ink4),
          ),
        ),
        if (summary != null && (isDone || isCurrent))
          AppText(
            summary!,
            style: AppTypography.caption,
            color: isCurrent ? AppColors.ink2 : AppColors.ink3,
          ),
      ],
    );
  }
}

/// "STEP 2 OF 4 · PLEX", the 52 du headline and the body line every setup
/// step opens with.
class StepHeading extends StatelessWidget {
  final String kicker;
  final String title;
  final String? body;
  final double bodyMaxWidth;

  const StepHeading({
    super.key,
    required this.kicker,
    required this.title,
    this.body,
    this.bodyMaxWidth = 700,
  });

  @override
  Widget build(BuildContext context) {
    final gap = SizedBox(height: 20.du(context));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        AppText(kicker, style: AppTypography.micro),
        gap,
        AppText(title, style: AppTypography.display, color: AppColors.ink),
        if (body != null) ...[
          gap,
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: bodyMaxWidth.du(context)),
            child: AppText(body!, style: AppTypography.body),
          ),
        ],
      ],
    );
  }
}

/// Scrolls the step's column as far up as it can go while the focused item
/// stays fully on screen.
void _revealTop(BuildContext context) {
  if (!context.mounted) return;
  final scrollable = Scrollable.maybeOf(context);
  final focused = FocusManager.instance.primaryFocus?.context
      ?.findRenderObject();
  final viewport = scrollable?.context.findRenderObject();
  if (scrollable == null || focused is! RenderBox || viewport is! RenderBox) {
    return;
  }
  final position = scrollable.position;
  final bottomInViewport = focused
      .localToGlobal(Offset(0, focused.size.height), ancestor: viewport)
      .dy;
  final bottomInContent = position.pixels + bottomInViewport;
  final target = (bottomInContent - position.viewportDimension + 24.du(context))
      .clamp(0.0, position.maxScrollExtent);
  if ((target - position.pixels).abs() < 1) return;
  position.animateTo(
    target,
    duration: AppMotion.rowScroll,
    curve: AppMotion.enter,
  );
}
