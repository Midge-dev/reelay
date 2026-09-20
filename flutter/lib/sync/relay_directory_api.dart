import 'package:dio/dio.dart';

import 'relay_protocol.dart';
import 'relay_urls.dart';

const _ambientTimeoutMs = 5000;
const _tolerantTimeoutMs = 75000;

class RelayDirectoryApi {
  final Dio _client = Dio(BaseOptions(
    connectTimeout: const Duration(milliseconds: _ambientTimeoutMs),
    receiveTimeout: const Duration(milliseconds: _ambientTimeoutMs),
  ));

  Future<List<RelayRoomSummary>> listRooms(String relayUrl) async {
    final url = relayHttpUrl(relayUrl);
    if (url == null) return const [];
    final fullUrl = '${url.base}/rooms${url.query != null ? '?${url.query}' : ''}';
    try {
      final response = await _client.get<List<dynamic>>(fullUrl);
      return (response.data ?? const []).map((e) => RelayRoomSummary.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<bool> testReachable(String relayUrl) async {
    final url = relayHttpUrl(relayUrl);
    if (url == null) return false;
    try {
      final response = await _client.get<void>(url.base);
      return _isSuccess(response.statusCode);
    } catch (_) {
      return false;
    }
  }

  Future<bool> testReachableTolerant(String relayUrl) async {
    final url = relayHttpUrl(relayUrl);
    if (url == null) return false;
    try {
      final response = await _client.get<void>(
        url.base,
        options: Options(receiveTimeout: const Duration(milliseconds: _tolerantTimeoutMs)),
      );
      return _isSuccess(response.statusCode);
    } catch (_) {
      return false;
    }
  }

  Future<bool> closeRoom(String relayUrl, String roomId, String peerId, String reconnectToken) async {
    final url = relayHttpUrl(relayUrl);
    if (url == null) return false;
    final fullUrl = '${url.base}/rooms/$roomId/close${url.query != null ? '?${url.query}' : ''}';
    try {
      final response = await _client.post<void>(
        fullUrl,
        data: {'peerId': peerId, 'reconnectToken': reconnectToken},
      );
      return _isSuccess(response.statusCode);
    } catch (_) {
      return false;
    }
  }

  bool _isSuccess(int? statusCode) => statusCode != null && statusCode >= 200 && statusCode < 300;
}
