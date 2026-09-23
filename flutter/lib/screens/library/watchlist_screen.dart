import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../data/plex/plex_models.dart';
import '../../focus/back_handler.dart';
import '../../kit/focusable_surface.dart';
import '../../kit/surface_style.dart';
import '../../kit/icon.dart';
import '../../kit/text.dart';
import '../../theme/phosphor_icons.dart';
import '../../theme/scale.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import 'poster_card.dart';

const _undoSeconds = 8;
// Screens 20/21: 20 du between header, action bar and grid; the action
// bar's controls are 58 tall.
const _blockGap = 20.0;
const _barHeight = 58.0;

enum _WatchlistSort {
  recentlyAdded('Recently added'),
  title('Title');

  final String label;
  const _WatchlistSort(this.label);
}

/// Screen 20/21 — the one list the viewer builds by hand and comes back
/// to prune, per its own explainer note. Spans every library at once (no
/// per-section scoping, no filter row — it belongs to the account, not a
/// server), and can hold titles this server doesn't have; without cross-
/// server duplicate folding (README: "the largest single piece of work in
/// this package", not built) this pass can't show the "Not on your
/// servers" badge up front, so resolution happens on select instead,
/// reusing the same guid lookup Home's watchlist row already did.
///
/// Hold to remove — DESIGN.md's destructive-but-reversible rule: acts
/// immediately (no confirm dialog), collapses the card, and puts an
/// 8-second undo chip in the header (screen 21). Letting it deplete
/// commits the removal; pressing it restores the card as if nothing
/// happened.
class WatchlistScreen extends StatefulWidget {
  final List<PlexWatchlistItem> items;
  final ValueChanged<PlexWatchlistItem> onSelectItem;
  final ValueChanged<PlexWatchlistItem> onRemove;

  /// The Plex account the list belongs to — "Plex account · name".
  final String? accountName;

  const WatchlistScreen({
    super.key,
    required this.items,
    required this.onSelectItem,
    required this.onRemove,
    this.accountName,
  });

  @override
  State<WatchlistScreen> createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends State<WatchlistScreen> {
  late List<PlexWatchlistItem> _items = widget.items;
  PlexWatchlistItem? _pendingRemoval;
  int _secondsLeft = _undoSeconds;
  Timer? _timer;
  final _scrollController = ScrollController();
  final _undoFocus = FocusNode(debugLabel: 'watchlist-undo');
  _WatchlistSort _sort = _WatchlistSort.recentlyAdded;

  List<PlexWatchlistItem> get _sorted => switch (_sort) {
    // Newest first by addedAt when every entry has one; otherwise the
    // account list's own order, which arrives oldest-first.
    _WatchlistSort.recentlyAdded =>
      _items.every((i) => i.addedAt != null)
          ? ([..._items]..sort((a, b) => b.addedAt!.compareTo(a.addedAt!)))
          : _items.reversed.toList(),
    _WatchlistSort.title => [
      ..._items,
    ]..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase())),
  };

  @override
  void didUpdateWidget(covariant WatchlistScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.items != oldWidget.items && _pendingRemoval == null) {
      setState(() => _items = widget.items);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scrollController.dispose();
    _undoFocus.dispose();
    super.dispose();
  }

  void _startRemoval(PlexWatchlistItem entry) {
    _timer?.cancel();
    // A hold on a second card while one removal is already pending commits
    // the first immediately — the undo chip only ever tracks one entry at
    // a time, matching the mockup (one chip in the header, not a stack).
    if (_pendingRemoval != null) widget.onRemove(_pendingRemoval!);
    setState(() {
      _items = _items.where((i) => i.ratingKey != entry.ratingKey).toList();
      _pendingRemoval = entry;
      _secondsLeft = _undoSeconds;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _undoFocus.requestFocus();
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_secondsLeft <= 1) {
        timer.cancel();
        final entry = _pendingRemoval;
        if (entry != null) widget.onRemove(entry);
        setState(() => _pendingRemoval = null);
        return;
      }
      setState(() => _secondsLeft -= 1);
    });
  }

  void _undoRemoval() {
    final entry = _pendingRemoval;
    if (entry == null) return;
    _timer?.cancel();
    setState(() {
      _items = [entry, ..._items];
      _pendingRemoval = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final items = _sorted;
    final count = '${_items.length} title${_items.length == 1 ? '' : 's'}';
    return ColoredBox(
      color: AppColors.background,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.safeX.du(context),
          AppSpacing.safeY.du(context),
          AppSpacing.safeX.du(context),
          0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                AppText('Watchlist', style: AppTypography.title1),
                SizedBox(width: 18.du(context)),
                AppText(
                  widget.accountName != null
                      ? 'Plex account · ${widget.accountName}'
                      : 'Plex account',
                  style: AppTypography.caption,
                ),
                const Spacer(),
                AppText(count, style: AppTypography.caption),
              ],
            ),
            SizedBox(height: _blockGap.du(context)),
            SizedBox(
              height: _barHeight.du(context),
              child: Row(
                children: [
                  _SortChip(
                    label: 'Sort · ${_sort.label}',
                    onClick: () => setState(
                      () => _sort =
                          _WatchlistSort.values[(_sort.index + 1) %
                              _WatchlistSort.values.length],
                    ),
                  ),
                  const Spacer(),
                  if (_pendingRemoval != null)
                    _UndoChip(
                      title: _pendingRemoval!.title,
                      secondsLeft: _secondsLeft,
                      focusNode: _undoFocus,
                      onUndo: _undoRemoval,
                    )
                  else if (_items.isNotEmpty)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AppIcon(
                          PhosphorIconsRegular.dotOutline,
                          size: 22,
                          tint: AppColors.ink4,
                        ),
                        SizedBox(width: AppSpacing.md.du(context)),
                        AppText(
                          'Hold Select on a title to take it off the list',
                          style: AppTypography.caption,
                        ),
                      ],
                    ),
                ],
              ),
            ),
            SizedBox(
              height: (_blockGap - AppSpacing.rowHeadroom / 2).du(context),
            ),
            Expanded(
              child: items.isEmpty ? _buildEmptyState() : _buildGrid(items),
            ),
          ],
        ),
      ),
    );
  }

  /// Empty screen: one icon, one sentence of fact, one of instruction.
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(
            PhosphorIconsRegular.bookmarkSimple,
            size: 64,
            tint: AppColors.lineStrong,
          ),
          SizedBox(height: AppSpacing.xl.du(context)),
          // Verbatim from the handoff's copy list.
          AppText(
            'Nothing saved yet — press + on anything to keep it here.',
            style: AppTypography.body,
          ),
        ],
      ),
    );
  }

  Widget _buildGrid(List<PlexWatchlistItem> items) {
    return PosterGrid(
      controller: _scrollController,
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return PosterCard(
          key: ValueKey(item.ratingKey),
          imageUrl: (item.thumb?.startsWith('http') ?? false)
              ? item.thumb
              : null,
          title: item.title,
          subtitle: item.year?.toString(),
          autofocus: index == 0 && _pendingRemoval == null,
          onClick: () => widget.onSelectItem(item),
          onLongClick: () => _startRemoval(item),
        );
      },
    );
  }
}

