import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../data/settings/app_settings.dart';
import '../../focus/back_handler.dart';
import '../../kit/soft_edge_shadow.dart';
import '../../kit/focusable_surface.dart';
import '../../kit/icon.dart';
import '../../kit/surface_style.dart';
import '../../kit/text.dart';
import '../../playback/playback_decision.dart';
import '../../theme/phosphor_icons.dart';
import '../../theme/scale.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';

enum _MenuTab { subtitles, quality }

/// Screen 14 — a right-hand panel, not a centered dialog, so the picture
/// stays visible while choosing (the handoff's own reasoning: "matters
/// when you are choosing a track by ear"). Subtitles and Quality are real,
/// backed by the same SubtitleOption/BitratePreset data the existing
/// cycle-buttons already used — this panel is a second way to reach the
/// same state, not a new mechanism. No Audio tab: this app doesn't have
/// separate audio-track switching at all yet (decidePlayback doesn't
/// model it), so a tab with nothing behind it would be worse than no tab.
class PlayerMenuPanel extends StatefulWidget {
  final List<SubtitleOption> subtitleOptions;
  final int? selectedSubtitleStreamId;
  final ValueChanged<int?> onSelectSubtitle;
  final int selectedBitrateKbps;
  final ValueChanged<int> onSelectBitrate;
  final VoidCallback onClose;

  const PlayerMenuPanel({
    super.key,
    required this.subtitleOptions,
    required this.selectedSubtitleStreamId,
    required this.onSelectSubtitle,
    required this.selectedBitrateKbps,
    required this.onSelectBitrate,
    required this.onClose,
  });

  @override
  State<PlayerMenuPanel> createState() => _PlayerMenuPanelState();
}

class _PlayerMenuPanelState extends State<PlayerMenuPanel> {
  _MenuTab _tab = _MenuTab.subtitles;
  final _subtitlesTabFocus = FocusNode(debugLabel: 'player-menu-tab-subtitles');
  final _qualityTabFocus = FocusNode(debugLabel: 'player-menu-tab-quality');
  final _firstRowFocus = FocusNode(debugLabel: 'player-menu-first-row');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _subtitlesTabFocus.requestFocus(),
    );
  }

  @override
  void dispose() {
    _subtitlesTabFocus.dispose();
    _qualityTabFocus.dispose();
    _firstRowFocus.dispose();
    super.dispose();
  }

  KeyEventResult _trapUpAboveTabs(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.arrowUp) {
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: BackHandler(
        onBack: widget.onClose,
        child: Stack(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onClose,
              child: const ColoredBox(color: AppColors.transparent),
            ),
            Positioned(
              top: 0,
              bottom: 0,
              right: 360.du(context),
              child: const SoftEdgeShadow(toward: AxisDirection.left),
            ),
            Positioned(
              top: 0,
              bottom: 0,
              right: 0,
              // Half the handoff's 680: the tracks are short labels, and a
              // narrower panel leaves more of the picture in view.
              width: 360.du(context),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.canvas,
                  border: Border(left: BorderSide(color: AppColors.line)),
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: AppSpacing.xxl.du(context),
                    vertical: AppSpacing.xxxl.du(context),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Focus(
                        canRequestFocus: false,
                        onKeyEvent: _trapUpAboveTabs,
                        child: Row(
                          children: [
                            Expanded(
                              child: _TabButton(
                                label: 'Subtitles',
                                selected: _tab == _MenuTab.subtitles,
                                focusNode: _subtitlesTabFocus,
                                onClick: () =>
                                    setState(() => _tab = _MenuTab.subtitles),
                              ),
                            ),
                            SizedBox(width: AppSpacing.md.du(context)),
                            Expanded(
                              child: _TabButton(
                                label: 'Quality',
                                selected: _tab == _MenuTab.quality,
                                focusNode: _qualityTabFocus,
                                onClick: () =>
                                    setState(() => _tab = _MenuTab.quality),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: AppSpacing.xl.du(context)),
                      Expanded(
                        child: switch (_tab) {
                          _MenuTab.subtitles => _buildSubtitlesList(),
                          _MenuTab.quality => _buildQualityList(),
                        },
                      ),
                      AppText(
                        'Back closes this panel and leaves playback untouched.',
                        style: AppTypography.caption,
                        color: AppColors.ink3,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubtitlesList() {
    return ListView(
      children: [
        for (final (index, option) in widget.subtitleOptions.indexed) ...[
          _MenuRow(
            label: option.label,
            selected: option.streamId == widget.selectedSubtitleStreamId,
            focusNode: index == 0 ? _firstRowFocus : null,
            onClick: () => widget.onSelectSubtitle(option.streamId),
          ),
          SizedBox(height: AppSpacing.sm.du(context)),
        ],
      ],
    );
  }

  Widget _buildQualityList() {
    return ListView(
      children: [
        for (final preset in AppSettings.bitratePresets) ...[
          _MenuRow(
            label: preset.label,
            selected: preset.kbps == widget.selectedBitrateKbps,
            onClick: () => widget.onSelectBitrate(preset.kbps),
          ),
          SizedBox(height: AppSpacing.sm.du(context)),
        ],
      ],
    );
  }
}

RoundedRectangleBorder _tabShape(BuildContext context) =>
    RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppShape.radiusSm.du(context)),
    );
SurfaceColors get _tabColors => SurfaceColors(
  container: AppColors.surface,
  content: AppColors.ink3,
  focusedContainer: AppColors.surfaceRaised,
  focusedContent: AppColors.ink,
  selectedContainer: AppColors.surfaceRaised,
  selectedContent: AppColors.ink,
);
SurfaceBorder get _tabBorder =>
    SurfaceBorder(focused: SurfaceBorderSide.solid(AppColors.accent));

class _TabButton extends StatelessWidget {
  final String label;
  final bool selected;
  final FocusNode focusNode;
  final VoidCallback onClick;

  const _TabButton({
    required this.label,
    required this.selected,
    required this.focusNode,
    required this.onClick,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52.du(context),
      child: FocusableSurface(
        onClick: onClick,
        selected: selected,
        focusNode: focusNode,
        shape: _tabShape(context),
        colors: _tabColors,
        border: _tabBorder,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg.du(context)),
          child: FittedBox(fit: BoxFit.scaleDown, child: AppText(label)),
        ),
      ),
    );
  }
}

RoundedRectangleBorder _rowShape(BuildContext context) =>
    RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppShape.radiusMd.du(context)),
    );
SurfaceColors get _rowColors => SurfaceColors(
  container: AppColors.surface,
  content: AppColors.ink2,
  focusedContainer: AppColors.surfaceRaised,
  focusedContent: AppColors.ink,
  selectedContainer: AppColors.surfaceRaised,
  selectedContent: AppColors.ink,
);
SurfaceBorder get _rowBorder =>
    SurfaceBorder(focused: SurfaceBorderSide.solid(AppColors.accent));

class _MenuRow extends StatelessWidget {
  final String label;
  final bool selected;
  final FocusNode? focusNode;
  final VoidCallback onClick;

  const _MenuRow({
    required this.label,
    required this.selected,
    this.focusNode,
    required this.onClick,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: 88.du(context)),
      child: FocusableSurface(
        onClick: onClick,
        selected: selected,
        focusNode: focusNode,
        shape: _rowShape(context),
        colors: _rowColors,
        border: _rowBorder,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.xl.du(context)),
          child: Row(
            children: [
              Expanded(child: AppText(label, style: AppTypography.label)),
              if (selected)
                const AppIcon(PhosphorIconsFill.checkCircle, size: 24),
            ],
          ),
        ),
      ),
    );
  }
}
