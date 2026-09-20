class RelayHttpUrl {
  final String base;
  final String? query;

  const RelayHttpUrl({required this.base, this.query});
}

RelayHttpUrl? relayHttpUrl(String relayUrl) {
  String httpScheme;
  String rest;
  if (relayUrl.startsWith('wss://')) {
    httpScheme = 'https://';
    rest = relayUrl.substring('wss://'.length);
  } else if (relayUrl.startsWith('ws://')) {
    httpScheme = 'http://';
    rest = relayUrl.substring('ws://'.length);
  } else {
    return null;
  }

  final hostAndPort = rest.split('/').first.split('?').first;
  if (hostAndPort.trim().isEmpty) return null;

  final queryIndex = rest.indexOf('?');
  final query = queryIndex == -1 ? null : (rest.substring(queryIndex + 1).isEmpty ? null : rest.substring(queryIndex + 1));

  return RelayHttpUrl(base: '$httpScheme$hostAndPort', query: query);
}

/// Builds the phone-chat page URL for a room, carrying the relay's own
/// auth query string forward. Ports QrCode.kt's `relayUrlToChatUrl`.
String? relayUrlToChatUrl(String relayUrl, String roomId, String defaultName) {
  final parsed = relayHttpUrl(relayUrl);
  if (parsed == null) return null;

  final params = <String>[
    if (parsed.query != null) parsed.query!,
    'room=$roomId',
    if (defaultName.trim().isNotEmpty) 'name=${Uri.encodeQueryComponent(defaultName)}',
  ];
  return '${parsed.base}/chat?${params.join('&')}';
}