RoundedRectangleBorder _chipShape(BuildContext context) =>
    RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppShape.radiusSm.du(context)),
    );
SurfaceColors get _chipColors => SurfaceColors(
  container: AppColors.transparent,
  content: AppColors.ink2,
  focusedContainer: AppColors.surfaceRaised,
  focusedContent: AppColors.ink,
);
SurfaceBorder get _chipBorder => SurfaceBorder(
  idle: SurfaceBorderSide.solid(AppColors.line),
  focused: SurfaceBorderSide.solid(AppColors.accent),
);

class _SortChip extends StatelessWidget {
  final String label;
  final VoidCallback onClick;

  const _SortChip({required this.label, required this.onClick});

  @override
  Widget build(BuildContext context) {
    return FocusableSurface(
      onClick: onClick,
      shape: _chipShape(context),
      colors: _chipColors,
      border: _chipBorder,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 20.du(context)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppText(label, style: AppTypography.caption, color: null),
            SizedBox(width: AppSpacing.md.du(context)),
            AppIcon(
              PhosphorIconsRegular.caretDown,
              size: 18,
              tint: AppColors.ink4,
            ),
          ],
        ),
      ),
    );
  }
}

/// Screen 21: the chip that takes the hint's place for eight seconds and
/// holds focus — "Took X off the list" and an Undo action, with a 3 du
/// rule underneath depleting to zero. Back triggers it while it lives.
class _UndoChip extends StatelessWidget {
  final String title;
  final int secondsLeft;
  final FocusNode focusNode;
  final VoidCallback onUndo;

  const _UndoChip({
    required this.title,
    required this.secondsLeft,
    required this.focusNode,
    required this.onUndo,
  });

  @override
  Widget build(BuildContext context) {
    return BackHandler(
      onBack: onUndo,
      // IntrinsicWidth: the depleting rule stretches to the chip's width,
      // and the chip sits in an unbounded Row.
      child: IntrinsicWidth(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: (_barHeight - 3).du(context),
              child: FocusableSurface(
                onClick: onUndo,
                focusNode: focusNode,
                shape: _chipShape(context),
                colors: _chipColors,
                border: _chipBorder,
                child: Padding(
                  padding: EdgeInsetsDirectional.only(
                    start: 22.du(context),
                    end: 10.du(context),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppIcon(
                        PhosphorIconsRegular.bookmarkSimple,
                        size: 22,
                        tint: AppColors.accent300,
                      ),
                      SizedBox(width: 18.du(context)),
                      AppText(
                        'Took $title off the list',
                        style: AppTypography.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(width: 18.du(context)),
                      Container(
                        height: 42.du(context),
                        padding: EdgeInsets.symmetric(
                          horizontal: 20.du(context),
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(
                            AppShape.radiusSm.du(context),
                          ),
                          border: Border.all(
                            color: AppColors.accent,
                            width: AppShape.borderWidth.du(context),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const AppIcon(
                              PhosphorIconsRegular.arrowCounterClockwise,
                              size: 20,
                            ),
                            SizedBox(width: 10.du(context)),
                            AppText(
                              'Undo',
                              style: AppTypography.caption,
                              color: null,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(2.du(context)),
              child: SizedBox(
                height: 3.du(context),
                child: ColoredBox(
                  color: AppColors.line,
                  child: FractionallySizedBox(
                    alignment: AlignmentDirectional.centerStart,
                    widthFactor: secondsLeft / _undoSeconds,
                    child: ColoredBox(color: AppColors.accent),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
