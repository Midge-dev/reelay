import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Where fetched artwork is kept between launches, by [ArtworkCache.keyFor].
abstract class ArtworkStore {
  Future<Uint8List?> read(String key);
  Future<void> write(String key, Uint8List bytes);
}

/// The app's artwork cache: posters and stills survive a restart, so a
/// saved Home (state/home_cache.dart) has its pictures at once.
///
/// Every artwork URL either backend builds is versioned — Plex's thumb
/// paths carry the image's updated-at, Jellyfin's a `tag` — so a saved copy
/// is never stale and is kept until evicted for space.
class ArtworkCache {
  ArtworkCache._();

  /// Null: no disk cache (most tests); artwork comes from the network only.
  static ArtworkStore? store;

  /// [url] without its token: tokens belong in the secure store, and the
  /// same picture shouldn't miss because a token changed.
  static String keyFor(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.queryParameters.containsKey('X-Plex-Token')) return url;
    final query = Map.of(uri.queryParameters)..remove('X-Plex-Token');
    // (replace(queryParameters: null) would keep the old query, token and all.)
    if (query.isEmpty) return '${uri.origin}${uri.path}';
    return uri.replace(queryParameters: query).toString();
  }
}

/// [NetworkImage], with [ArtworkCache.store] in front of the network.
@immutable
class CachedArtworkImage extends ImageProvider<CachedArtworkImage> {
  const CachedArtworkImage(this.url);

  final String url;

  static HttpClient? _sharedClient;
  static HttpClient get _client => _sharedClient ??= HttpClient()..autoUncompress = false;

  @override
  Future<CachedArtworkImage> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(CachedArtworkImage key, ImageDecoderCallback decode) =>
      MultiFrameImageStreamCompleter(
        codec: _load(decode),
        scale: 1,
        debugLabel: url,
        informationCollector: () => [DiagnosticsProperty<ImageProvider>('Image provider', this)],
      );

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final store = ArtworkCache.store;
    final key = ArtworkCache.keyFor(url);
    Uint8List? bytes;
    if (store != null) {
      try {
        bytes = await store.read(key);
      } catch (_) {
        bytes = null;
      }
    }
    if (bytes == null) {
      bytes = await _fetch();
      if (store != null) unawaited(store.write(key, bytes).catchError((_) {}));
    }
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  Future<Uint8List> _fetch() async {
    final uri = Uri.parse(url);
    final request = await _client.getUrl(uri);
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>().catchError((_) {});
      throw NetworkImageLoadException(statusCode: response.statusCode, uri: uri);
    }
    final bytes = await consolidateHttpClientResponseBytes(response);
    if (bytes.lengthInBytes == 0) throw Exception('CachedArtworkImage is an empty file: $uri');
    return bytes;
  }

  @override
  bool operator ==(Object other) => other is CachedArtworkImage && other.url == url;

  @override
  int get hashCode => url.hashCode;

  @override
  String toString() => '${objectRuntimeType(this, 'CachedArtworkImage')}("$url")';
}

/// Artwork kept in memory — for tests, and as a stand-in where there's no
/// disk.
class MemoryArtworkStore implements ArtworkStore {
  final _bytes = <String, Uint8List>{};

  Iterable<String> get keys => _bytes.keys;

  @override
  Future<Uint8List?> read(String key) async => _bytes[key];

  @override
  Future<void> write(String key, Uint8List bytes) async => _bytes[key] = bytes;
}

/// Artwork in files under [directory], one per key, the least recently
/// used dropped once the whole passes [maxBytes].
class FileArtworkStore implements ArtworkStore {
  FileArtworkStore(this.directory, {this.maxBytes = 150 * 1024 * 1024}) {
    unawaited(_trim().catchError((_) {}));
  }

  final Directory directory;
  final int maxBytes;

  /// Bytes written since the last trim; one runs every [_trimEvery].
  int _sinceTrim = 0;
  static const _trimEvery = 16 * 1024 * 1024;

  File _file(String key) => File('${directory.path}/${_fnv1a64(key)}');

  @override
  Future<Uint8List?> read(String key) async {
    final file = _file(key);
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    // Read is use: keep it from the next trim.
    unawaited(file.setLastModified(DateTime.now()).catchError((_) {}));
    return bytes;
  }

  @override
  Future<void> write(String key, Uint8List bytes) async {
    await directory.create(recursive: true);
    final file = _file(key);
    // Whole or not at all: a half-written file would be a broken poster
    // every launch after.
    final partial = File('${file.path}.part');
    await partial.writeAsBytes(bytes, flush: true);
    await partial.rename(file.path);
    _sinceTrim += bytes.lengthInBytes;
    if (_sinceTrim >= _trimEvery) {
      _sinceTrim = 0;
      await _trim();
    }
  }

  /// Down to three quarters of [maxBytes], oldest use first.
  Future<void> _trim() async {
    if (!await directory.exists()) return;
    final files = <(File, FileStat)>[];
    var total = 0;
    await for (final entity in directory.list()) {
      if (entity is! File) continue;
      final stat = await entity.stat();
      files.add((entity, stat));
      total += stat.size;
    }
    if (total <= maxBytes) return;
    files.sort((a, b) => a.$2.modified.compareTo(b.$2.modified));
    final target = maxBytes * 3 ~/ 4;
    for (final (file, stat) in files) {
      if (total <= target) break;
      try {
        await file.delete();
        total -= stat.size;
      } catch (_) {}
    }
  }

  /// A stable file name for [key] (String.hashCode isn't stable across
  /// runs).
  static String _fnv1a64(String key) {
    // The FNV offset basis 0xcbf29ce484222325, as a signed 64-bit int;
    // Dart's int arithmetic wraps at 64 bits, as FNV wants.
    var hash = -3750763034362895579;
    for (final unit in key.codeUnits) {
      hash ^= unit;
      hash *= 0x100000001b3;
    }
    return hash.toUnsigned(64).toRadixString(16).padLeft(16, '0');
  }
}
