import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reelay/data/plex/plex_models.dart';
import 'package:reelay/kit/card.dart';
import 'package:reelay/screens/library/show_episodes_screen.dart';

const _server = PlexServer(name: 'Home', baseUrl: 'http://192.168.1.5:32400', accessToken: 'tok');

void main() {
  testWidgets('shows the show/season titles and every episode heading', (tester) async {
    PlexEpisode? selected;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ShowEpisodesScreen(
          server: _server,
          showTitle: 'Severance',
          seasonTitle: 'Season 1',
          episodes: const [
            PlexEpisode(ratingKey: 'e1', title: 'Good News About Hell', index: 1),
            PlexEpisode(ratingKey: 'e2', title: 'Half Loop', index: 2),
          ],
          onSelect: (e) => selected = e,
          onBack: () {},
        ),
      ),
    );

    expect(find.text('Severance'), findsOneWidget);
    expect(find.text('Season 1'), findsOneWidget);
    expect(find.text('1. Good News About Hell'), findsOneWidget);
    expect(find.text('2. Half Loop'), findsOneWidget);

    // The episode heading is a sibling of the clickable card (a thumbnail
    // + text side by side in a Row), not an ancestor — tap the card itself.
    await tester.tap(find.byType(AppCard).at(1));
    await tester.pump();
    expect(selected?.ratingKey, 'e2');
  });
}
