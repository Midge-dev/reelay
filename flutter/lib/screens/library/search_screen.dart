import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../theme/phosphor_icons.dart';

import '../../data/plex/plex_models.dart';
import '../../data/plex/plex_resources_api.dart' show ReachableServer;
import '../../focus/back_handler.dart';
import '../../kit/icon.dart';
import '../../kit/text.dart';
import '../../state/duplicate_fold.dart';
import '../../theme/scale.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../../data/plex/plex_image_url.dart';
import '../../kit/edge_fade_row.dart';
import '../common/time_format.dart';
import 'poster_card.dart';
import 'search_keyboard.dart';

const _leftColumnWidth = 440.0;
const _queryFieldHeight = 64.0;
const _searchDebounce = Duration(milliseconds: 350);

/// Screen 05 — Search, global across every connected server. The on-screen
/// keyboard sits where the D-pad already is and never loses focus to the
/// results; results reflow as a side effect of typing, grouped by kind,
/// each labelled with the server it lives on.
class SearchScreen extends StatefulWidget {
  final List<ReachableServer> servers;
  final Future<List<FoldedWork<PlexOnDeckItem>>> Function(String query) search;
  final ValueChanged<FoldedWork<PlexOnDeckItem>> onSelectResult;
  final VoidCallback onBack;

