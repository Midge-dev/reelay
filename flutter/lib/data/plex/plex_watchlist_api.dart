import 'package:dio/dio.dart';

import 'plex_http_client.dart';
import 'plex_models.dart';
import 'plex_response.dart';

/// Client for Plex's account-level Watchlist, which lives in the Discover
/// metadata universe (discover.provider.plex.tv) rather than on any local
/// server — the same reverse-engineered API python-plexapi's
/// MyPlexAccount.watchlist()/addToWatchlist() use. A watchlist item's guid
/// (`plex://movie/&lt;id&gt;`) is what ties it back to a local
/// PlexLibraryItem with the same guid; the trailing id is also the
/// Discover ratingKey these actions expect.
class PlexWatchlistApi {
  final String clientIdentifier;
  final Dio _client = plexHttpClient();

  PlexWatchlistApi(this.clientIdentifier);

  Options _headers(String accountToken) => Options(headers: {
        'X-Plex-Product': 'Reelay',
        'X-Plex-Client-Identifier': clientIdentifier,
        'X-Plex-Token': accountToken,
      });

  String _discoverRatingKey(String guid) => guid.substring(guid.lastIndexOf('/') + 1);

  Future<List<PlexWatchlistItem>> fetchWatchlist(String accountToken) async {
    final response = await _client.get<Map<String, dynamic>>(
      'https://discover.provider.plex.tv/library/sections/watchlist/all',
      options: _headers(accountToken),
    );
    return extractMediaContainerList(response.data!, 'Metadata', PlexWatchlistItem.fromJson);
  }

  Future<void> addToWatchlist(String accountToken, String guid) async {
    await _client.put<void>(
      'https://discover.provider.plex.tv/actions/addToWatchlist?ratingKey=${_discoverRatingKey(guid)}',
      options: _headers(accountToken),
    );
  }

  Future<void> removeFromWatchlist(String accountToken, String guid) async {
    await _client.put<void>(
      'https://discover.provider.plex.tv/actions/removeFromWatchlist?ratingKey=${_discoverRatingKey(guid)}',
      options: _headers(accountToken),
    );
  }
}
