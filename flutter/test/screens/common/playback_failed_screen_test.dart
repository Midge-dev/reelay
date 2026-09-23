import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/data/plex/plex_models.dart';
import 'package:reelay/data/plex/plex_resources_api.dart';
import 'package:reelay/screens/common/playback_failed_screen.dart';
import 'package:reelay/state/copy_facts.dart';
import 'package:reelay/state/duplicate_fold.dart';

Future<void> _pump(
  WidgetTester tester, {
  String reason = 'Attic stopped answering partway through starting.',
  VoidCallback? onRetry,
  VoidCallback? onBack,
  String? alternateServerName,
  VoidCallback? onPlayAlternate,
  VoidCallback? onAllSources,
}) async {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: PlaybackFailedScreen(
        serverName: 'Attic',
        reason: reason,
        onRetry: onRetry ?? () {},
        onBack: onBack ?? () {},
        title: 'The Quiet Coast',
        otherCopies: alternateServerName == null ? 0 : 2,
        alternate: alternateServerName == null
            ? null
            : Sourced(
                const PlexLibraryItem(ratingKey: '9', title: 'The Quiet Coast'),
                PlexServer(name: alternateServerName, baseUrl: 'http://l', accessToken: 't'),
                ServerReachability.local,
              ),
        loadFacts: (_) async => const CopyFacts(picture: '1080p', directPlay: true),
        resumeAtMs: 46 * 60000 + 12000,
        onPlayAlternate: onPlayAlternate,
        onAllSources: onAllSources,
      ),
    ),
  );
}

void main() {
  testWidgets('names the failure plainly, never a raw exception', (tester) async {
    await _pump(tester);

    expect(find.text("COULDN'T START"), findsOneWidget);
    expect(find.text('Attic stopped answering partway through starting.'), findsOneWidget);
    expect(find.textContaining('Exception'), findsNothing);
  });

  testWidgets('tapping Try again invokes onRetry', (tester) async {
    var retried = false;
    await _pump(tester, onRetry: () => retried = true);

    await tester.tap(find.text('Try Attic again'));
    await tester.pump();

    expect(retried, isTrue);
  });

  testWidgets('tapping Back invokes onBack', (tester) async {
    var wentBack = false;
    await _pump(tester, onBack: () => wentBack = true);

    await tester.tap(find.text('Back'));
    await tester.pump();

    expect(wentBack, isTrue);
  });

  testWidgets('with no alternate source, only Try again and Back show', (tester) async {
    await _pump(tester);

    expect(find.textContaining('Play from'), findsNothing);
    expect(find.text('Try Attic again'), findsOneWidget);
  });

  testWidgets('with an alternate source, Play from X becomes primary and Try again stays available', (tester) async {
    await _pump(tester, alternateServerName: 'Loft', onPlayAlternate: () {});

    expect(find.text('Play from Loft'), findsOneWidget);
    expect(find.text('Try Attic again'), findsOneWidget);
  });

  testWidgets('the offer says what the other copy is and where you carry on', (tester) async {
    await _pump(tester, alternateServerName: 'Loft', onPlayAlternate: () {}, onAllSources: () {});
    await tester.pump();

    expect(
      find.text(
        'The Quiet Coast is on two other servers. Loft has a 1080p copy this '
        'television can play directly, and you would carry on from 46:12.',
      ),
      findsOneWidget,
    );
    expect(find.text('Plex · local · answered just now'), findsOneWidget);
    expect(find.text('Direct play'), findsOneWidget);
    expect(find.text('All sources'), findsOneWidget);
    expect(find.text('Back'), findsNothing);
  });

  testWidgets('tapping Play from X invokes onPlayAlternate', (tester) async {
    var playedAlternate = false;
    await _pump(tester, alternateServerName: 'Loft', onPlayAlternate: () => playedAlternate = true);

    await tester.tap(find.text('Play from Loft'));
    await tester.pump();

    expect(playedAlternate, isTrue);
  });
}
