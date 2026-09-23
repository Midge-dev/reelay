/// Plex wraps every list response as `{"MediaContainer": {"<Key>": [...]}}`
/// (Directory/Metadata/Hub depending on endpoint) — one helper instead of
/// a wrapper class per response shape.
List<T> extractMediaContainerList<T>(
  Map<String, dynamic> json,
  String key,
  T Function(Map<String, dynamic>) fromJson,
) {
  final container = json['MediaContainer'] as Map<String, dynamic>? ?? const {};
  final list = container[key] as List<dynamic>? ?? const [];
  return list.map((e) => fromJson(e as Map<String, dynamic>)).toList();
}

Map<String, dynamic>? extractMediaContainer(Map<String, dynamic> json) {
  return json['MediaContainer'] as Map<String, dynamic>?;
}
