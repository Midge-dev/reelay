import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../data/plex/plex_models.dart';
import '../../kit/edge_fade_row.dart';
import '../../kit/icon.dart';
import '../../kit/text.dart';
import '../../theme/phosphor_icons.dart';
import '../../theme/scale.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import 'poster_card.dart';

const _gridColumns = 7;
const _posterCardHeight = 310.0;
const _undoSeconds = 8;

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

  const WatchlistScreen({
    super.key,
    required this.items,
    required this.onSelectItem,
    required this.onRemove,
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
    return ColoredBox(
      color: AppColors.background,
      child: Padding(
        padding: EdgeInsets.fromLTRB(32.du(context), 24.du(context), 32.du(context), 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                AppText('Watchlist', style: AppTypography.title1),
                const Spacer(),
                if (_pendingRemoval != null)
                  _UndoChip(secondsLeft: _secondsLeft, onUndo: _undoRemoval)
                else
                  AppText(
                    '${_items.length} title${_items.length == 1 ? '' : 's'}',
                    color: AppColors.ink3,
                  ),
              ],
            ),
            SizedBox(height: 22.du(context)),
            Expanded(child: _items.isEmpty ? _buildEmptyState() : _buildGrid()),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: EdgeInsets.only(top: 24.du(context)),
      child: const AppText(
        'Nothing saved yet — press + on anything to keep it here.',
      ),
    );
  }

  Widget _buildGrid() {
    return ClipRect(
      child: AnimatedBuilder(
        animation: _scrollController,
        builder: (context, child) => EdgeFadeRow(
          axis: Axis.vertical,
          fadeStart:
              _scrollController.hasClients && _scrollController.offset > 0,
          fadeWidth: posterRowPeekExtent,
          child: child!,
        ),
        child: GridView.builder(
          controller: _scrollController,
          padding: EdgeInsets.only(bottom: 48.du(context)),
          clipBehavior: Clip.none,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: _gridColumns,
            mainAxisSpacing: 24.du(context),
            crossAxisSpacing: 24.du(context),
            mainAxisExtent: _posterCardHeight.du(context),
          ),
          itemCount: _items.length,
          itemBuilder: (context, index) {
            final item = _items[index];
            return PosterCard(
              key: ValueKey(item.ratingKey),
              imageUrl: (item.thumb?.startsWith('http') ?? false)
                  ? item.thumb
                  : null,
              title: item.title,
              subtitle: item.year?.toString(),
              autofocus: index == 0,
              onClick: () => widget.onSelectItem(item),
              onLongClick: () => _startRemoval(item),
            );
          },
        ),
      ),
    );
  }
}

class _UndoChip extends StatelessWidget {
  final int secondsLeft;
  final VoidCallback onUndo;

  const _UndoChip({required this.secondsLeft, required this.onUndo});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onUndo,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: AppSpacing.lg.du(context),
          vertical: AppSpacing.sm.du(context),
        ),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.lineStrong),
          borderRadius: BorderRadius.circular(AppShape.radiusMd.du(context)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(
              PhosphorIconsRegular.arrowCounterClockwise,
              size: 18,
              tint: AppColors.accent300,
            ),
            SizedBox(width: AppSpacing.sm.du(context)),
            AppText(
              'Removed · Undo ($secondsLeft)',
              color: AppColors.accent300,
            ),
          ],
        ),
      ),
    );
  }
}
