import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../data/plex/plex_image_url.dart';
import '../../data/plex/plex_models.dart';
import '../../data/plex/plex_resources_api.dart' show ReachableServer;
import '../../focus/back_handler.dart';
import '../../focus/screen_memory.dart';
import '../../kit/filter_chip.dart';
import '../../kit/text.dart';
import '../../state/duplicate_fold.dart';
import '../../state/person_credits.dart';
import '../../theme/scale.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../common/artwork.dart';
import 'poster_card.dart';

const _circle = 130.0;
// Title details are fetched for every credit; a few at a time keeps a
// remote server responsive while the captions fill in.
const _creditFetchesAtOnce = 6;

enum _Split { everything, appearsIn, directed }

/// Screen 03c — everything a person is in, across every connected server.
/// Captions carry what they did on each title (the character, else the
/// job), and chips split the same list by that — "directed by" and
/// "appears in" are different questions. Only titles actually on your
/// servers: a search of what you own, not a biography.
class PersonFilmographyScreen extends StatefulWidget {
  final List<ReachableServer> servers;
  final PlexServer originServer;
  final PlexPerson person;
  final Future<List<FoldedWork<PlexLibraryItem>>> Function() loadWorks;
  final Future<PersonCredit?> Function(FoldedWork<PlexLibraryItem>) loadCredit;
  final ValueChanged<FoldedWork<PlexLibraryItem>> onSelectItem;
  final VoidCallback onBack;

  const PersonFilmographyScreen({
    super.key,
    required this.servers,
    required this.originServer,
    required this.person,
    required this.loadWorks,
    required this.loadCredit,
    required this.onSelectItem,
    required this.onBack,
  });

  @override
  State<PersonFilmographyScreen> createState() =>
      _PersonFilmographyScreenState();
}

/// What the page keeps in its ScreenMemory besides focus and scroll.
class _Loaded {
  final List<FoldedWork<PlexLibraryItem>> works;
  final Map<String, PersonCredit?> credits;
  final _Split split;

  const _Loaded(this.works, this.credits, this.split);
}

class _PersonFilmographyScreenState extends State<PersonFilmographyScreen> {
  List<FoldedWork<PlexLibraryItem>>? _works;
  final _credits = <String, PersonCredit?>{};
  _Split _split = _Split.everything;

  static String _key(FoldedWork<PlexLibraryItem> w) =>
      '${w.primary.server.machineIdentifier}:${w.primary.value.ratingKey}';

  @override
  void initState() {
    super.initState();
    final kept = ScreenMemory.read<_Loaded>(context, 'person.loaded');
    if (kept != null) {
      _works = kept.works;
      _credits.addAll(kept.credits);
      _split = kept.split;
      if (_credits.length < kept.works.length) unawaited(_loadCredits());
    } else {
      unawaited(_load());
    }
  }

  void _remember() {
    final works = _works;
    if (works == null) return;
    ScreenMemory.write(
      context,
      'person.loaded',
      _Loaded(works, Map.of(_credits), _split),
    );
  }

  Future<void> _load() async {
    List<FoldedWork<PlexLibraryItem>> works;
    try {
      works = await widget.loadWorks();
    } catch (_) {
      works = const [];
    }
    if (!mounted) return;
    setState(() => _works = works);
    await _loadCredits();
  }

  Future<void> _loadCredits() async {
    final pending = [
      for (final w in _works ?? const <FoldedWork<PlexLibraryItem>>[])
        if (!_credits.containsKey(_key(w))) w,
    ];
    var next = 0;
    Future<void> worker() async {
      while (next < pending.length) {
        final work = pending[next++];
        PersonCredit? credit;
        try {
          credit = await widget.loadCredit(work);
        } catch (_) {}
        if (!mounted) return;
        setState(() => _credits[_key(work)] = credit);
      }
    }

    await Future.wait(List.generate(_creditFetchesAtOnce, (_) => worker()));
  }

  bool _matches(FoldedWork<PlexLibraryItem> w, _Split split) {
    final credit = _credits[_key(w)];
    return switch (split) {
      _Split.everything => true,
      _Split.appearsIn => credit?.acted ?? false,
      _Split.directed => credit?.directed ?? false,
    };
  }

  /// "Attic", "Attic and Loft", "Attic, Loft and Marcus's server".
  String _serverList(List<FoldedWork<PlexLibraryItem>> works) {
    final present = {
      for (final w in works)
        for (final c in w.copies) c.server.machineIdentifier,
    };
    final names = [
      for (final s in widget.servers)
        if (present.contains(s.server.machineIdentifier)) s.server.name,
    ];
    if (names.length <= 1) return names.join();
    return '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
  }

