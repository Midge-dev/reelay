import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../data/media/media_models.dart';
import '../../focus/screen_memory.dart';
import '../../kit/collapse_out.dart';
import '../../kit/focusable_surface.dart';
import '../../kit/surface_style.dart';
import '../../kit/icon.dart';
import '../../kit/text.dart';
import '../../theme/phosphor_icons.dart';
import '../../theme/scale.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../common/time_format.dart';
import '../common/undo_chip.dart';
import 'poster_card.dart';

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
  final List<MediaItem> items;
  final ValueChanged<MediaItem> onSelectItem;
  final ValueChanged<MediaItem> onRemove;

  /// Whose list it is, beside the title — "Plex account · sam",
  /// "Jellyfin favorites · Loft".
  final String sourceLabel;

  /// A poster for an entry from a server (a Jellyfin favorite); null leaves
  /// only absolute artwork, which a Plex watchlist entry carries.
  final String? Function(MediaItem item)? artworkFor;

  /// ratingKey -> the connected server holding it, or null when none does
  /// (absent while still being looked up).
  final Map<String, String?> availability;

  const WatchlistScreen({
    super.key,
    required this.items,
    required this.onSelectItem,
    required this.onRemove,
    this.sourceLabel = 'Plex account',
    this.artworkFor,
    this.availability = const {},
  });

  @override
  State<WatchlistScreen> createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends State<WatchlistScreen> {
  // Screen 21, as Home does it: a hold takes a title off at once, focus
  // moves to the next title in reading order (never to the chip), and the
  // chip restates for every removal still undoable — "Took 3 titles off
  // the list" — rather than committing the one before. The server hears
  // when the eight seconds run out, or when the screen is left.

  /// Taken off, still undoable; newest last.
  final _pending = <MediaItem>[];

  /// Told to the server, but maybe still in [WatchlistScreen.items] until
  /// the list refreshes.
  final _committed = <String>{};
  int _secondsLeft = undoSeconds;
  Timer? _timer;
  final _scrollController = ScrollController();
  final _undoFocus = FocusNode(debugLabel: 'watchlist-undo');
  final _itemFocus = <String, FocusNode>{};
  _WatchlistSort _sort = _WatchlistSort.recentlyAdded;

  /// A card taken off collapses where it was, then the grid closes up
  /// (screen 21, "Gone on release").
  late final _leaving = LeavingItems<MediaItem>(idOf: (e) => e.id, onExpired: () {
    if (mounted) setState(() {});
  });

  FocusNode _focusFor(String id) => _itemFocus.putIfAbsent(id, () => FocusNode(debugLabel: 'watchlist-$id'));

  /// What's on the list now: what the screen was given, less removals.
  List<MediaItem> get _items {
    final hidden = {for (final e in _pending) e.id, ..._committed};
    return [for (final e in widget.items) if (!hidden.contains(e.id)) e];
  }

  List<MediaItem> get _sorted => switch (_sort) {
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
  void dispose() {
    // Leaving with Undo still running commits it, as Home does — it used to
    // drop the removal, and the title came back.
    _commit(rebuild: false);
    _leaving.dispose();
    _scrollController.dispose();
    _undoFocus.dispose();
    for (final node in _itemFocus.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _startRemoval(MediaItem entry) {
    // Where focus goes: the next title in reading order, else the one
    // before. Never the chip, which would put the cursor somewhere the
    // person didn't aim it (screen 21).
    final shown = _sorted;
    final at = shown.indexWhere((e) => e.id == entry.id);
    final next = at + 1 < shown.length ? shown[at + 1] : (at > 0 ? shown[at - 1] : null);
    setState(() {
      _pending.add(entry);
      _secondsLeft = undoSeconds;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Nothing left on the list: the chip is all there is to land on.
      (next != null ? _focusFor(next.id) : _undoFocus).requestFocus();
    });
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_secondsLeft <= 1) {
        _commit();
        return;
      }
      setState(() => _secondsLeft -= 1);
    });
  }

  void _commit({bool rebuild = true}) {
    _timer?.cancel();
    _timer = null;
    final done = List.of(_pending);
    _pending.clear();
    _committed.addAll(done.map((e) => e.id));
    for (final entry in done) {
      widget.onRemove(entry);
    }
    if (rebuild && mounted) setState(() {});
  }

  /// Undo — the chip, or Back while it lives — puts back the newest
  /// removal; the chip restates for the rest.
  void _undoRemoval() {
    if (_pending.isEmpty) return;
    final restored = _pending.last;
    final chipHadFocus = _undoFocus.hasFocus;
    setState(() => _pending.removeLast());
    if (_pending.isEmpty) {
      _timer?.cancel();
      _timer = null;
    }
    if (chipHadFocus && _pending.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusFor(restored.id).requestFocus();
      });
    }
  }

  String get _undoMessage =>
      _pending.length == 1 ? 'Took ${_pending.single.title} off the list' : 'Took ${_pending.length} titles off the list';

  @override
  Widget build(BuildContext context) {
    final items = _sorted;
    final missing = _items
        .where(
          (i) =>
              widget.availability.containsKey(i.id) &&
              widget.availability[i.id] == null,
        )
        .length;
    final count = [
      '${formatCount(_items.length)} title${_items.length == 1 ? '' : 's'}',
      if (missing > 0) '$missing not on your servers',
    ].join(' · ');
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
                // Flexible: with a Plex account and a Jellyfin server both,
                // the label outgrows the 960x540 canvas at the 130% default.
                Expanded(
                  child: AppText(
                    widget.sourceLabel,
                    style: AppTypography.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                SizedBox(width: 18.du(context)),
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
                  if (_pending.isNotEmpty)
                    UndoChip(
                      message: _undoMessage,
                      secondsLeft: _secondsLeft,
                      focusNode: _undoFocus,
                      onUndo: _undoRemoval,
                      height: _barHeight,
                      backTakesPrecedence: true,
                    )
                  else if (_items.isNotEmpty)
                    // Flexible: at the 130% default on a 960x540 canvas the
                    // hint is wider than the room the sort chip leaves it.
                    Flexible(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AppIcon(
                            PhosphorIconsRegular.dotOutline,
                            size: 22,
                            tint: AppColors.ink4,
                          ),
                          SizedBox(width: AppSpacing.md.du(context)),
                          Flexible(
                            child: AppText(
                              'Hold Select on a title to take it off the list',
                              style: AppTypography.caption,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(
              height: (_blockGap - AppSpacing.rowHeadroom / 2).du(context),
            ),
            Expanded(
              child: switch (_leaving.merge(items)) {
                final slots when slots.isEmpty => _buildEmptyState(),
                final slots => _buildGrid(slots),
              },
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

  Widget _buildGrid(List<Slot<MediaItem>> slots) {
    final restoring = ScreenMemory.restoringOf(context);
    return PosterGrid(
      storageId: 'watchlist',
      controller: _scrollController,
      itemCount: slots.length,
      itemBuilder: (context, i) {
        final slot = slots[i];
        final item = slot.item;
        final index = slot.index;
        final leaving = slot.leaving;
        final known = widget.availability.containsKey(item.id);
        final holder = widget.availability[item.id];
        final unavailable = known && holder == null;
        final card = PosterCard(
            imageUrl:
                widget.artworkFor?.call(item) ??
                ((item.thumb?.startsWith('http') ?? false) ? item.thumb : null),
            title: item.title,
            subtitle: [
              if (known) holder ?? 'Plex Discover',
              if (item.year != null) '${item.year}',
            ].join(' · '),
            muted: unavailable,
            marker: unavailable
                ? Row(
                    children: [
                      AppIcon(
                        PhosphorIconsRegular.cloudSlash,
                        size: 18,
                        tint: AppColors.warning,
                      ),
                      SizedBox(width: AppSpacing.sm.du(context)),
                      Flexible(
                        child: AppText(
                          'Not on your servers',
                          style: AppTypography.caption,
                          color: AppColors.warning,
                          maxLines: 1,
                        ),
                      ),
                    ],
                  )
                : null,
            focusNode: leaving ? null : _focusFor(item.id),
            autofocus: !leaving && index == 0 && _pending.isEmpty && !restoring,
            // Nothing to open for a title none of your servers hold — the
            // marker says so; holding still takes it off the list.
            onClick: unavailable ? () {} : () => widget.onSelectItem(item),
            onLongClick: leaving ? null : () => _startRemoval(item),
          );
        if (leaving) {
          // Loose in its cell, so it can narrow; then the grid reflows.
          return Align(
            key: ValueKey('leaving:${item.id}'),
            alignment: AlignmentDirectional.topStart,
            child: CollapseOut(child: card),
          );
        }
        return RememberFocus(key: ValueKey(item.id), id: 'item:${item.id}', child: card);
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
