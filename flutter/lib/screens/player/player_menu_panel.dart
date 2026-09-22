import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../data/settings/app_settings.dart';
import '../../focus/back_handler.dart';
import '../../kit/focusable_surface.dart';
import '../../kit/icon.dart';
import '../../kit/surface_style.dart';
import '../../kit/text.dart';
import '../../playback/playback_decision.dart';
import '../../theme/phosphor_icons.dart';
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
              right: 0,
              width: 680,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.canvas,
                  border: Border(left: BorderSide(color: AppColors.line)),
                  boxShadow: AppElevation.overlay,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xxxl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Focus(
                        canRequestFocus: false,
                        onKeyEvent: _trapUpAboveTabs,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _TabButton(
                              label: 'Subtitles',
                              selected: _tab == _MenuTab.subtitles,
                              focusNode: _subtitlesTabFocus,
                              onClick: () =>
                                  setState(() => _tab = _MenuTab.subtitles),
                            ),
                            const SizedBox(width: AppSpacing.md),
                            _TabButton(
                              label: 'Quality',
                              selected: _tab == _MenuTab.quality,
                              focusNode: _qualityTabFocus,
                              onClick: () =>
                                  setState(() => _tab = _MenuTab.quality),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
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
          const SizedBox(height: AppSpacing.sm),
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
          const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }
}

final _tabShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.circular(AppShape.radiusSm),
);
final _tabColors = SurfaceColors(
  container: AppColors.surface,
  content: AppColors.ink3,
  focusedContainer: AppColors.surfaceRaised,
  focusedContent: AppColors.ink,
  selectedContainer: AppColors.surfaceRaised,
  selectedContent: AppColors.ink,
);
final _tabBorder = SurfaceBorder(
  focused: SurfaceBorderSide.solid(AppColors.accent),
);

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
      height: 52,
      child: FocusableSurface(
        onClick: onClick,
        selected: selected,
        focusNode: focusNode,
        shape: _tabShape,
        colors: _tabColors,
        border: _tabBorder,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: AppText(label),
        ),
      ),
    );
  }
}

final _rowShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.circular(AppShape.radiusMd),
);
final _rowColors = SurfaceColors(
  container: AppColors.surface,
  content: AppColors.ink2,
  focusedContainer: AppColors.surfaceRaised,
  focusedContent: AppColors.ink,
  selectedContainer: AppColors.surfaceRaised,
  selectedContent: AppColors.ink,
);
final _rowBorder = SurfaceBorder(
  focused: SurfaceBorderSide.solid(AppColors.accent),
);

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
      constraints: const BoxConstraints(minHeight: 88),
      child: FocusableSurface(
        onClick: onClick,
        selected: selected,
        focusNode: focusNode,
        shape: _rowShape,
        colors: _rowColors,
        border: _rowBorder,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
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