  /// The credit follows the chip: under Directed a cameo in their own film
  /// still reads "Director"; under Appears in it's the character.
  String _caption(FoldedWork<PlexLibraryItem> w, _Split split) {
    final item = w.primary.value;
    final credit = _credits[_key(w)];
    final what = switch (split) {
      _Split.directed => 'Director',
      _ => credit?.label,
    };
    final when = item.type == 'show'
        ? (item.childCount != null
              ? '${item.childCount} season${item.childCount == 1 ? '' : 's'}'
              : null)
        : item.year?.toString();
    return [?what, ?when].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    _remember();
    final works = _works;
    final total = works?.length ?? 0;
    final creditsIn = works != null && _credits.length >= works.length;
    final appearsIn =
        works?.where((w) => _matches(w, _Split.appearsIn)).length ?? 0;
    final directed =
        works?.where((w) => _matches(w, _Split.directed)).length ?? 0;
    // The chips only appear for someone who both acted and directed —
    // for anyone else there is nothing to split, so no chips at all.
    final splits = <(_Split, String)>[
      if (creditsIn && appearsIn > 0 && directed > 0) ...[
        (_Split.appearsIn, 'Appears in · $appearsIn'),
        (_Split.directed, 'Directed · $directed'),
      ],
    ];
    final split = splits.any((s) => s.$1 == _split)
        ? _split
        : _Split.everything;
    final shown = [
      for (final w in works ?? const <FoldedWork<PlexLibraryItem>>[])
        if (_matches(w, split)) w,
    ];

    final subtitle = works == null
        ? 'Looking across your servers…'
        : total == 0
        ? 'Nothing of theirs is on your servers'
        : '$total title${total == 1 ? '' : 's'} on ${_serverList(works)}';

    return BackHandler(
      onBack: widget.onBack,
      child: ColoredBox(
        color: AppColors.background,
        child: Padding(
          // 03c: 48 from the rail, 56 from the top; the grid runs to the
          // right edge.
          padding: EdgeInsets.only(
            left: AppSpacing.safeX.du(context),
            top: 56.du(context),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.only(right: 80.du(context)),
                child: Row(
                  children: [
                    _PersonCircle(
                      server: widget.originServer,
                      person: widget.person,
                    ),
                    SizedBox(width: 28.du(context)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AppText(
                            widget.person.tag,
                            style: AppTypography.title1,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          SizedBox(height: 6.du(context)),
                          AppText(
                            subtitle,
                            style: AppTypography.caption,
                            color: AppColors.ink3,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    if (splits.isNotEmpty) ...[
                      SizedBox(width: 28.du(context)),
                      for (final (i, (value, label)) in [
                        (_Split.everything, 'Everything · $total'),
                        ...splits,
                      ].indexed) ...[
                        if (i > 0) SizedBox(width: 12.du(context)),
                        RememberFocus(
                          id: 'split:${value.name}',
                          child: AppFilterChip(
                            selected: value == split,
                            onClick: () => setState(() => _split = value),
                            child: AppText(
                              label,
                              style: AppTypography.caption,
                              color: null,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
              SizedBox(height: 30.du(context)),
              Expanded(
                child: PosterGrid(
                  storageId: 'filmography-${split.name}',
                  itemCount: shown.length,
                  itemBuilder: (context, index) {
                    final work = shown[index];
                    final key = _key(work);
                    return RememberFocus(
                      key: ValueKey(key),
                      id: 'item:$key',
                      child: PosterCard(
                        imageUrl: PlexImageUrl.of(
                          work.primary.server,
                          work.primary.value.thumb,
                        ),
                        title: work.primary.value.title,
                        subtitle: _caption(work, split),
                        autofocus:
                            index == 0 && !ScreenMemory.restoringOf(context),
                        onClick: () => widget.onSelectItem(work),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PersonCircle extends StatelessWidget {
  final PlexServer server;
  final PlexPerson person;

  const _PersonCircle({required this.server, required this.person});

  @override
  Widget build(BuildContext context) {
    final thumb = person.thumb;
    final url = thumb == null
        ? null
        : thumb.startsWith('http')
        ? thumb
        : PlexImageUrl.of(server, thumb);
    return Container(
      width: _circle.du(context),
      height: _circle.du(context),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.surfaceOverlay,
        border: Border.all(
          color: AppColors.lineStrong,
          width: AppShape.borderWidth.du(context),
        ),
      ),
      child: ClipOval(
        child: url != null
            ? Artwork(imageUrl: url)
            : Center(
                child: AppText(
                  person.tag.isNotEmpty ? person.tag[0].toUpperCase() : '?',
                  style: AppTypography.title1,
                  color: AppColors.ink3,
                ),
              ),
      ),
    );
  }
}
