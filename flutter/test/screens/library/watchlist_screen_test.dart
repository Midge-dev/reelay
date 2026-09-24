import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/data/plex/plex_models.dart';
import 'package:reelay/screens/library/poster_card.dart';
import 'package:reelay/screens/library/watchlist_screen.dart';

const _items = [
  PlexWatchlistItem(ratingKey: '1', title: 'Arrival', year: 2016),
  PlexWatchlistItem(ratingKey: '2', title: 'Aftershow', year: 2024),
];

Future<void> _pump(
  WidgetTester tester, {
  List<PlexWatchlistItem> items = _items,
  ValueChanged<PlexWatchlistItem>? onSelectItem,
  ValueChanged<PlexWatchlistItem>? onRemove,
  Map<String, String?> availability = const {},
}) async {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: WatchlistScreen(
        items: items,
        onSelectItem: onSelectItem ?? (_) {},
        onRemove: onRemove ?? (_) {},
        availability: availability,
      ),
    ),
  );
}

void main() {
  testWidgets('shows every saved title and the total count', (tester) async {
    await _pump(tester);

    expect(find.text('Watchlist'), findsOneWidget);
    expect(find.text('Arrival'), findsOneWidget);
    expect(find.text('Aftershow'), findsOneWidget);
    expect(find.text('2 titles'), findsOneWidget);
  });

  testWidgets('an empty watchlist shows the verbatim empty-state copy', (tester) async {
    await _pump(tester, items: const []);

    expect(find.text('Nothing saved yet — press + on anything to keep it here.'), findsOneWidget);
  });

  testWidgets('tapping a title invokes onSelectItem, newest first', (tester) async {
    PlexWatchlistItem? selected;
    await _pump(tester, onSelectItem: (e) => selected = e);

    await tester.tap(find.byType(PosterCard).first);
    await tester.pump();

    expect(selected?.ratingKey, '2', reason: 'Recently added sorts the newest (last in the account list) first');
  });

  testWidgets('holding a card removes it immediately and shows an undo chip, without calling onRemove yet', (tester) async {
    var removed = false;
    await _pump(tester, onRemove: (_) => removed = true);

    await tester.longPress(find.byType(PosterCard).first);
    await tester.pump();

    // The first card is the newest entry, Aftershow.
    expect(find.text('Aftershow'), findsNothing, reason: 'destructive-but-reversible acts immediately');
    expect(find.text('Arrival'), findsOneWidget);
    expect(find.textContaining('Undo'), findsOneWidget);
    expect(removed, isFalse, reason: 'onRemove only fires once the undo window expires');
  });

  testWidgets('holding Select on the D-pad keeps the card removed after the button is released', (tester) async {
    await _pump(tester);
    await tester.pump(); // autofocus lands on the first card

    // The hold fires while the key is still down and moves focus to the
    // undo chip; the release then arrives there and must not read as a
    // press of Undo.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(find.text('Aftershow'), findsNothing);

    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pump();

    expect(find.text('Aftershow'), findsNothing, reason: 'the release belongs to the hold, not to Undo');
    expect(find.textContaining('Undo'), findsOneWidget);

    // A fresh press on the focused chip still undoes.
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(find.text('Aftershow'), findsOneWidget);
  });

  testWidgets('pressing undo restores the card and never calls onRemove', (tester) async {
    var removed = false;
    await _pump(tester, onRemove: (_) => removed = true);

    await tester.longPress(find.byType(PosterCard).first);
    await tester.pump();
    await tester.tap(find.textContaining('Undo'));
    await tester.pump();

    expect(find.text('Aftershow'), findsOneWidget);
    expect(find.textContaining('Undo'), findsNothing);
    expect(removed, isFalse);
  });

  testWidgets('letting the undo window expire commits the removal', (tester) async {
    PlexWatchlistItem? removedEntry;
    await _pump(tester, onRemove: (e) => removedEntry = e);

    await tester.longPress(find.byType(PosterCard).first);
    await tester.pump();

    await tester.pump(const Duration(seconds: 8));

    expect(removedEntry?.ratingKey, '2');
    expect(find.textContaining('Undo'), findsNothing);
  });

  testWidgets('a title on none of your servers stays in the grid, marked, and counted (screen 20)', (tester) async {
    PlexWatchlistItem? opened;
    await _pump(tester, availability: const {'1': 'Attic', '2': null}, onSelectItem: (e) => opened = e);

    expect(find.text('Not on your servers'), findsOneWidget);
    expect(find.text('2 titles · 1 not on your servers'), findsOneWidget);
    expect(find.text('Plex Discover · 2024'), findsOneWidget);
    expect(find.text('Attic · 2016'), findsOneWidget);

    await tester.tap(find.text('Aftershow'));
    await tester.pump();
    expect(opened, isNull, reason: 'nothing to open when no server holds it');
  });
}
