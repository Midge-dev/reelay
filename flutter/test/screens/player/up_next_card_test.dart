import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/data/plex/plex_models.dart';
import 'package:reelay/screens/player/up_next_card.dart';

const _server = PlexServer(name: 'Home', baseUrl: 'http://192.168.1.5:32400', accessToken: 'tok');
const _item = PlexOnDeckItem(ratingKey: '2', type: 'episode', title: 'Fencelines', index: 5, parentIndex: 2);

Future<void> _pump(
  WidgetTester tester, {
  PlexOnDeckItem item = _item,
  VoidCallback? onPlayNow,
  VoidCallback? onDismiss,
}) async {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.bottomRight,
        child: UpNextCard(
          server: _server,
          item: item,
          onPlayNow: onPlayNow ?? () {},
          onDismiss: onDismiss ?? () {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('shows the episode number, title, and a starting countdown', (tester) async {
    await _pump(tester);

    expect(find.text('UP NEXT · EPISODE 5'), findsOneWidget);
    expect(find.text('Fencelines'), findsOneWidget);
    expect(find.text('Play in 12'), findsOneWidget);
  });

  testWidgets('the countdown ticks down every second', (tester) async {
    await _pump(tester);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Play in 11'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Play in 8'), findsOneWidget);
  });

  testWidgets('letting the countdown reach zero invokes onPlayNow', (tester) async {
    var played = false;
    await _pump(tester, onPlayNow: () => played = true);

    await tester.pump(const Duration(seconds: 12));

    expect(played, isTrue);
  });

  testWidgets('tapping "Play in N" invokes onPlayNow immediately', (tester) async {
    var played = false;
    await _pump(tester, onPlayNow: () => played = true);

    await tester.tap(find.textContaining('Play in'));
    await tester.pump();

    expect(played, isTrue);
  });

  testWidgets('tapping "Not now" invokes onDismiss', (tester) async {
    var dismissed = false;
    await _pump(tester, onDismiss: () => dismissed = true);

    await tester.tap(find.text('Not now'));
    await tester.pump();

    expect(dismissed, isTrue);
  });
}