  const SearchScreen({
    super.key,
    required this.servers,
    required this.search,
    required this.onSelectResult,
    required this.onBack,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _firstKeyFocus = FocusNode(debugLabel: 'search-first-key');
  String _query = '';
  List<FoldedWork<PlexOnDeckItem>> _results = const [];
  bool _searching = false;
  int _requestId = 0;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _firstKeyFocus.requestFocus(),
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _firstKeyFocus.dispose();
    super.dispose();
  }

  void _onQueryChanged(String query) {
    setState(() => _query = query);
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _results = const [];
        _searching = false;
      });
      return;
    }
    _debounce = Timer(_searchDebounce, () => _runSearch(query));
  }

  Future<void> _runSearch(String query) async {
    final requestId = ++_requestId;
    setState(() => _searching = true);
    List<FoldedWork<PlexOnDeckItem>> results;
    try {
      results = await widget.search(query);
    } catch (_) {
      results = const [];
    }
    if (!mounted || requestId != _requestId) return;
    setState(() {
      _results = results;
      _searching = false;
    });
  }

  void _onChar(String c) => _onQueryChanged(_query + c);
  void _onBackspace() => _onQueryChanged(
    _query.isEmpty ? '' : _query.substring(0, _query.length - 1),
  );
  void _onClear() => _onQueryChanged('');

  @override
  Widget build(BuildContext context) {
    final trimmed = _query.trim();
    final shows = _results
        .where((r) => r.primary.value.type == 'show')
        .toList();
    final movies = _results
        .where((r) => r.primary.value.type == 'movie')
        .toList();

    return BackHandler(
      onBack: widget.onBack,
      child: ColoredBox(
        color: AppColors.background,
        child: Padding(
          // Screen 05: 64 du from the top, 48 from the rail, 56 from the
          // results. The keyboard column is narrower than the design's 560
          // — at full size it dominated the screen.
          padding: EdgeInsets.fromLTRB(
            AppSpacing.safeX.du(context),
            64.du(context),
            0,
            AppSpacing.safeY.du(context),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: _leftColumnWidth.du(context),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _QueryField(query: _query),
                    SizedBox(height: AppSpacing.xl.du(context)),
                    SearchKeyboard(
                      onChar: _onChar,
                      onBackspace: _onBackspace,
                      onClear: _onClear,
                      firstKeyFocusNode: _firstKeyFocus,
                    ),
                  ],
                ),
              ),
              SizedBox(width: 56.du(context)),
              Expanded(
                child: _ResultsPanel(
                  servers: widget.servers,
                  query: trimmed,
                  searching: _searching,
                  shows: shows,
                  movies: movies,
                  onSelect: widget.onSelectResult,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QueryField extends StatelessWidget {
  final String query;

  const _QueryField({required this.query});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _queryFieldHeight.du(context),
      padding: EdgeInsets.symmetric(horizontal: AppSpacing.xl.du(context)),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(
          color: AppColors.line,
          width: AppShape.borderWidth.du(context),
        ),
        borderRadius: BorderRadius.circular(AppShape.radiusMd.du(context)),
      ),
      child: Row(
        children: [
          AppIcon(
            PhosphorIconsRegular.magnifyingGlass,
            size: 24,
            tint: AppColors.ink3,
          ),
          SizedBox(width: 14.du(context)),
          Flexible(
            child: AppText(
              query.isEmpty ? 'Type a title' : query,
              style: AppTypography.rowLabel.copyWith(
                fontWeight: FontWeight.w400,
              ),
              color: query.isEmpty ? AppColors.ink3 : AppColors.ink,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // The caret sits right after the text, where the next letter goes.
          SizedBox(width: AppSpacing.xs.du(context)),
          Container(
            width: 2.du(context),
            height: 30.du(context),
            color: AppColors.accent,
          ),
        ],
      ),
    );
  }
}

class _ResultsPanel extends StatelessWidget {
  final List<ReachableServer> servers;
  final String query;
  final bool searching;
  final List<FoldedWork<PlexOnDeckItem>> shows;
  final List<FoldedWork<PlexOnDeckItem>> movies;
  final ValueChanged<FoldedWork<PlexOnDeckItem>> onSelect;

  const _ResultsPanel({
    required this.servers,
    required this.query,
    required this.searching,
    required this.shows,
    required this.movies,
    required this.onSelect,
  });

  /// "across Attic and Loft" / "on Attic".
  String get _serverLabel {
    final names = {
      for (final item in [...shows, ...movies]) item.primary.server.name,
    }.toList();
    if (names.length == 1) return 'on ${names.single}';
    if (names.length == 2) return 'across ${names[0]} and ${names[1]}';
    return 'across ${names.length} servers';
  }

  @override
  Widget build(BuildContext context) {
    if (query.isEmpty) return const SizedBox.shrink();

    final total = shows.length + movies.length;
    if (!searching && total == 0) {
      // Verbatim from the handoff's copy list.
      return AppText(
        'Nothing on your servers matches that.',
        style: AppTypography.body,
      );
    }

    return SingleChildScrollView(
      clipBehavior: Clip.none,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              AppText(
                searching
                    ? 'Searching…'
                    : '${formatCount(total)} result${total == 1 ? '' : 's'}',
                style: AppTypography.rowLabel,
              ),
              if (!searching) ...[
                SizedBox(width: AppSpacing.lg.du(context)),
                Flexible(
                  child: AppText(
                    _serverLabel,
                    style: AppTypography.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
          if (shows.isNotEmpty)
            _ResultGroup(label: 'SERIES', items: shows, onSelect: onSelect),
          if (movies.isNotEmpty)
            _ResultGroup(label: 'MOVIES', items: movies, onSelect: onSelect),
        ],
      ),
    );
  }
}

/// One kind of result: a micro kicker, then a row of full-size posters
/// captioned with where each lives and a year or season count.
class _ResultGroup extends StatefulWidget {
  final String label;
  final List<FoldedWork<PlexOnDeckItem>> items;
  final ValueChanged<FoldedWork<PlexOnDeckItem>> onSelect;

  const _ResultGroup({
    required this.label,
    required this.items,
    required this.onSelect,
  });

  @override
  State<_ResultGroup> createState() => _ResultGroupState();
}

class _ResultGroupState extends State<_ResultGroup> {
  // The row starts flush against the keyboard column, so its leading edge
  // only fades once it has actually scrolled.
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  static String _caption(FoldedWork<PlexOnDeckItem> work) {
    final v = work.primary.value;
    final detail = switch (v.type) {
      'show' when v.childCount != null =>
        '${v.childCount} season${v.childCount == 1 ? '' : 's'}',
      _ when v.year != null => '${v.year}',
      _ => null,
    };
    return [work.primary.server.name, ?detail].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: AppSpacing.lg.du(context)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          AppText(widget.label, style: AppTypography.micro),
          SizedBox(height: (14 - AppSpacing.rowHeadroom / 2).du(context)),
          SizedBox(
            height: (posterCardExtent + AppSpacing.rowHeadroom).du(context),
            // Clip at the row's leading edge — scrolled-away cards used to
            // paint over the keyboard — leaving a sliver for a focused
            // first card's scale and frame. Vertically nothing is clipped.
            child: ClipRect(
              clipper: _LeadingEdgeClipper(12.du(context)),
              child: AnimatedBuilder(
                animation: _scroll,
                builder: (context, child) => EdgeFadeRow(
                  fadeStart: _scroll.hasClients && _scroll.offset > 0,
                  child: child!,
                ),
                child: ListView.separated(
                  controller: _scroll,
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  padding: EdgeInsets.only(
                    right: AppSpacing.safeX.du(context),
                    top: (AppSpacing.rowHeadroom / 2).du(context),
                    bottom: (AppSpacing.rowHeadroom / 2).du(context),
                  ),
                  itemCount: widget.items.length,
                  separatorBuilder: (context, index) =>
                      SizedBox(width: AppSpacing.cardGap.du(context)),
                  itemBuilder: (context, index) {
                    final item = widget.items[index];
                    return PosterCard(
                      key: ValueKey(
                        '${item.primary.server.machineIdentifier}:${item.primary.value.ratingKey}',
                      ),
                      imageUrl: PlexImageUrl.of(
                        item.primary.server,
                        item.primary.value.thumb,
                      ),
                      title: item.primary.value.title,
                      subtitle: _caption(item),
                      onClick: () => widget.onSelect(item),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Clips only the leading edge (less [bleed]); every other side is open.
class _LeadingEdgeClipper extends CustomClipper<Rect> {
  final double bleed;

  const _LeadingEdgeClipper(this.bleed);

  @override
  Rect getClip(Size size) => Rect.fromLTRB(
    -bleed,
    -size.height,
    size.width + size.width,
    size.height * 2,
  );

  @override
  bool shouldReclip(_LeadingEdgeClipper old) => old.bleed != bleed;
}
