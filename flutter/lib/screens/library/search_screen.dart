import 'dart:async';

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

import '../../data/plex/plex_models.dart';
import '../../focus/back_handler.dart';
import '../../kit/icon.dart';
import '../../kit/text.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import 'movie_detail_sections.dart';
import 'search_keyboard.dart';

const _leftColumnWidth = 560.0;
const _queryFieldHeight = 76.0;
const _searchDebounce = Duration(milliseconds: 350);

/// Ports screen 05 of the Nocturne handoff. The on-screen keyboard sits
/// where the D-pad already is and never loses focus to the results —
/// results only ever reflow as a side effect of typing. Scoped to the
/// current server (no multi-server fan-out yet — see NOTES.md).
class SearchScreen extends StatefulWidget {
  final PlexServer server;
  final Future<List<PlexOnDeckItem>> Function(String query) search;
  final ValueChanged<PlexOnDeckItem> onSelectResult;
  final VoidCallback onBack;

  const SearchScreen({
    super.key,
    required this.server,
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
  List<PlexOnDeckItem> _results = const [];
  bool _searching = false;
  int _requestId = 0;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _firstKeyFocus.requestFocus());
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
    List<PlexOnDeckItem> results;
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
  void _onBackspace() => _onQueryChanged(_query.isEmpty ? '' : _query.substring(0, _query.length - 1));
  void _onClear() => _onQueryChanged('');

  @override
  Widget build(BuildContext context) {
    final trimmed = _query.trim();
    final shows = _results.where((r) => r.type == 'show').toList();
    final movies = _results.where((r) => r.type == 'movie').toList();

    return BackHandler(
      onBack: widget.onBack,
      child: ColoredBox(
        color: AppColors.background,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.xxxl, AppSpacing.xxl, AppSpacing.xxxl, AppSpacing.xl),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: _leftColumnWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _QueryField(query: _query),
                    const SizedBox(height: AppSpacing.md),
                    SearchKeyboard(onChar: _onChar, onBackspace: _onBackspace, onClear: _onClear, firstKeyFocusNode: _firstKeyFocus),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xxxl),
              Expanded(
                child: _ResultsPanel(
                  server: widget.server,
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
      height: _queryFieldHeight,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(AppShape.radiusMd),
      ),
      child: Row(
        children: [
          const AppIcon(Icons.search, size: 24, tint: AppColors.ink3),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: AppText(
              query.isEmpty ? 'Type a title…' : query,
              color: query.isEmpty ? AppColors.ink3 : AppColors.ink,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (query.isNotEmpty) Container(width: 2, height: 30, color: AppColors.accent),
        ],
      ),
    );
  }
}

class _ResultsPanel extends StatelessWidget {
  final PlexServer server;
  final String query;
  final bool searching;
  final List<PlexOnDeckItem> shows;
  final List<PlexOnDeckItem> movies;
  final ValueChanged<PlexOnDeckItem> onSelect;

  const _ResultsPanel({
    required this.server,
    required this.query,
    required this.searching,
    required this.shows,
    required this.movies,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    if (query.isEmpty) return const SizedBox.shrink();

    final total = shows.length + movies.length;
    if (!searching && total == 0) {
      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.sm),
        child: AppText('No matches for "$query".', color: AppColors.ink2),
      );
    }

    return SingleChildScrollView(
      // A results header plus two fixed-height PosterRows can exceed the
      // viewport once there's enough of each kind — scrolling degrades
      // gracefully where a fixed Column would just overflow the bottom.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              AppText(
                searching ? 'Searching…' : '$total result${total == 1 ? '' : 's'}',
                style: AppTypography.rowLabel,
              ),
              if (!searching) ...[
                const SizedBox(width: AppSpacing.md),
                // Flexible, not a bare child — a long server name can
                // otherwise reach all the way to the rail's clock overlay,
                // which ignores this screen's own right-edge padding.
                Flexible(
                  child: AppText('on ${server.name}', color: AppColors.ink3, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          if (shows.isNotEmpty) PosterRow(title: 'SERIES', items: shows, server: server, onClick: onSelect),
          if (movies.isNotEmpty) PosterRow(title: 'MOVIES', items: movies, server: server, onClick: onSelect),
        ],
      ),
    );
  }
}
